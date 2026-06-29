#!/bin/bash
# Cloud-1 emergency cleanup — deletes ALL cloud1 AWS resources regardless of Terraform state.
# Use when 'terraform destroy' leaves orphaned resources (e.g. after ctrl+C'd applies).
# Run from inside the cloud1-tools container.
#
# Usage: ./docker/cloud1-cleanup.sh

set -uo pipefail
R="${AWS_DEFAULT_REGION:-eu-west-3}"
TAG="Name=tag:Project,Values=cloud1"

log()  { echo "  $*"; }
step() { echo; echo "─── $* ───"; }
ok()   { echo "  ✓ $*"; }
skip() { echo "  · (none found)"; }

echo "╔══════════════════════════════════════════════════╗"
echo "║  Cloud-1 Emergency Cleanup — region: $R  ║"
echo "╚══════════════════════════════════════════════════╝"
echo "Will delete ALL resources tagged Project=cloud1."
echo "Press Ctrl+C in the next 5s to abort."
sleep 5

# ── 0. Terraform destroy (handles in-state resources first) ───────────────────
step "Step 0: terraform destroy (in-state resources)"
if [ -f /workspace/terraform/terraform.tfstate ]; then
  cd /workspace/terraform
  terraform destroy -auto-approve 2>&1 | tail -5 || log "terraform destroy partial/failed — continuing with manual cleanup"
  cd - > /dev/null
else
  log "No terraform.tfstate found — skipping, proceeding with manual cleanup"
fi

# ── 1. Auto Scaling Group (force-deletes, terminates web instances) ────────────
step "Step 1: Auto Scaling Groups"
ASG_NAMES=$(aws autoscaling describe-auto-scaling-groups \
  --filters "Name=tag:Project,Values=cloud1" \
  --query "AutoScalingGroups[].AutoScalingGroupName" \
  --output text --region "$R" 2>/dev/null || true)
if [ -n "$ASG_NAMES" ]; then
  for asg in $ASG_NAMES; do
    log "Deleting ASG: $asg"
    aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$asg" --force-delete --region "$R" 2>/dev/null && ok "$asg deleted" || log "failed (may already be gone)"
  done
  log "Waiting 30s for ASG instances to start terminating..."
  sleep 30
else
  skip
fi

# ── 2. EC2 instances (lb, db, web) ────────────────────────────────────────────
step "Step 2: EC2 instances"
IDS=$(aws ec2 describe-instances \
  --filters "$TAG" "Name=instance-state-name,Values=running,stopped,pending,stopping" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text --region "$R" 2>/dev/null || true)
if [ -n "$IDS" ]; then
  log "Terminating: $IDS"
  aws ec2 terminate-instances --instance-ids $IDS --region "$R" > /dev/null
  log "Waiting for termination (may take ~2 min)..."
  aws ec2 wait instance-terminated --instance-ids $IDS --region "$R"
  ok "All instances terminated"
else
  skip
fi

# ── 3. Elastic IPs ────────────────────────────────────────────────────────────
step "Step 3: Elastic IPs"
EIP_IDS=$(aws ec2 describe-addresses \
  --filters "$TAG" \
  --query "Addresses[].AllocationId" \
  --output text --region "$R" 2>/dev/null || true)
if [ -n "$EIP_IDS" ]; then
  for alloc in $EIP_IDS; do
    log "Releasing: $alloc"
    aws ec2 release-address --allocation-id "$alloc" --region "$R" 2>/dev/null && ok "$alloc released" || true
  done
else
  skip
fi

# ── 4. Launch Templates ───────────────────────────────────────────────────────
step "Step 4: Launch Templates"
LT_IDS=$(aws ec2 describe-launch-templates \
  --filters "Name=launch-template-name,Values=cloud1-*" \
  --query "LaunchTemplates[].LaunchTemplateId" \
  --output text --region "$R" 2>/dev/null || true)
