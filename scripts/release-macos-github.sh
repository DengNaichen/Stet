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

  [[ -f "$env_file" ]] || return 0

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
SPARKLE_FEED_BASE_URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/${GITHUB_TAG}/"
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
DMG_STAGING_DIR="$WORK_DIR/dmg-staging"

find_sparkle_generate_appcast() {
  local candidates=()

  if [[ -n "${SPARKLE_GENERATE_APPCAST:-}" ]]; then
    candidates+=("$SPARKLE_GENERATE_APPCAST")
  fi

  candidates+=(
    "$ROOT_DIR/.build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
    "$ROOT_DIR/.build/SourcePackages/checkouts/Sparkle/bin/generate_appcast"
    "$ROOT_DIR/build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
    "$ROOT_DIR/build/SourcePackages/checkouts/Sparkle/bin/generate_appcast"
    "$ROOT_DIR/.derivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
    "$ROOT_DIR/.derivedData/SourcePackages/checkouts/Sparkle/bin/generate_appcast"
  )

  candidates+=("$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast(N))
  candidates+=("$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages/checkouts/Sparkle/bin/generate_appcast(N))

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

SPARKLE_GENERATE_APPCAST="$(find_sparkle_generate_appcast || true)"

expected_build_number_for_version() {
  local version="$1"
  local major=""
  local minor=""
  local patch=""
  local extra=""

  IFS='.' read -r major minor patch extra <<< "$version"

  if [[ -n "$extra" || -z "$major" || -z "$minor" || -z "$patch" ]]; then
    echo "Unsupported MARKETING_VERSION format: $version" >&2
    echo "Expected semantic version in major.minor.patch format." >&2
    exit 1
  fi

  if [[ ! "$major" =~ '^[0-9]+$' || ! "$minor" =~ '^[0-9]+$' || ! "$patch" =~ '^[0-9]+$' ]]; then
    echo "Unsupported MARKETING_VERSION format: $version" >&2
    echo "Each semantic version component must be numeric." >&2
    exit 1
  fi

  printf '%d\n' $((10#$major * 1000000 + 10#$minor * 1000 + 10#$patch))
}

plist_has_key() {
  local plist_path="$1"
  local key_path="$2"

  /usr/bin/plutil -extract "$key_path" raw -o /dev/null "$plist_path" >/dev/null 2>&1
}

mkdir -p "$WORK_DIR"
rm -rf "$ARCHIVE_PATH" "$APP_PATH" "$DMG_OUTPUT_DIR" "$SPARKLE_DIR" "$APP_ENTITLEMENTS" "$DMG_STAGING_DIR"

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
    STET_RELEASE_PROVISIONING_PROFILE_SPECIFIER="$ARCHIVE_PROVISIONING_PROFILE_SPECIFIER"
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

codesign --display --entitlements "$APP_ENTITLEMENTS" --xml "$APP_PATH"

if [[ ! -s "$APP_ENTITLEMENTS" ]]; then
  echo "The archived app did not produce an XML entitlements file." >&2
  exit 1
fi

plutil -lint "$APP_ENTITLEMENTS" >/dev/null

REQUIRES_DISTRIBUTION_PROFILE=0

if plist_has_key "$APP_ENTITLEMENTS" "com.apple.developer.applesignin" || \
  plist_has_key "$APP_ENTITLEMENTS" "com.apple.developer.ubiquity-kvstore-identifier"; then
  REQUIRES_DISTRIBUTION_PROFILE=1
fi

if [[ "$REQUIRES_DISTRIBUTION_PROFILE" == "1" ]]; then
  if [[ "$ARCHIVE_CODE_SIGN_STYLE" != "Manual" ]]; then
    cat <<'EOF'
Release signing is misconfigured for restricted entitlements.

This app includes an entitlement that requires a Developer ID distribution
provisioning profile. Automatic archive signing can produce a development-signed app
that is invalid after the bundle is re-signed for Developer ID distribution.

Use Manual archive signing with your Developer ID Application identity and a matching
distribution provisioning profile for NaichengDeng.Stet.
EOF
    exit 1
  fi

  if [[ -z "$ARCHIVE_PROVISIONING_PROFILE_SPECIFIER" ]]; then
    cat <<'EOF'
Missing distribution provisioning profile for restricted entitlements.

This app includes an entitlement that requires a matching distribution provisioning
profile when signed for Developer ID release.
Set ARCHIVE_PROVISIONING_PROFILE_SPECIFIER to that profile and try again.
EOF
    exit 1
  fi
fi

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

normalize_versioned_framework() {
  local framework_path="$1"
  local binary_name="$2"
  local version_a="$framework_path/Versions/A"

  [[ -d "$version_a" ]] || return 0

  rm -rf "$framework_path/Versions/Current"
  ln -s A "$framework_path/Versions/Current"

  for item in Headers Modules Resources "$binary_name"; do
    if [[ -e "$version_a/$item" ]]; then
      rm -rf "$framework_path/$item"
      ln -s "Versions/Current/$item" "$framework_path/$item"
    fi
  done

  if [[ -f "$version_a/$binary_name" ]]; then
    chmod +x "$version_a/$binary_name"
  fi
}

SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_ROOT="$SPARKLE_FRAMEWORK/Versions/Current"
resign_component "$SPARKLE_ROOT/Autoupdate"
resign_component "$SPARKLE_ROOT/XPCServices/Downloader.xpc"
resign_component "$SPARKLE_ROOT/XPCServices/Installer.xpc"
resign_component "$SPARKLE_ROOT/Updater.app"
resign_component "$SPARKLE_FRAMEWORK"

normalize_versioned_framework "$APP_PATH/Contents/Frameworks/sherpa_onnx.framework" "sherpa_onnx"

resign_component "$APP_PATH/Contents/Frameworks/StetVisuals.framework"
resign_component "$APP_PATH/Contents/Frameworks/sherpa_onnx.framework"

echo "Re-signing main application bundle..."
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
EXPECTED_TAG_PREFIX="v${VERSION}"
EXPECTED_BUILD="$(expected_build_number_for_version "$VERSION")"

if [[ "$GITHUB_TAG" != "$EXPECTED_TAG_PREFIX" && "$GITHUB_TAG" != ${EXPECTED_TAG_PREFIX}-* ]]; then
  cat <<EOF
Release tag does not match the archived app version.

Expected tag: ${EXPECTED_TAG_PREFIX} or ${EXPECTED_TAG_PREFIX}-<suffix>
Actual tag:   ${GITHUB_TAG}
App version:  ${VERSION}
App build:    ${BUILD}

Update MARKETING_VERSION before running the release workflow.
EOF
  exit 1
fi

if [[ "$BUILD" != "$EXPECTED_BUILD" ]]; then
  cat <<EOF
Release build number does not match the app version.

Expected CURRENT_PROJECT_VERSION: ${EXPECTED_BUILD}
Actual CURRENT_PROJECT_VERSION:   ${BUILD}
App version:                      ${VERSION}

Update CURRENT_PROJECT_VERSION before running the release workflow.
EOF
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Creating release DMG..."
rm -rf "$DMG_OUTPUT_DIR"
mkdir -p "$DMG_OUTPUT_DIR"
RELEASE_DMG_NAME="${RELEASE_DMG_NAME:-${APP_NAME}-${GITHUB_TAG}.dmg}"
FINAL_DMG="$DMG_OUTPUT_DIR/$RELEASE_DMG_NAME"

rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"
ditto "$APP_PATH" "$DMG_STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$FINAL_DMG"

codesign \
  --force \
  --sign "$DEVELOPER_ID_APPLICATION" \
  --timestamp \
  "$FINAL_DMG"

codesign --verify --verbose=2 "$FINAL_DMG"

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
