#!/bin/bash
# Puts a screenshot or a video into the website with the size and name the pages expect
# (site/MEDIA.md lists them). Uses only tools that come with macOS.
# Usage:
#   site-media.sh shot <name> <light.png> <dark.png>
#       scales both to at most 1600 pixels wide, converts them to the generic Display P3 profile and
#       writes <name>-light.png and <name>-dark.png
#   site-media.sh video <name> <recording.mov>
#       converts to H.264 at most 1280 pixels wide, 30 frames a second and 1.2 Mbit/s (the page plays
#       it muted; scripts/site-video.swift) and writes <name>.mp4 and a poster <name>.jpg made from its
#       first frame
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
media="$(cd "$script_dir/.." && pwd)/site/public/media"

fail() {
  echo "site-media: $1" >&2
  exit 1
}

max_width=1600
# A screenshot carries the profile of the display it was taken on, which names the display's model
# and maker, and sometimes its serial number. Converting to the generic profile keeps the colours
# and leaves none of that in the file.
display_p3="/System/Library/ColorSync/Profiles/Display P3.icc"

shot() {
  local source="$1" destination="$2" width
  [[ -f "$source" ]] || fail "no such file: $source"
  width="$(sips -g pixelWidth "$source" | awk '/pixelWidth/ { print $2 }')"
  if ((width > max_width)); then
    sips --resampleWidth "$max_width" "$source" --out "$destination" >/dev/null
  else
    cp "$source" "$destination"
  fi
  sips --matchTo "$display_p3" "$destination" --out "$destination" >/dev/null
  echo "site-media: wrote ${destination#"$media/"} ($(($(stat -f %z "$destination") / 1024)) KB)"
}

case "${1:-}" in
  shot)
    [[ $# -eq 4 ]] || fail "usage: site-media.sh shot <name> <light.png> <dark.png>"
    shot "$3" "$media/$2-light.png"
    shot "$4" "$media/$2-dark.png"
    ;;
  video)
    [[ $# -eq 3 ]] || fail "usage: site-media.sh video <name> <recording.mov>"
    [[ -f "$3" ]] || fail "no such file: $3"
    swift "$script_dir/site-video.swift" "$3" "$media/$2.mp4" "$media/$2.jpg" >/dev/null
    echo "site-media: wrote $2.mp4 ($(($(stat -f %z "$media/$2.mp4") / 1024)) KB)"
    ;;
  *) fail "usage: site-media.sh shot <name> <light.png> <dark.png> | video <name> <recording.mov>" ;;
esac
