#!/usr/bin/env bash
# Tear down the whole workshop, in the reverse order of main_deploy.sh. Stops at the first failure.
#
#   ./main_destroy.sh                  asks you to type "destroy" first
#   ./main_destroy.sh --yes            no prompt
#   ./main_destroy.sh --keep-images    keep the ECR repositories and images, so the next deploy is faster
#
#   1. Claude Desktop: remove the aiops-eks entry (it holds the MCP token) from claude_desktop_config.json
#   2. mcp-server-terraform: terraform destroy (EKS, ECS, ALB, VPC, SSM token, nginx workload with the cluster)
#   3. mcp-server-deployments: terraform destroy (ECR repositories mcp-server and nginx, images included)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Windows (Git Bash) keeps the Claude Desktop config under %APPDATA%; everything else uses the macOS path.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) PLATFORM=windows; DEFAULT_CLAUDE_CONFIG="$APPDATA/Claude/claude_desktop_config.json" ;;
  *)                    PLATFORM=macos;   DEFAULT_CLAUDE_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
esac
CLAUDE_CONFIG_PATH="${CLAUDE_CONFIG_PATH:-$DEFAULT_CLAUDE_CONFIG}"

claude_running() {
  if [[ "$PLATFORM" == windows ]]; then
    tasklist //FI "IMAGENAME eq Claude.exe" 2>/dev/null | grep -i 'claude\.exe' >/dev/null
  else
    ps -axo comm= | grep '/Claude\.app/Contents/MacOS/Claude$' >/dev/null
  fi
}

ASSUME_YES=false
KEEP_IMAGES=false
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=true ;;
    --keep-images) KEEP_IMAGES=true ;;
    *) sed -n '2,11p' "$0"; exit 1 ;;
  esac
done

banner() { printf '\n######## %s ########\n' "$*"; }

for cmd in terraform aws python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd is required" >&2; exit 1; }
done

echo "This permanently deletes the AI Ops workshop from AWS account $(aws sts get-caller-identity --query Account --output text):"
echo "  - EKS cluster, ECS service, load balancer, VPC and the MCP token (mcp-server-terraform)"
if $KEEP_IMAGES; then
  echo "  - ECR repositories are KEPT (--keep-images)"
else
  echo "  - ECR repositories mcp-server and nginx, with all their images (mcp-server-deployments)"
fi
echo "  - the aiops-eks entry in your Claude Desktop config"
if ! $ASSUME_YES; then
  read -r -p 'Type "destroy" to continue: ' answer
  [[ "$answer" == "destroy" ]] || { echo "Cancelled."; exit 1; }
fi

banner "1/3 Claude Desktop configuration"
if claude_running; then
  # Claude Desktop rewrites its config from memory while running, so an edit now would be lost.
  echo "Claude Desktop is running, so the aiops-eks entry is left in place. Quit it and remove the entry"
  echo "under Settings > Developer, or re-run this script later (the AWS steps are safe to repeat)."
elif [[ -f "$CLAUDE_CONFIG_PATH" ]]; then
  python3 - "$CLAUDE_CONFIG_PATH" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
config = json.loads(path.read_text())
servers = config.get("mcpServers") or {}
if "aiops-eks" in servers:
    del servers["aiops-eks"]
    path.write_text(json.dumps(config, indent=2) + "\n")
    print(f"Removed aiops-eks from {path}")
else:
    print("No aiops-eks entry, nothing to remove")
backup = path.with_suffix(".json.bak")
if backup.exists() and "aiops-eks" in (json.loads(backup.read_text()).get("mcpServers") or {}):
    backup.unlink()
    print(f"Deleted {backup.name}, which also held the MCP token")
PY
else
  echo "No Claude Desktop config found, nothing to remove"
fi

banner "2/3 Infrastructure (mcp-server-terraform)"
terraform -chdir="$ROOT_DIR/mcp-server-terraform" init -input=false >/dev/null
terraform -chdir="$ROOT_DIR/mcp-server-terraform" destroy -auto-approve

banner "3/3 ECR repositories (mcp-server-deployments)"
if $KEEP_IMAGES; then
  echo "Skipped (--keep-images)."
else
  terraform -chdir="$ROOT_DIR/mcp-server-deployments/terraform" init -input=false >/dev/null
  terraform -chdir="$ROOT_DIR/mcp-server-deployments/terraform" destroy -auto-approve
fi

banner "All done"
echo "Left in place: the Terraform state bucket, and the aiops-workshop context in your ~/.kube/config."
