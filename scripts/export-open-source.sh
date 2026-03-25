#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="${1:-}"

if [[ -z "$TARGET_DIR" ]]; then
  echo "usage: ./scripts/export-open-source.sh /path/to/export-dir" >&2
  exit 1
fi

TARGET_DIR="$(cd "$(dirname "$TARGET_DIR")" && pwd)/$(basename "$TARGET_DIR")"

if [[ -e "$TARGET_DIR" ]]; then
  echo "target directory already exists: $TARGET_DIR" >&2
  exit 1
fi

require_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_bin rsync
require_bin python3

echo "Exporting sanitized public tree to $TARGET_DIR"

rsync -a \
  --exclude ".git" \
  --exclude ".DS_Store" \
  --exclude ".derivedData" \
  --exclude ".env" \
  --exclude ".env.release" \
  --exclude "node_modules" \
  --exclude ".build" \
  --exclude "build" \
  --exclude "dist" \
  --exclude "DerivedData" \
  --exclude ".swiftpm" \
  --exclude "default.profraw" \
  --exclude "apps/backend/supabase/.branches" \
  --exclude "apps/backend/supabase/.temp" \
  --exclude "apps/mac/build_log.txt" \
  "$ROOT_DIR/" \
  "$TARGET_DIR/"

PRIVATE_PATHS=(
  "apps/backend/supabase/functions/relay/managed_billing_backend.ts"
  "apps/backend/supabase/functions/relay/billing.ts"
  "apps/backend/supabase/functions/relay/usage.ts"
  "apps/backend/supabase/migrations/20260318120000_payg_wallet_v1.sql"
  "apps/backend/supabase/migrations/20260318123000_precision_model_billing_v1.sql"
  "apps/backend/supabase/migrations/20260318221500_fix_apply_credit_topup_ambiguity.sql"
  "apps/backend/supabase/migrations/20260318223500_fix_managed_usage_rpc_overloads.sql"
  "apps/backend/supabase/migrations/20260318224500_fix_begin_managed_usage_event_id.sql"
  "apps/backend/supabase/migrations/20260320234541_fix_billing_model_flaws.sql"
  "apps/backend/supabase/migrations/20260324213000_beta_invite_and_relay_limits.sql"
)

for relative_path in "${PRIVATE_PATHS[@]}"; do
  rm -f "$TARGET_DIR/$relative_path"
done

cp "$ROOT_DIR/docs/open-source/backend.README.public.md" \
  "$TARGET_DIR/apps/backend/README.md"
cp "$ROOT_DIR/docs/open-source/root.README.public.md" \
  "$TARGET_DIR/OPEN_SOURCE.md"

python3 - "$TARGET_DIR" <<'PY'
from pathlib import Path
import sys

target = Path(sys.argv[1])

factory_path = target / "apps/backend/supabase/functions/relay/billing_factory.ts"
factory_path.write_text(
    """import type { RelayBillingBackend } from "./billing_backend.ts";
import { UnmeteredRelayBillingBackend } from "./unmetered_billing_backend.ts";

export function makeRelayBillingBackend(): RelayBillingBackend {
  return new UnmeteredRelayBillingBackend();
}
""",
    encoding="utf-8",
)

readme_path = target / "README.md"
text = readme_path.read_text(encoding="utf-8")
marker = "## Open Source Export\n"
if marker not in text:
    text += (
        "\n## Open Source Export\n\n"
        "This public repository is generated from a private source repository. "
        "Managed billing, trial operations, abuse controls, and monetization "
        "internals are intentionally omitted.\n"
    )
    readme_path.write_text(text, encoding="utf-8")
PY

echo "Sanitized export complete."
echo
echo "Next steps:"
echo "  1. cd \"$TARGET_DIR\""
echo "  2. git init"
echo "  3. git add ."
echo "  4. git commit -m 'Initial public export'"
