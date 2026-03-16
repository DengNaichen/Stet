#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Stet.xcodeproj"
SCHEME="Stet"

BUILD_ROOT="$ROOT_DIR/.build"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
SOURCE_PACKAGES_PATH="$BUILD_ROOT/SourcePackages"
PACKAGE_CACHE_PATH="$BUILD_ROOT/PackageCache"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/Stet.app"

mkdir -p "$BUILD_ROOT" "$DIST_DIR"

# Remove stale outputs from the previous airType product name before rebuilding.
rm -rf \
  "$DIST_DIR/Stet.app" \
  "$DIST_DIR/Stet.app.dSYM" \
  "$DIST_DIR/Stet.swiftmodule" \
  "$DIST_DIR/airType.app" \
  "$DIST_DIR/airType.app.dSYM" \
  "$DIST_DIR/airType.swiftmodule"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_PATH" \
  -packageCachePath "$PACKAGE_CACHE_PATH" \
  CONFIGURATION_BUILD_DIR="$DIST_DIR" \
  build

codesign --verify --deep --strict "$APP_PATH"

echo
echo "Built app:"
echo "  $APP_PATH"
