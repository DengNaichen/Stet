#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Stet.xcodeproj"
SCHEME="Stet"
APP_NAME="Stet"
DIST_DIR="$ROOT_DIR/dist/github-release"
ENV_FILE="$ROOT_DIR/.env.release"

load_env_file() {
  local env_file="$1"

  [[ -f "$env_file" ]] || return

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    [[ "$line" != *"="* ]] && continue

    local key="${line%%=*}"
    local value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    # Explicit environment variables passed to the script should win.
    if [[ ${+parameters[$key]} -eq 1 ]]; then
      continue
    fi

    export "$key=$value"
  done < "$env_file"
}

load_env_file "$ENV_FILE"

: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required.}"
: "${NOTARY_PROFILE:?NOTARY_PROFILE is required.}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required, for example owner/repo.}"
: "${GITHUB_TAG:?GITHUB_TAG is required, for example v1.0.0.}"

DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-Developer ID Application}"
ARCHIVE_CODE_SIGN_STYLE="${ARCHIVE_CODE_SIGN_STYLE:-Automatic}"
ARCHIVE_CODE_SIGN_IDENTITY="${ARCHIVE_CODE_SIGN_IDENTITY:-$DEVELOPER_ID_APPLICATION}"
ARCHIVE_PROVISIONING_PROFILE_SPECIFIER="${ARCHIVE_PROVISIONING_PROFILE_SPECIFIER:-}"
GENERATE_SPARKLE_APPCAST="${GENERATE_SPARKLE_APPCAST:-1}"
SPARKLE_KEYCHAIN_ACCOUNT="${SPARKLE_KEYCHAIN_ACCOUNT:-ed25519}"
SPARKLE_FEED_BASE_URL="${SPARKLE_FEED_BASE_URL:-https://github.com/${GITHUB_REPOSITORY}/releases/download/${GITHUB_TAG}}"
RELEASES_PAGE_URL="https://github.com/${GITHUB_REPOSITORY}/releases/tag/${GITHUB_TAG}"

if [[ "$GENERATE_SPARKLE_APPCAST" == "1" ]]; then
  : "${SPARKLE_APPCAST_URL:?SPARKLE_APPCAST_URL is required when GENERATE_SPARKLE_APPCAST=1.}"
  : "${SPARKLE_PUBLIC_ED_KEY:?SPARKLE_PUBLIC_ED_KEY is required when GENERATE_SPARKLE_APPCAST=1.}"
fi

WORK_DIR="$DIST_DIR/$GITHUB_TAG"
ARCHIVE_PATH="$WORK_DIR/${APP_NAME}.xcarchive"
APP_PATH="$WORK_DIR/${APP_NAME}.app"
DMG_OUTPUT_DIR="$WORK_DIR/dmg"
NOTARY_SUBMISSION_PLIST="$WORK_DIR/notary-submission.plist"
NOTARY_LOG_JSON="$WORK_DIR/notary-log.json"
SPARKLE_DIR="$WORK_DIR/sparkle"
APP_ENTITLEMENTS="$WORK_DIR/${APP_NAME}.entitlements.plist"
NPX_BIN="${NPX_BIN:-$(command -v npx || true)}"
NPM_CACHE_DIR="${NPM_CACHE_DIR:-$WORK_DIR/.npm-cache}"

