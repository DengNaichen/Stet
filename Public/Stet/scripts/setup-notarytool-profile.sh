#!/bin/zsh
set -euo pipefail

PROFILE_NAME="${1:-${NOTARY_PROFILE:-stet-notary}}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APP_SPECIFIC_PASSWORD="${APP_SPECIFIC_PASSWORD:-}"

if [[ -z "$APPLE_ID" ]]; then
  echo "APPLE_ID is required."
  exit 1
fi

if [[ -z "$APPLE_TEAM_ID" ]]; then
  echo "APPLE_TEAM_ID is required."
  exit 1
fi

COMMAND=(
  xcrun notarytool store-credentials
  "$PROFILE_NAME"
  --apple-id "$APPLE_ID"
  --team-id "$APPLE_TEAM_ID"
  --validate
)

if [[ -n "$APP_SPECIFIC_PASSWORD" ]]; then
  COMMAND+=(--password "$APP_SPECIFIC_PASSWORD")
fi

echo "Storing notarytool credentials in Keychain profile '$PROFILE_NAME'..."
"${COMMAND[@]}"

echo
echo "Saved Keychain profile: $PROFILE_NAME"
