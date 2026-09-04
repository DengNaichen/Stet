#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

xcodebuild \
  -project Stet.xcodeproj \
  -scheme Stet \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

BUILD_SETTINGS="$(
  xcodebuild \
    -project Stet.xcodeproj \
    -scheme Stet \
    -configuration Debug \
    -destination 'platform=macOS' \
    -showBuildSettings
)"
TARGET_BUILD_DIR="$(printf '%s\n' "$BUILD_SETTINGS" | /usr/bin/sed -n 's/^[[:space:]]*TARGET_BUILD_DIR = //p')"
WRAPPER_NAME="$(printf '%s\n' "$BUILD_SETTINGS" | /usr/bin/sed -n 's/^[[:space:]]*WRAPPER_NAME = //p')"

if [[ -z "$TARGET_BUILD_DIR" || -z "$WRAPPER_NAME" ]]; then
  echo "Unable to resolve the Stet build product from Xcode build settings." >&2
  exit 1
fi

APP_BUNDLE="$TARGET_BUILD_DIR/$WRAPPER_NAME"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "No Stet app bundle found at $APP_BUNDLE" >&2
  exit 1
fi

APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$(defaults read "$APP_BUNDLE/Contents/Info.plist" CFBundleExecutable)"
"$APP_EXECUTABLE" --run-ai-rewrite-probe
