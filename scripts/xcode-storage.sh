#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
user_home="${HOME:?HOME must be set}"
derived_data_root="$user_home/Library/Developer/Xcode/DerivedData"
archives_root="$user_home/Library/Developer/Xcode/Archives"
swiftpm_cache_root="$user_home/Library/Caches/org.swift.swiftpm"

workspace_paths=(
  "$project_root/Stet.xcodeproj"
  "$project_root/StetMobile/StetMobile.xcodeproj"
)

local_cache_paths=(
  "$project_root/.derivedData"
  "$project_root/.build/AppleIntelligenceRewriteProbe"
  "$project_root/Packages/StetEngine/.build"
  "$project_root/sherpa-onnx/build-swift-macos"
  "$project_root/StetMobile/.derivedData"
  "$project_root/StetMobile/.build"
)

if [[ ! -d "$project_root/Stet.xcodeproj" ]]; then
  echo "Refusing to run outside the Stet repository: $project_root" >&2
  exit 1
fi

print_size() {
  local label="$1"
  local target_path="$2"

  if [[ -e "$target_path" || -L "$target_path" ]]; then
    printf '%-34s %s\n' "$label" "$(du -sh "$target_path" 2>/dev/null | /usr/bin/awk '{print $1}')"
  else
    printf '%-34s %s\n' "$label" "0B"
  fi
}

is_expected_workspace() {
  local workspace_path="$1"
  local expected_workspace

  for expected_workspace in "${workspace_paths[@]}"; do
    if [[ "$workspace_path" == "$expected_workspace" ]]; then
      return 0
    fi
  done

  return 1
}

project_derived_data_paths() {
  local candidate
  local workspace_path

  [[ -d "$derived_data_root" ]] || return 0

  for candidate in "$derived_data_root"/*(N/); do
    [[ -f "$candidate/info.plist" ]] || continue
    workspace_path="$(/usr/bin/plutil -extract WorkspacePath raw -o - "$candidate/info.plist" 2>/dev/null || true)"
    if is_expected_workspace "$workspace_path"; then
      printf '%s\n' "$candidate"
    fi
  done
}

doctor() {
  local cache_path
  local found_project_cache=0

  echo "Disk"
  df -h / | tail -n 1
  echo

  echo "Project-local build caches"
  for cache_path in "${local_cache_paths[@]}"; do
    print_size "${cache_path#$project_root/}" "$cache_path"
  done
  echo

  echo "Matching Xcode DerivedData"
  while IFS= read -r cache_path; do
    [[ -n "$cache_path" ]] || continue
    found_project_cache=1
    print_size "${cache_path:t}" "$cache_path"
  done < <(project_derived_data_paths)
  if [[ "$found_project_cache" -eq 0 ]]; then
    echo "No Stet/StetMobile DerivedData found."
  fi
  print_size "Shared Xcode module caches" "$derived_data_root/ModuleCache.noindex"
  print_size "SwiftPM download cache" "$swiftpm_cache_root"
  print_size "Xcode Archives (preserved)" "$archives_root"
  echo

  echo "Simulator runtimes (preserved by this script)"
  xcrun simctl runtime list -v 2>/dev/null || echo "Unable to query simulator runtimes."
}

validate_no_symlink_components() {
  local checked_path="$1"
  local allowed_root="$2"
  local current_path="$checked_path"

  while [[ "$current_path" != "$allowed_root" ]]; do
    if [[ "$current_path" == "/" ]]; then
      echo "Deletion target escapes its allowed root: $checked_path" >&2
      return 1
    fi
    if [[ -L "$current_path" ]]; then
      echo "Refusing path with symlink component: $current_path" >&2
      return 1
    fi
    current_path="${current_path:h}"
  done

  if [[ -L "$allowed_root" ]]; then
    echo "Refusing symlinked allowed root: $allowed_root" >&2
    return 1
  fi
}

validate_deletion_target() {
  local target="$1"

  if [[ -L "$target" ]]; then
    echo "Refusing to delete symlink: $target" >&2
    return 1
  fi

  case "$target" in
    "$project_root/.derivedData" | \
      "$project_root/.build/AppleIntelligenceRewriteProbe" | \
      "$project_root/Packages/StetEngine/.build" | \
      "$project_root/sherpa-onnx/build-swift-macos" | \
      "$project_root/StetMobile/.derivedData" | \
      "$project_root/StetMobile/.build")
      validate_no_symlink_components "$target" "$project_root" || return 1
      return 0
      ;;
  esac

  if [[ "$target" == "$derived_data_root"/* ]] && [[ -f "$target/info.plist" ]]; then
    validate_no_symlink_components "$target" "$derived_data_root" || return 1
    local workspace_path
    workspace_path="$(/usr/bin/plutil -extract WorkspacePath raw -o - "$target/info.plist" 2>/dev/null || true)"
    if is_expected_workspace "$workspace_path"; then
      return 0
    fi
  fi

  echo "Refusing unapproved deletion target: $target" >&2
  return 1
}

clean_project() {
  local cache_path
  local deletion_paths=("${local_cache_paths[@]}")
  local process_name
  local process_pattern
  local busy_processes=()
  local build_process_names=(
    Xcode
    xcodebuild
    xcode-build-server
    XCBBuildService
    SWBBuildService
    sourcekit-lsp
    SourceKitService
    swift
    swift-build
    swift-test
    swift-package
    swift-driver
    swiftc
    swift-frontend
    xctest
  )
  local build_process_patterns=(
    '/xcode-build-server([[:space:]]|$)'
  )

  for process_name in "${build_process_names[@]}"; do
    if /usr/bin/pgrep -x "$process_name" >/dev/null 2>&1; then
      busy_processes+=("$process_name")
    fi
  done

  for process_pattern in "${build_process_patterns[@]}"; do
    if /usr/bin/pgrep -f "$process_pattern" >/dev/null 2>&1; then
      busy_processes+=(xcode-build-server)
    fi
  done

  if (( ${#busy_processes[@]} > 0 )); then
    echo "Build tooling is running: ${(j:, :)busy_processes}. Quit it before cleaning DerivedData." >&2
    exit 2
  fi

  while IFS= read -r cache_path; do
    [[ -n "$cache_path" ]] && deletion_paths+=("$cache_path")
  done < <(project_derived_data_paths)

  echo "Deleting only allowlisted, reproducible Stet build caches:"
  for cache_path in "${deletion_paths[@]}"; do
    [[ -e "$cache_path" || -L "$cache_path" ]] || continue
    validate_deletion_target "$cache_path"
    printf '  %s (%s)\n' "$cache_path" "$(du -sh "$cache_path" 2>/dev/null | /usr/bin/awk '{print $1}')"
    rm -rf -- "$cache_path"
  done

  echo "Done. Archives, signing data, models, frameworks, and simulator runtimes were not touched."
}

case "${1:-doctor}" in
  doctor)
    doctor
    ;;
  clean-project)
    clean_project
    ;;
  *)
    echo "Usage: $0 {doctor|clean-project}" >&2
    exit 64
    ;;
esac
