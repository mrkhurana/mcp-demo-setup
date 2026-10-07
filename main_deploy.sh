#!/usr/bin/env bash
# Full workshop deploy: runs the three deploy scripts in order and stops at the first failure.
#
#   ./main_deploy.sh <version>      e.g. ./main_deploy.sh v0.2.0 (default: latest)
#
#   1. mcp-server-deployments/deploy.sh <version>   build + push the MCP image, mirror nginx into ECR
#   2. mcp-server-terraform/deploy.sh               VPC, EKS, ECS, ALB, auth token + nginx workload
#      then force a new ECS deployment so the task runs the image just pushed to :latest
#   3. mcp-client/deploy.sh                         verify the MCP server and configure Claude Desktop
set -euo pipefail

VERSION="${1:-latest}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-$(awk -F'=' '/^aws_region/ {gsub(/[" ]/, "", $2); print $2}' "$ROOT_DIR/mcp-server-terraform/terraform.tfvars")}"

banner() { printf '\n######## %s ########\n' "$*"; }

# Step 3 refuses to run while Claude Desktop is open, so check now instead of after a long deploy.
if ps -axo comm= | grep '/Claude\.app/Contents/MacOS/Claude$' >/dev/null; then
  echo "Claude Desktop is running. Quit it completely (Cmd+Q), then re-run ./main_deploy.sh." >&2
  exit 1
fi

banner "1/3 MCP server image ($VERSION)"
"$ROOT_DIR/mcp-server-deployments/deploy.sh" "$VERSION"

banner "2/3 Infrastructure and workload"
"$ROOT_DIR/mcp-server-terraform/deploy.sh"

ECS_CLUSTER="$(terraform -chdir="$ROOT_DIR/mcp-server-terraform" output -raw ecs_cluster_name)"
ECS_SERVICE="$(terraform -chdir="$ROOT_DIR/mcp-server-terraform" output -raw ecs_service_name)"
printf '\nRolling ECS service %s onto the new image...\n' "$ECS_SERVICE"
aws ecs update-service --region "$REGION" --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" \
  --force-new-deployment >/dev/null
aws ecs wait services-stable --region "$REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
echo "ECS service is stable."

banner "3/3 Claude Desktop connection"
"$ROOT_DIR/mcp-client/deploy.sh"

banner "All done"
