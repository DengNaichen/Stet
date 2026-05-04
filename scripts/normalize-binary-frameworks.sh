#!/bin/zsh
set -euo pipefail

signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  signing_identity="-"
fi

timestamp_args=(--timestamp=none)
if [[ "${CONFIGURATION:-}" == "Release" && "$signing_identity" != "-" ]]; then
  timestamp_args=(--timestamp)
fi

normalize_versioned_framework() {
  local framework_path="$1"
  local framework_name="$2"
  local binary_name="$3"
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

  echo "Normalizing and signing $framework_name"
  codesign \
    --force \
    --sign "$signing_identity" \
    "${timestamp_args[@]}" \
    --preserve-metadata=identifier,entitlements,flags \
    "$framework_path"
}

DERIVED_DATA_DIR="$(cd "${BUILD_DIR:-$TARGET_BUILD_DIR}/../.." && pwd)"
SHERPA_ARTIFACT_DIR="$DERIVED_DATA_DIR/SourcePackages/artifacts/sherpaonnxpackage/sherpa_onnx/Packages/StetEngine/Vendor/SherpaOnnxPackage/sherpa-onnx-new.xcframework"

normalize_versioned_framework \
  "$SHERPA_ARTIFACT_DIR/macos-arm64_x86_64/sherpa_onnx.framework" \
  "SwiftPM sherpa_onnx.framework artifact" \
  "sherpa_onnx"

APP_FRAMEWORKS_DIR="${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-}"
if [[ -d "$APP_FRAMEWORKS_DIR" ]]; then
  normalize_versioned_framework "$APP_FRAMEWORKS_DIR/sherpa_onnx.framework" "embedded sherpa_onnx.framework" "sherpa_onnx"
fi
