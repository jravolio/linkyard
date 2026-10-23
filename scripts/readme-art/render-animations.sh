#!/bin/bash
# Records the picker's effects into docs/assets/picker-animations.gif. Needs ffmpeg.
# The picker opens in the middle of the main screen for about fifteen seconds while it records.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"

source "$here/build.sh"
build_harness record "$here/animations.swift"
xcrun -sdk macosx metal "$root/Browserino/Views/Prompt/PickerEffects.metal" -o "$work/default.metallib"
CFFIXED_USER_HOME="$work/home" "$work/record" "$work/out"

ffmpeg -loglevel error -y -f concat -safe 0 -i "$work/out/frames.txt" \
  -vf "fps=30,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
  -loop 0 "$root/docs/assets/picker-animations.gif"
echo "$root/docs/assets/picker-animations.gif"
