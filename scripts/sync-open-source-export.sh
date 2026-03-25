#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PUBLIC_REPO_DIR="${PUBLIC_REPO_DIR:-}"
PUBLIC_REPO_BRANCH="${PUBLIC_REPO_BRANCH:-main}"
PUBLIC_REPO_REMOTE="${PUBLIC_REPO_REMOTE:-origin}"
OPEN_SOURCE_SYNC_PUSH="${OPEN_SOURCE_SYNC_PUSH:-true}"
OPEN_SOURCE_SYNC_BASE_REF="${OPEN_SOURCE_SYNC_BASE_REF:-}"
OPEN_SOURCE_COMMIT_MESSAGE="${OPEN_SOURCE_COMMIT_MESSAGE:-}"

WATCH_PATHS=(
  "apps/backend"
  "docs/open-source"
  "scripts/export-open-source.sh"
  "scripts/sync-open-source-export.sh"
)

require_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_bin git
require_bin rsync
require_bin mktemp

if [[ -z "$PUBLIC_REPO_DIR" ]]; then
  echo "PUBLIC_REPO_DIR is required" >&2
  exit 1
fi

if [[ ! -d "$PUBLIC_REPO_DIR/.git" ]]; then
  echo "PUBLIC_REPO_DIR must point to a git checkout: $PUBLIC_REPO_DIR" >&2
  exit 1
fi

resolve_base_ref() {
  if [[ -n "$OPEN_SOURCE_SYNC_BASE_REF" ]]; then
    printf '%s' "$OPEN_SOURCE_SYNC_BASE_REF"
    return
  fi

  if git -C "$ROOT_DIR" rev-parse --verify '@{upstream}' >/dev/null 2>&1; then
    git -C "$ROOT_DIR" rev-parse --abbrev-ref '@{upstream}'
    return
  fi

  if git -C "$ROOT_DIR" rev-parse --verify 'HEAD^' >/dev/null 2>&1; then
    printf '%s' 'HEAD^'
    return
  fi

  printf '%s' ''
}

has_watched_changes() {
  local base_ref="$1"
  local diff_args=()

  if [[ -n "$base_ref" ]]; then
    diff_args=("$base_ref..HEAD")
  else
    diff_args=("HEAD")
  fi

  local changed
  changed="$(git -C "$ROOT_DIR" diff --name-only "${diff_args[@]}" -- "${WATCH_PATHS[@]}")"
  [[ -n "$changed" ]]
}

base_ref="$(resolve_base_ref)"

if ! has_watched_changes "$base_ref"; then
  echo "No watched open-source export changes detected."
  exit 0
fi

tmp_export_dir="$(mktemp -d /tmp/stet-open-sync-XXXXXX)"
cleanup() {
  rm -rf "$tmp_export_dir"
}
trap cleanup EXIT

"$ROOT_DIR/scripts/export-open-source.sh" "$tmp_export_dir" >/dev/null

rsync -a --delete \
  --exclude ".git" \
  "$tmp_export_dir/" \
  "$PUBLIC_REPO_DIR/"

if [[ -z "$(git -C "$PUBLIC_REPO_DIR" status --short)" ]]; then
  echo "Public export repository is already up to date."
  exit 0
fi

git -C "$PUBLIC_REPO_DIR" add -A

if [[ -z "$OPEN_SOURCE_COMMIT_MESSAGE" ]]; then
  source_sha="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
  OPEN_SOURCE_COMMIT_MESSAGE="Sync public export from ${source_sha}"
fi

git -C "$PUBLIC_REPO_DIR" commit -m "$OPEN_SOURCE_COMMIT_MESSAGE"

if [[ "$OPEN_SOURCE_SYNC_PUSH" == "true" ]]; then
  git -C "$PUBLIC_REPO_DIR" push "$PUBLIC_REPO_REMOTE" "HEAD:${PUBLIC_REPO_BRANCH}"
fi

echo "Public export sync complete."
