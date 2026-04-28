#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.build/AppleIntelligenceRewriteProbe"

cd "$ROOT_DIR"

xcodebuild \
  -project Stet.xcodeproj \
  -scheme Stet \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_BUNDLE="$(find "$DERIVED_DATA_PATH/Build/Products/Debug" -maxdepth 1 -name 'Stet*.app' -print -quit)"
if [[ -z "$APP_BUNDLE" ]]; then
  echo "No Stet app bundle found under $DERIVED_DATA_PATH/Build/Products/Debug" >&2
  exit 1
fi

APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$(defaults read "$APP_BUNDLE/Contents/Info.plist" CFBundleExecutable)"
"$APP_EXECUTABLE" --run-ai-rewrite-probe
