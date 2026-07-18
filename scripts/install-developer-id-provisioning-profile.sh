#!/bin/zsh
set -euo pipefail

: "${DEVELOPER_ID_PROVISIONING_PROFILE_BASE64:?DEVELOPER_ID_PROVISIONING_PROFILE_BASE64 is required.}"
: "${DEVELOPER_ID_PROVISIONING_PROFILE_UUID:?DEVELOPER_ID_PROVISIONING_PROFILE_UUID is required.}"
: "${ARCHIVE_PROVISIONING_PROFILE_SPECIFIER:?ARCHIVE_PROVISIONING_PROFILE_SPECIFIER is required.}"

PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
PROFILE_PATH="$PROFILE_DIR/$DEVELOPER_ID_PROVISIONING_PROFILE_UUID.provisionprofile"

umask 077
mkdir -p "$PROFILE_DIR"
printf '%s' "$DEVELOPER_ID_PROVISIONING_PROFILE_BASE64" | /usr/bin/base64 -D > "$PROFILE_PATH"

if [[ ! -s "$PROFILE_PATH" ]]; then
  echo "The Developer ID provisioning profile secret decoded to an empty file." >&2
  exit 1
fi

echo "Installed Developer ID provisioning profile."
