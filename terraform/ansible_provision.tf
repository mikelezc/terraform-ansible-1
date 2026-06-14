# Runs Ansible automatically after Terraform creates the infrastructure.
# This means a single "terraform apply" deploys everything end-to-end.

# Sequence:
#   1. Wait for SSH to be available on EC2-LB and EC2-DB
#   2. Wait for ASG web instances to reach InService state
#   3. Run ansible-playbook (configures Nginx LB + MariaDB)

# Re-triggers if LB IP, DB IP, or ASG name change (i.e. after terraform destroy + apply).
# For scaling events (terraform apply -var="web_desired=N"), re-run Ansible manually:
#   ansible-playbook -i inventory.ini playbook.yml -l lb

resource "null_resource" "ansible_provision" {
  depends_on = [
    local_file.ansible_inventory,
    aws_eip.lb,
    aws_instance.db,
    aws_autoscaling_group.web,
  ]

  triggers = {
    lb_ip    = aws_eip.lb.public_ip
    db_ip    = aws_instance.db.public_ip
    asg_name = aws_autoscaling_group.web.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Expand ~ in the key path (bash doesn't expand ~ inside variables)
      SSH_KEY=$(eval echo ${var.ssh_private_key_path})

      echo "=== [Ansible] Waiting for SSH on LB (${aws_eip.lb.public_ip}) ==="
      until ssh -i $SSH_KEY \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=5 \
        ubuntu@${aws_eip.lb.public_ip} true 2>/dev/null; do
        echo "  LB not ready yet, retrying in 10s..."
        sleep 10
      done
      echo "  LB SSH ready"

      echo "=== [Ansible] Waiting for SSH on DB (${aws_instance.db.public_ip}) ==="
      until ssh -i $SSH_KEY \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=5 \
        ubuntu@${aws_instance.db.public_ip} true 2>/dev/null; do
        echo "  DB not ready yet, retrying in 10s..."
        sleep 10
      done
      echo "  DB SSH ready"

      echo "=== [Ansible] Waiting for ${var.web_min_size} ASG instances to be InService ==="
      until [ "$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names ${aws_autoscaling_group.web.name} \
        --region ${var.aws_region} \
        --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`] | length(@)' \
        --output text 2>/dev/null)" -ge "${var.web_min_size}" ]; do
        echo "  Waiting for ASG instances..."
        sleep 30
      done
      echo "  ASG instances InService"

      echo "=== [Ansible] Running playbook ==="
      cd ${path.module}/../ansible
      ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini playbook.yml

      echo "=== [Ansible] Done. Site available at: https://${aws_cloudfront_distribution.wordpress.domain_name} ==="
    EOT
  }
}
