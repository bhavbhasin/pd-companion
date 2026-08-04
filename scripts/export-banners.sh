#!/usr/bin/env bash
#
# export-banners.sh
# Renders the social banners from website/assets/brand/banner.html via headless
# Chrome, one PNG per platform target.
#
# Run from anywhere:  bash scripts/export-banners.sh
# Re-run whenever banner.html changes. The PNGs are generated - never edit them
# by hand.
#
# Chrome (not rsvg) because the banner composes a CSS gradient, a webfont and an
# SVG together; export-brand.sh stays the tool for the plain SVG marks.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/website/assets/brand/banner.html"
OUT="$REPO/website/assets/brand"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ ! -x "$CHROME" ]; then
  echo "Chrome not found at:"
  echo "  $CHROME"
  echo "Install Google Chrome, or point CHROME at another Chromium build."
  exit 1
fi

# target=WIDTHxHEIGHT  ->  kampa-banner-<target>.png
TARGETS=(
  "youtube=2048x1152"
  "linkedin=1584x396"
  "x=1500x500"
  "company=1128x191"
)

for entry in "${TARGETS[@]}"; do
  name="${entry%%=*}"
  size="${entry##*=}"
  dst="$OUT/kampa-banner-$name.png"

  "$CHROME" \
    --headless \
    --disable-gpu \
    --hide-scrollbars \
    --force-device-scale-factor=1 \
    --window-size="${size/x/,}" \
    --virtual-time-budget=6000 \
    --screenshot="$dst" \
    "file://$SRC?target=$name" >/dev/null 2>&1

  if [ -f "$dst" ]; then
    echo "  rendered: $(basename "$dst")  ($size)"
  else
    echo "  FAILED:   $(basename "$dst")"
  fi
done

echo ""
echo "Done. PNGs in website/assets/brand/"
