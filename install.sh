#!/usr/bin/env bash
# Set up the AI Ops MCP workshop: creates a FLO26 directory next to this repo, clones the three
# workshop repositories into it, and copies main_deploy.sh, main_destroy.sh and nginx_url.sh there.
#
#   ./install.sh                       creates ../FLO26 (next to this repo)
#   FLO26_DIR=~/work/FLO26 ./install.sh
#   GIT_BASE=git@github.com:mrkhurana ./install.sh    clone over SSH instead of HTTPS
#
# Safe to re-run: repositories that are already cloned are pulled instead.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLO26_DIR="${FLO26_DIR:-$(dirname "$SCRIPT_DIR")/FLO26}"
GIT_BASE="${GIT_BASE:-https://github.com/mrkhurana}"

# <folder name used by the scripts> <repository name on GitHub>
REPOS=(
  "mcp-server-deployments mcp-server-deployments"
  "mcp-server-terraform mcp-server-terraform"
  "mcp-client mcp-client"
)

step() { printf '\n==> %s\n' "$*"; }
ok()   { printf '    OK  %s\n' "$*"; }
warn() { printf '    WARN %s\n' "$*" >&2; }
fail() { printf '    FAIL %s\n' "$*" >&2; exit 1; }

step "Checking tools"
command -v git >/dev/null 2>&1 || fail "git is required"
missing=()
for cmd in aws terraform kubectl docker node npx python3 curl; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (( ${#missing[@]} )); then
  warn "not installed yet: ${missing[*]} (needed before ./main_deploy.sh, see README.md)"
else
  ok "git, aws, terraform, kubectl, docker, node, npx, python3, curl"
fi

step "Creating $FLO26_DIR"
mkdir -p "$FLO26_DIR"
ok "$FLO26_DIR"

step "Cloning the workshop repositories from $GIT_BASE"
for entry in "${REPOS[@]}"; do
  read -r folder repo <<<"$entry"
  target="$FLO26_DIR/$folder"
  if [[ -d "$target/.git" ]]; then
    git -C "$target" pull --ff-only --quiet && ok "$folder (already cloned, updated)" \
      || warn "$folder: could not update; leaving your local copy as it is"
  elif [[ -e "$target" ]]; then
    fail "$target exists but is not a git repository; move it away and re-run"
  else
    git clone --quiet "$GIT_BASE/$repo.git" "$target" \
      || fail "could not clone $GIT_BASE/$repo.git. Check that you have access to the repository."
    ok "$folder"
  fi
done

step "Copying main_deploy.sh, main_destroy.sh and nginx_url.sh"
for script in main_deploy.sh main_destroy.sh nginx_url.sh; do
  cp "$SCRIPT_DIR/$script" "$FLO26_DIR/$script"
  chmod +x "$FLO26_DIR/$script"
  ok "$FLO26_DIR/$script"
done

cat <<EOF

==> Done. Your workshop directory is:
    $FLO26_DIR

Next steps (details in README.md):
    1. Export your AWS credentials and check them:   aws sts get-caller-identity
    2. Configure mcp-server-terraform/terraform.tfvars and the Terraform state bucket
    3. Quit Claude Desktop, then:                     cd "$FLO26_DIR" && ./main_deploy.sh v0.2.0
    4. When you're finished:                         cd "$FLO26_DIR" && ./main_destroy.sh
EOF