find_sparkle_generate_appcast() {
  local candidates=()

  if [[ -n "${SPARKLE_GENERATE_APPCAST:-}" ]]; then
    candidates+=("$SPARKLE_GENERATE_APPCAST")
  fi

  candidates+=(
    "$ROOT_DIR/.build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
    "$ROOT_DIR/build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
    "$ROOT_DIR/.derivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
  )

  candidates+=("$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast(N))

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

SPARKLE_GENERATE_APPCAST="$(find_sparkle_generate_appcast || true)"

mkdir -p "$WORK_DIR"
rm -rf "$ARCHIVE_PATH" "$APP_PATH" "$DMG_OUTPUT_DIR" "$SPARKLE_DIR" "$APP_ENTITLEMENTS" "$NPM_CACHE_DIR"

if [[ -z "$NPX_BIN" ]]; then
  echo "Missing npx in PATH. Install Node.js or set NPX_BIN to a working npx binary."
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "$DEVELOPER_ID_APPLICATION"; then
  echo "Missing signing identity: $DEVELOPER_ID_APPLICATION"
  echo "Install the Developer ID Application certificate in Xcode first."
  exit 1
fi

echo "Archiving $APP_NAME with $ARCHIVE_CODE_SIGN_STYLE signing..."
XCODEBUILD_COMMAND=(
  xcodebuild
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  CODE_SIGN_STYLE="$ARCHIVE_CODE_SIGN_STYLE" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID"
)

if [[ "$ARCHIVE_CODE_SIGN_STYLE" == "Manual" ]]; then
  XCODEBUILD_COMMAND+=(
    CODE_SIGN_IDENTITY="$ARCHIVE_CODE_SIGN_IDENTITY"
    OTHER_CODE_SIGN_FLAGS="--timestamp"
  )
fi

if [[ -n "$ARCHIVE_PROVISIONING_PROFILE_SPECIFIER" ]]; then
  XCODEBUILD_COMMAND+=(
    PROVISIONING_PROFILE_SPECIFIER="$ARCHIVE_PROVISIONING_PROFILE_SPECIFIER"
  )
fi

if [[ "$GENERATE_SPARKLE_APPCAST" == "1" ]]; then
  XCODEBUILD_COMMAND+=(
    SPARKLE_FEED_URL="$SPARKLE_APPCAST_URL"
    SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY"
  )
fi

"${XCODEBUILD_COMMAND[@]}"

ditto "$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app" "$APP_PATH"

codesign -d --entitlements :- "$APP_PATH" > "$APP_ENTITLEMENTS" 2>/dev/null

resign_component() {
  local target_path="$1"

  if [[ ! -e "$target_path" ]]; then
    return
  fi

  codesign \
    --force \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --timestamp \
    --options runtime \
    --preserve-metadata=identifier,entitlements,flags \
    "$target_path"
}

SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_ROOT="$SPARKLE_FRAMEWORK/Versions/Current"
resign_component "$SPARKLE_ROOT/Autoupdate"
resign_component "$SPARKLE_ROOT/XPCServices/Downloader.xpc"
resign_component "$SPARKLE_ROOT/XPCServices/Installer.xpc"
resign_component "$SPARKLE_ROOT/Updater.app"
resign_component "$SPARKLE_FRAMEWORK"
resign_component "$APP_PATH/Contents/Frameworks/StetVisuals.framework"

codesign \
  --force \
  --sign "$DEVELOPER_ID_APPLICATION" \
  --timestamp \
  --options runtime \
  --entitlements "$APP_ENTITLEMENTS" \
  "$APP_PATH"

VERSION="$(
  /usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE_PATH/Info.plist"
)"
BUILD="$(
  /usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE_PATH/Info.plist"
)"
RELEASE_BASENAME="${APP_NAME}-${VERSION}-${BUILD}-mac"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Creating release DMG..."
rm -rf "$DMG_OUTPUT_DIR"
mkdir -p "$DMG_OUTPUT_DIR"
NPM_CONFIG_CACHE="$NPM_CACHE_DIR" "$NPX_BIN" --yes create-dmg \
  --overwrite \
  --identity "$DEVELOPER_ID_APPLICATION" \
  --dmg-title "$APP_NAME" \
  "$APP_PATH" \
  "$DMG_OUTPUT_DIR"

