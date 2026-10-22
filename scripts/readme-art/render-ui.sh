#!/bin/bash
# Renders the picker and Settings views with demo profiles, then composes the README art.
# A throwaway home folder keeps your real browser profiles out of the screenshots.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"

cd "$root/Browserino"
find . -name '*.swift' ! -name main.swift ! -name BrowserinoApp.swift ! -name BrowserinoApplication.swift | while read -r file; do
  mkdir -p "$work/src/$(dirname "$file")"
  awk '/^#Preview/{exit} {print}' "$file" > "$work/src/$file"
done

xcrun swiftc -O -parse-as-library -enable-bare-slash-regex -target arm64-apple-macos14.4 \
  -o "$work/render" $(find "$work/src" -name '*.swift') "$here/harness.swift"
mkdir -p "$work/out" "$work/home"
cp -R "$here/demo-home/." "$work/home/"
CFFIXED_USER_HOME="$work/home" "$work/render" "$work/out"
python3 -I "$here/compose.py" "$work/out" "$root"