if [ -n "$LT_IDS" ]; then
  for lt in $LT_IDS; do
    log "Deleting: $lt"
    aws ec2 delete-launch-template --launch-template-id "$lt" --region "$R" 2>/dev/null && ok "$lt deleted" || true
  done
else
  skip
fi

# ── 5. EFS (mount targets first, then file systems) ───────────────────────────
step "Step 5: EFS"
FS_IDS=$(aws efs describe-file-systems \
  --query "FileSystems[].FileSystemId" \
  --output text --region "$R" 2>/dev/null || true)
for fs_id in $FS_IDS; do
  PROJ=$(aws efs list-tags-for-resource --resource-id "$fs_id" --region "$R" \
    --query "Tags[?Key=='Project'].Value" --output text 2>/dev/null || true)
  if [ "$PROJ" = "cloud1" ]; then
    MT_IDS=$(aws efs describe-mount-targets --file-system-id "$fs_id" --region "$R" \
      --query "MountTargets[].MountTargetId" --output text 2>/dev/null || true)
    for mt in $MT_IDS; do
      log "Deleting mount target: $mt"
      aws efs delete-mount-target --mount-target-id "$mt" --region "$R" 2>/dev/null || true
    done
    if [ -n "$MT_IDS" ]; then
      log "Waiting for mount targets to delete..."
      until [ -z "$(aws efs describe-mount-targets --file-system-id "$fs_id" --region "$R" \
        --query "MountTargets[].MountTargetId" --output text 2>/dev/null)" ]; do
        sleep 5
      done
    fi
    log "Deleting EFS: $fs_id"
    aws efs delete-file-system --file-system-id "$fs_id" --region "$R" 2>/dev/null && ok "$fs_id deleted" || true
  fi
done
[ -z "$FS_IDS" ] && skip

# ── 6. S3 buckets (delete all versions, then bucket) ─────────────────────────
step "Step 6: S3 buckets"
BUCKETS=$(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, 'cloud1-')].Name" \
  --output text 2>/dev/null || true)
if [ -n "$BUCKETS" ]; then
  for bucket in $BUCKETS; do
    log "Emptying and deleting: $bucket"
    python3 - "$bucket" <<'PYEOF'
import boto3, sys
bucket_name = sys.argv[1]
s3 = boto3.resource('s3')
bucket = s3.Bucket(bucket_name)
bucket.object_versions.delete()
bucket.delete()
print(f"  ✓ {bucket_name} deleted")
PYEOF
  done
else
  skip
fi

# ── 7. CloudWatch alarms ──────────────────────────────────────────────────────
step "Step 7: CloudWatch alarms"
ALARMS=$(aws cloudwatch describe-alarms \
  --alarm-name-prefix "cloud1-" \
  --query "MetricAlarms[].AlarmName" \
  --output text --region "$R" 2>/dev/null || true)
if [ -n "$ALARMS" ]; then
  aws cloudwatch delete-alarms --alarm-names $ALARMS --region "$R" && ok "Alarms deleted"
else
  skip
fi

# ── 8. SNS topics ─────────────────────────────────────────────────────────────
step "Step 8: SNS topics"
TOPIC_ARNS=$(aws sns list-topics --region "$R" \
  --query "Topics[?contains(TopicArn, 'cloud1')].TopicArn" \
  --output text 2>/dev/null || true)
if [ -n "$TOPIC_ARNS" ]; then
  for arn in $TOPIC_ARNS; do
    log "Deleting: $arn"
    aws sns delete-topic --topic-arn "$arn" --region "$R" 2>/dev/null && ok "deleted" || true
  done
else
  skip
fi

# ── 9. Security Groups ────────────────────────────────────────────────────────
step "Step 9: Security Groups"
SG_IDS=$(aws ec2 describe-security-groups \
  --filters "$TAG" \
  --query "SecurityGroups[].GroupId" \
  --output text --region "$R" 2>/dev/null || true)