dmg_matches=("$DMG_OUTPUT_DIR"/*.dmg(N))
if (( ${#dmg_matches[@]} != 1 )); then
  echo "Expected exactly one DMG in $DMG_OUTPUT_DIR, found ${#dmg_matches[@]}"
  exit 1
fi

FINAL_DMG="${dmg_matches[1]}"
RELEASE_DMG_NAME="${RELEASE_DMG_NAME:-${APP_NAME}-${GITHUB_TAG}.dmg}"

if [[ "$(basename "$FINAL_DMG")" != "$RELEASE_DMG_NAME" ]]; then
  mv "$FINAL_DMG" "$DMG_OUTPUT_DIR/$RELEASE_DMG_NAME"
  FINAL_DMG="$DMG_OUTPUT_DIR/$RELEASE_DMG_NAME"
fi

echo "Submitting DMG for notarization..."
xcrun notarytool submit \
  "$FINAL_DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format plist \
  > "$NOTARY_SUBMISSION_PLIST"

NOTARY_ID="$(
  /usr/libexec/PlistBuddy -c 'Print :id' "$NOTARY_SUBMISSION_PLIST"
)"
NOTARY_STATUS="$(
  /usr/libexec/PlistBuddy -c 'Print :status' "$NOTARY_SUBMISSION_PLIST"
)"

if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
  echo "Notarization failed with status: $NOTARY_STATUS"
  xcrun notarytool log "$NOTARY_ID" "$NOTARY_LOG_JSON" --keychain-profile "$NOTARY_PROFILE"
  echo "Saved notarization log to $NOTARY_LOG_JSON"
  exit 1
fi

echo "Stapling notarization ticket..."
xcrun stapler staple -v "$FINAL_DMG"
xcrun stapler validate -v "$FINAL_DMG"
if ! spctl -a -vv --type open "$FINAL_DMG"; then
  echo "Warning: spctl assessment failed for $FINAL_DMG, but stapler validation already succeeded."
fi

if [[ "$GENERATE_SPARKLE_APPCAST" == "1" ]]; then
  if [[ ! -x "$SPARKLE_GENERATE_APPCAST" ]]; then
    echo "Missing Sparkle tool. Set SPARKLE_GENERATE_APPCAST or install Sparkle artifacts in a standard location."
    exit 1
  fi

  if [[ -z "${SPARKLE_PRIVATE_KEY_PATH:-}" && -z "${SPARKLE_KEYCHAIN_ACCOUNT:-}" ]]; then
    echo "Sparkle appcast generation requires SPARKLE_PRIVATE_KEY_PATH or SPARKLE_KEYCHAIN_ACCOUNT."
    exit 1
  fi

  mkdir -p "$SPARKLE_DIR"
  cp "$FINAL_DMG" "$SPARKLE_DIR/"

  if [[ -n "${RELEASE_NOTES_PATH:-}" ]]; then
    RELEASE_NOTES_EXTENSION="${RELEASE_NOTES_PATH##*.}"
    cp "$RELEASE_NOTES_PATH" "$SPARKLE_DIR/${RELEASE_BASENAME}.${RELEASE_NOTES_EXTENSION}"
  fi

  APPCAST_COMMAND=(
    "$SPARKLE_GENERATE_APPCAST"
    --download-url-prefix "$SPARKLE_FEED_BASE_URL"
    --link "$RELEASES_PAGE_URL"
    --full-release-notes-url "$RELEASES_PAGE_URL"
    --embed-release-notes
  )

  if [[ -n "${SPARKLE_PRIVATE_KEY_PATH:-}" ]]; then
    APPCAST_COMMAND+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_PATH")
  else
    APPCAST_COMMAND+=(--account "$SPARKLE_KEYCHAIN_ACCOUNT")
  fi

  APPCAST_COMMAND+=("$SPARKLE_DIR")

  echo "Generating Sparkle appcast..."
  "${APPCAST_COMMAND[@]}"
fi

echo
echo "Release artifacts:"
echo "  Archive:    $ARCHIVE_PATH"
echo "  App:        $APP_PATH"
echo "  DMG:        $FINAL_DMG"
if [[ "$GENERATE_SPARKLE_APPCAST" == "1" ]]; then
  echo "  Appcast:    $SPARKLE_DIR/appcast.xml"
fi
echo "  Notary ID:  $NOTARY_ID"
