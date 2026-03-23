#!/bin/zsh

set -euo pipefail

cd "$(dirname "$0")/.."

project="apps/mac/Stet.xcodeproj"
scheme="Stet"

if ! command -v xcode-build-server >/dev/null 2>&1; then
  echo "xcode-build-server is not installed."
  echo "Install it with: brew install xcode-build-server"
  exit 1
fi

xcode-build-server config -project "$project" -scheme "$scheme"

echo "Generated $(pwd)/buildServer.json for SourceKit-LSP."
echo "If diagnostics still look stale, rerun the VS Code build task once."
