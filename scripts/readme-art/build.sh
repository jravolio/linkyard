# Sourced by render-ui.sh and render-animations.sh with $here, $root and $work set.
# Compiles Linkyard's sources, minus the app entry point and #Preview blocks, with the given harness files into "$work/$1".
build_harness() {
  local binary=$1
  shift
  (cd "$root/Browserino" && find . -name '*.swift' ! -name main.swift ! -name BrowserinoApp.swift ! -name BrowserinoApplication.swift ! -name Updates.swift) | while read -r file; do
    mkdir -p "$work/src/$(dirname "$file")"
    awk '/^#Preview/{exit} {print}' "$root/Browserino/$file" > "$work/src/$file"
  done
  xcrun swiftc -O -parse-as-library -enable-bare-slash-regex -target arm64-apple-macos14.4 \
    -o "$work/$binary" $(find "$work/src" -name '*.swift') "$here/demo.swift" "$@"
  mkdir -p "$work/out" "$work/home"
  cp -R "$here/demo-home/." "$work/home/"
}
