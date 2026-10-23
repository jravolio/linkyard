#!/bin/bash
# Renders the picker and Settings views with demo profiles, then composes the README art.
# A throwaway home folder keeps your real browser profiles out of the screenshots.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"

source "$here/build.sh"
build_harness render "$here/harness.swift"
CFFIXED_USER_HOME="$work/home" "$work/render" "$work/out"
python3 -I "$here/compose.py" "$work/out" "$root"
