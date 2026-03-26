#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Stet.xcodeproj"
SCHEME="StetVisuals"
BUILD_DIR="$ROOT_DIR/build/StetVisuals"
ARCHIVE_PATH="$BUILD_DIR/StetVisuals-macOS.xcarchive"
OUTPUT_PATH="${1:-$ROOT_DIR/dist/StetVisuals.xcframework}"

rm -rf "$BUILD_DIR" "$OUTPUT_PATH"
mkdir -p "$BUILD_DIR" "$(dirname "$OUTPUT_PATH")"

xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

xcodebuild -create-xcframework \
  -framework "$ARCHIVE_PATH/Products/Library/Frameworks/StetVisuals.framework" \
  -output "$OUTPUT_PATH"

echo "Created $OUTPUT_PATH"
