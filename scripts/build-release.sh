#!/bin/bash
# Builds a universal Linkyard.app, ad-hoc signed (there's no paid Apple Developer ID),
# and zips it into dist/ for a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(xcodebuild -project Browserino.xcodeproj -scheme Browserino -showBuildSettings 2>/dev/null | awk '/ MARKETING_VERSION /{print $3; exit}')
derived=build/release
app="$derived/Build/Products/Release/Linkyard.app"
zip="dist/Linkyard-$version.zip"

rm -rf "$derived" "$zip"
mkdir -p dist
xcodebuild -project Browserino.xcodeproj -scheme Browserino -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  build | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
codesign --force --deep --sign - "$app"
ditto -c -k --keepParent "$app" "$zip"

echo "$zip"
shasum -a 256 "$zip"
