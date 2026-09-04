#!/bin/zsh
set -euo pipefail

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>  (e.g. $0 0.1.5)"
  exit 1
fi

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "Error: version must be in major.minor.patch format (got: $VERSION)"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT_DIR/Stet.xcodeproj/project.pbxproj"

IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
BUILD_NUMBER=$(( MAJOR * 1000000 + MINOR * 1000 + PATCH ))

CURRENT_VERSION="$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= //;s/;//')"

if [[ "$CURRENT_VERSION" == "$VERSION" ]]; then
  echo "Already at version $VERSION, nothing to do."
  exit 0
fi

echo "Bumping $CURRENT_VERSION → $VERSION (build $BUILD_NUMBER)"

sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${VERSION};/g" "$PBXPROJ"

CURRENT_BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= //;s/;//')"
sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};/g" "$PBXPROJ"

cd "$ROOT_DIR"
git add Stet.xcodeproj/project.pbxproj
git commit -m "Bump version to $VERSION"
git tag "v$VERSION"
git push origin main
git push origin "v$VERSION"

echo "Released v$VERSION (build $BUILD_NUMBER)"
