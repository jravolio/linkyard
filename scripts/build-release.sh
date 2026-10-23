#!/bin/bash
# Builds a universal Linkyard.app, ad-hoc signed (there's no paid Apple Developer ID),
# and zips it into dist/ for a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

derived=build/release
app="$derived/Build/Products/Release/Linkyard.app"

rm -rf "$derived"
mkdir -p dist
# netrc: Sparkle is public, and the default Keychain lookup can wait forever on a Keychain prompt.
xcodebuild -project Browserino.xcodeproj -scheme Browserino -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" -packageAuthorizationProvider netrc \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  build | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'

# Sparkle's XPC services are only for sandboxed apps. Nested code is signed inside out instead of with the deprecated --deep.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
rm -rf "$sparkle/XPCServices" "$sparkle/Versions/B/XPCServices"
for code in "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle" "$app"; do
  codesign --force --sign - "$code"
done

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
zip="dist/Linkyard-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

echo "$zip"
shasum -a 256 "$zip"
