#!/bin/bash
# Builds, previews or checks the website in site/ with the pinned Node (scripts/get-node.sh).
# Usage: site.sh dev | build | check
#   dev    serves the site with live reload at http://localhost:5173/Cutaway/
#   build  builds it into site/.vitepress/dist; a dead internal link fails the build
#   check  builds it, then checks the size budgets and lists the media still to be made
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
site="$repo_root/site"

fail() {
  echo "site: $1" >&2
  exit 1
}

# In CI, actions/setup-node provides the same version; elsewhere use the pinned one.
if [[ -z "${CI:-}" ]]; then
  PATH="$("$script_dir/get-node.sh"):$PATH"
  export PATH
fi

cd "$site"
if [[ ! -d node_modules ]] || [[ package-lock.json -nt node_modules ]]; then
  npm ci --no-fund --no-audit
fi

# Every image and video of the site together, and what the home page loads before scrolling.
media_budget=$((25 * 1024 * 1024))
first_screen_budget=$((1536 * 1024))

bytes() {
  stat -c %s "$@" 2>/dev/null || stat -f %z "$@"
}

check() {
  npx vitepress build

  local media_total=0 size
  while IFS= read -r -d '' file; do
    size="$(bytes "$file")"
    media_total=$((media_total + size))
  done < <(find public -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.mp4' -o -name '*.svg' \) -print0)
  echo "site: images and videos: $((media_total / 1024)) KB of $((media_budget / 1024)) KB"
  ((media_total <= media_budget)) || fail "images and videos exceed the budget"

  # The home page's first screen: its HTML, the scripts and styles it links, and the product
  # picture in one appearance.
  local dist=.vitepress/dist first_screen
  first_screen=$(($(bytes "$dist/index.html") + $(bytes public/media/home-overview-light.png)))
  local asset
  while IFS= read -r asset; do
    [[ -f "$dist/$asset" ]] && first_screen=$((first_screen + $(bytes "$dist/$asset")))
  done < <(grep -oE '/Cutaway/assets/[^"]+\.(js|css)' "$dist/index.html" | sed 's|^/Cutaway/||' | sort -u)
  echo "site: home page before scrolling: $((first_screen / 1024)) KB of $((first_screen_budget / 1024)) KB"
  ((first_screen <= first_screen_budget)) || fail "the home page's first screen exceeds the budget"

  # Screenshots and videos the pages name but public/media does not have yet.
  local missing=0 name
  while IFS= read -r name; do
    if [[ ! -f "public/media/$name-light.png" || ! -f "public/media/$name-dark.png" ]]; then
      echo "site: screenshot still to make: $name"
      missing=$((missing + 1))
    fi
  done < <(grep -rhoE '<Shot name="[^"]+"' --include='*.md' . --exclude-dir=node_modules | sed -E 's/.*name="([^"]+)"/\1/' | sort -u)
  while IFS= read -r name; do
    if [[ ! -f "public/media/$name.mp4" ]]; then
      echo "site: video still to make: $name"
      missing=$((missing + 1))
    fi
  done < <(grep -hoE "video: '[^']+'" .vitepress/theme/components/HomePage.vue | sed -E "s/video: '([^']+)'/\1/" | sort -u)
  echo "site: $missing screenshots and videos are placeholders"
}

case "${1:-}" in
  dev) exec npx vitepress dev ;;
  build) npx vitepress build ;;
  check) check ;;
  *) fail "usage: site.sh dev | build | check" ;;
esac
