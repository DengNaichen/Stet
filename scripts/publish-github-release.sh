#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env.release"
DIST_ROOT="$ROOT_DIR/dist/github-release"

if [[ -f "$ENV_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    [[ "$line" != *"="* ]] && continue

    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    export "$key=$value"
  done < "$ENV_FILE"
fi

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required.}"
: "${GITHUB_TAG:?GITHUB_TAG is required.}"

RELEASE_DIR="${RELEASE_DIR:-$DIST_ROOT/$GITHUB_TAG}"
ZIP_PATH="${ZIP_PATH:-}"
APPCAST_PATH="${APPCAST_PATH:-$RELEASE_DIR/sparkle/appcast.xml}"
RELEASE_TITLE="${RELEASE_TITLE:-$GITHUB_TAG}"
RELEASE_NOTES_PATH="${RELEASE_NOTES_PATH:-${RELEASE_NOTES_PATH:-}}"
GITHUB_RELEASE_NOTES_MODE="${GITHUB_RELEASE_NOTES_MODE:-generate}"
GITHUB_RELEASE_LATEST="${GITHUB_RELEASE_LATEST:-true}"
GITHUB_RELEASE_PRERELEASE="${GITHUB_RELEASE_PRERELEASE:-false}"
GITHUB_RELEASE_DRAFT="${GITHUB_RELEASE_DRAFT:-false}"
GITHUB_RELEASE_VERIFY_TAG="${GITHUB_RELEASE_VERIFY_TAG:-true}"
GITHUB_RELEASE_TARGET="${GITHUB_RELEASE_TARGET:-$(git rev-parse HEAD)}"

if [[ -z "$ZIP_PATH" ]]; then
  zip_matches=("$RELEASE_DIR"/*.zip(N))
  final_zip_matches=("${(@)zip_matches:#*-pre-notary.zip}")
  if (( ${#final_zip_matches[@]} > 0 )); then
    zip_matches=("${final_zip_matches[@]}")
  fi

  if (( ${#zip_matches[@]} == 0 )); then
    echo "No zip asset found in $RELEASE_DIR"
    exit 1
  fi
  ZIP_PATH="${zip_matches[1]}"
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Zip asset not found: $ZIP_PATH"
  exit 1
fi

assets=("$ZIP_PATH")
if [[ -f "$APPCAST_PATH" ]]; then
  assets+=("$APPCAST_PATH")
fi

release_exists=false
if gh release view "$GITHUB_TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  release_exists=true
fi

create_args=(
  "$GITHUB_TAG"
  --repo "$GITHUB_REPOSITORY"
  --title "$RELEASE_TITLE"
)

if [[ "$GITHUB_RELEASE_VERIFY_TAG" == "true" ]]; then
  create_args+=(--verify-tag)
else
  create_args+=(--target "$GITHUB_RELEASE_TARGET")
fi

if [[ "$GITHUB_RELEASE_LATEST" == "true" ]]; then
  create_args+=(--latest)
else
  create_args+=(--latest=false)
fi

if [[ "$GITHUB_RELEASE_PRERELEASE" == "true" ]]; then
  create_args+=(--prerelease)
fi

if [[ "$GITHUB_RELEASE_DRAFT" == "true" ]]; then
  create_args+=(--draft)
fi

case "$GITHUB_RELEASE_NOTES_MODE" in
  generate)
    create_args+=(--generate-notes)
    if [[ -n "$RELEASE_NOTES_PATH" && -f "$RELEASE_NOTES_PATH" ]]; then
      create_args+=(--notes-file "$RELEASE_NOTES_PATH")
    fi
    ;;
  file)
    if [[ -z "$RELEASE_NOTES_PATH" || ! -f "$RELEASE_NOTES_PATH" ]]; then
      echo "GITHUB_RELEASE_NOTES_MODE=file requires RELEASE_NOTES_PATH"
      exit 1
    fi
    create_args+=(--notes-file "$RELEASE_NOTES_PATH")
    ;;
  tag)
    create_args+=(--notes-from-tag)
    ;;
  none)
    ;;
  *)
    echo "Unsupported GITHUB_RELEASE_NOTES_MODE: $GITHUB_RELEASE_NOTES_MODE"
    exit 1
    ;;
esac

if [[ "$release_exists" == false ]]; then
  echo "Creating GitHub release $GITHUB_TAG..."
  gh release create "${create_args[@]}"
else
  echo "GitHub release $GITHUB_TAG already exists. Uploading assets with --clobber."
fi

echo "Uploading assets..."
gh release upload "$GITHUB_TAG" "${assets[@]}" --clobber --repo "$GITHUB_REPOSITORY"

echo
echo "Published GitHub release assets:"
for asset in "${assets[@]}"; do
  echo "  $asset"
done
echo "Release URL:"
echo "  https://github.com/$GITHUB_REPOSITORY/releases/tag/$GITHUB_TAG"