if [ -n "$SG_IDS" ]; then
  for sg in $SG_IDS; do
    log "Deleting SG: $sg"
    aws ec2 delete-security-group --group-id "$sg" --region "$R" 2>/dev/null && ok "$sg deleted" || log "$sg skipped (dependency)"
  done
else
  skip
fi

# ── 10. IAM ───────────────────────────────────────────────────────────────────
step "Step 10: IAM"
PROFILE="cloud1-web-instance-profile"
ROLE="cloud1-web-instance-role"
aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE" --role-name "$ROLE" 2>/dev/null || true
aws iam delete-instance-profile --instance-profile-name "$PROFILE" 2>/dev/null && ok "Instance profile deleted" || true
aws iam delete-role-policy --role-name "$ROLE" --policy-name "cloud1-web-s3-read" 2>/dev/null || true
aws iam delete-role --role-name "$ROLE" 2>/dev/null && ok "IAM role deleted" || true

# ── 11. CloudFront (disable → wait → delete) ──────────────────────────────────
step "Step 11: CloudFront"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
DIST_IDS=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[].Id" --output text 2>/dev/null || true)

CF_PENDING=""
for dist_id in $DIST_IDS; do
  PROJ=$(aws cloudfront list-tags-for-resource \
    --resource "arn:aws:cloudfront::${ACCOUNT}:distribution/${dist_id}" \
    --query "Tags.Items[?Key=='Project'].Value" --output text 2>/dev/null || true)
  if [ "$PROJ" = "cloud1" ]; then
    RESULT=$(aws cloudfront get-distribution --id "$dist_id" 2>/dev/null)
    ETAG=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['ETag'])")
    ENABLED=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['Distribution']['DistributionConfig']['Enabled'])")
    STATUS=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['Distribution']['Status'])")

    if [ "$STATUS" = "Deployed" ] && [ "$ENABLED" = "False" ]; then
      log "Deleting disabled distribution: $dist_id"
      aws cloudfront delete-distribution --id "$dist_id" --if-match "$ETAG" 2>/dev/null && ok "$dist_id deleted" || true
    elif [ "$ENABLED" = "True" ]; then
      log "Disabling distribution: $dist_id"
      UPDATED=$(echo "$RESULT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cfg = d['Distribution']['DistributionConfig']
cfg['Enabled'] = False
print(json.dumps(cfg))
")
      NEW_ETAG=$(aws cloudfront update-distribution \
        --id "$dist_id" --if-match "$ETAG" \
        --distribution-config "$UPDATED" \
        --query ETag --output text 2>/dev/null)
      ok "$dist_id disabled (etag: $NEW_ETAG)"
      CF_PENDING="$CF_PENDING $dist_id:$NEW_ETAG"
    else
      log "$dist_id is still deploying — will check again"
      CF_PENDING="$CF_PENDING $dist_id:$ETAG"
    fi
  fi
done
[ -z "$DIST_IDS" ] && skip

# Wait for CloudFront distributions to finish disabling, then delete
if [ -n "$CF_PENDING" ]; then
  echo ""
  log "Waiting for CloudFront distributions to finish disabling (~15 min)..."
  for entry in $CF_PENDING; do
    dist_id="${entry%%:*}"
    etag="${entry##*:}"
    log "Polling $dist_id..."
    until [ "$(aws cloudfront get-distribution --id "$dist_id" \
      --query "Distribution.Status" --output text 2>/dev/null)" = "Deployed" ]; do
      sleep 30
      printf "."
    done
    echo ""
    aws cloudfront delete-distribution --id "$dist_id" --if-match "$etag" 2>/dev/null \
      && ok "$dist_id deleted" || log "Failed to delete $dist_id — retry: aws cloudfront delete-distribution --id $dist_id --if-match $etag"
  done
fi

echo ""
echo "╔════════════════════════════════════╗"
echo "║  Cleanup complete!                 ║"
echo "║  Run 'terraform apply' to redeploy ║"
echo "╚════════════════════════════════════╝"
