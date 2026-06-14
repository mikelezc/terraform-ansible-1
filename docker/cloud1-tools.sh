#!/bin/bash
# Builds (if needed) the tools container and opens an interactive shell inside it.
# Run from the repo root:  ./docker/cloud1-tools.sh
#
# The container mounts the entire project as /workspace and ships:
#   terraform · ansible · ansible-playbook · aws (CLI) · git · jq
#
# Requirements:
#   - Docker running locally
#   - AWS credentials configured at ~/.aws/  (run: aws configure)
#   - SSH key at ~/.ssh/cloud-1-key.pem
#     (or override: AWS_KEY_PATH=/path/to/key.pem ./docker/cloud1-tools.sh)

set -e

IMAGE_NAME="cloud1-tools"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# SSH key path — override the default with the AWS_KEY_PATH env variable
AWS_KEY_PATH="${AWS_KEY_PATH:-$HOME/.ssh/cloud-1-key.pem}"

if [ ! -f "$AWS_KEY_PATH" ]; then
  echo "ERROR: SSH key not found at '$AWS_KEY_PATH'."
  echo "  Copy it there or set: AWS_KEY_PATH=/path/to/cloud-1-key.pem"
  exit 1
fi

if ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
  echo ">>> Building $IMAGE_NAME image (first time only, ~3 min)..."
  docker build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile.tools" "$SCRIPT_DIR"
fi

# ─── Usage guide ──────────────────────────────────────────────────────────────
cat <<'HELP'

┌──────────────────────────────────────────────────────────────────────────┐
│  cloud1-tools — development container                                    │
│  Project mounted at: /workspace                                          │
│  Tools available:  terraform · ansible · aws · git · jq                  │
├──────────────────────────────────────────────────────────────────────────┤
│  FULL DEPLOY (infra + config in one command)                             │
│    cd /workspace/terraform                                               │
│    terraform init                                                        │
│    terraform apply                        # deploys everything (~20 min) │
│                                                                          │
│  RE-RUN ANSIBLE (after scaling or manual config refresh)                 │
│    cd /workspace/ansible                                                 │
│    ansible-playbook -i inventory.ini playbook.yml          # LB + DB     │
│    ansible-playbook -i inventory.ini playbook.yml -l lb    # LB only     │
│                                                                          │
│  SCALE WEB INSTANCES                                                     │
│    cd /workspace/terraform                                               │
│    terraform apply -var="web_desired=4"   # scale up to 4 instances     │
│    terraform apply -var="web_desired=2"   # scale back down to 2        │
│                                                                          │
│  CHECK OUTPUTS (site URL, IPs, etc.)                                     │
│    cd /workspace/terraform                                               │
│    terraform output                                                      │
│                                                                          │
│  DESTROY EVERYTHING                                                      │
│    cd /workspace/terraform                                               │
│    terraform destroy                      # removes all AWS resources    │
│                                                                          │
│  EXIT CONTAINER                                                          │
│    exit                                                                  │
└──────────────────────────────────────────────────────────────────────────┘

HELP

echo ">>> Entering container (project mounted at /workspace)..."
echo ""

docker run --rm -it \
  -v "$PROJECT_ROOT:/workspace" \
  -v "$HOME/.aws:/root/.aws:ro" \
  -v "$AWS_KEY_PATH:/root/.ssh/cloud-1-key.pem:ro" \
  -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-west-3}" \
  "$IMAGE_NAME" \
  bash
