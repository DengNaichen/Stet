#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$ROOT_DIR/.git/hooks"
HOOK_PATH="$HOOKS_DIR/pre-push"

mkdir -p "$HOOKS_DIR"

cat > "$HOOK_PATH" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"

if [[ -z "${PUBLIC_REPO_DIR:-}" ]]; then
  echo "Skipping open-source sync: PUBLIC_REPO_DIR is not set."
  exit 0
fi

"$ROOT_DIR/scripts/sync-open-source-export.sh"
EOF

chmod +x "$HOOK_PATH"

echo "Installed pre-push hook at $HOOK_PATH"
echo "Set PUBLIC_REPO_DIR to your public repo checkout before pushing."
