#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Stet.xcodeproj"
SCHEME="Stet"
LOCAL_RELEASE_BUNDLE_ID="${LOCAL_RELEASE_BUNDLE_ID:-NaichengDeng.Stet.LocalRelease}"
LOCAL_RELEASE_URL_SCHEME="${LOCAL_RELEASE_URL_SCHEME:-naichengdeng.stet.localrelease}"

BUILD_ROOT="$ROOT_DIR/.build"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
SOURCE_PACKAGES_PATH="$BUILD_ROOT/SourcePackages"
PACKAGE_CACHE_PATH="$BUILD_ROOT/PackageCache"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/Stet.app"

mkdir -p "$BUILD_ROOT" "$DIST_DIR"

# Clear stale repo-local package caches after path or product renames.
if [[ -f "$SOURCE_PACKAGES_PATH/workspace-state.json" ]] && \
  grep -q "/Users/nd/Developer/airType" "$SOURCE_PACKAGES_PATH/workspace-state.json"; then
  rm -rf "$SOURCE_PACKAGES_PATH" "$PACKAGE_CACHE_PATH"
fi

if [[ -f "$DERIVED_DATA_PATH/SourcePackages/workspace-state.json" ]] && \
  grep -q "/Users/nd/Developer/airType" "$DERIVED_DATA_PATH/SourcePackages/workspace-state.json"; then
  rm -rf "$DERIVED_DATA_PATH"
fi

# Remove stale outputs from earlier product names before rebuilding.
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
  PRODUCT_BUNDLE_IDENTIFIER="$LOCAL_RELEASE_BUNDLE_ID" \
  APP_URL_SCHEME="$LOCAL_RELEASE_URL_SCHEME" \
  build

codesign --verify --deep --strict "$APP_PATH"

echo
echo "Built app:"
echo "  $APP_PATH"
echo "  Bundle ID: $LOCAL_RELEASE_BUNDLE_ID"
