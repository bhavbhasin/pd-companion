#!/usr/bin/env bash
#
# export-brand.sh — Rasterize the Kampa brand SVGs to high-res transparent PNGs.
#
# Why this exists: the brand marks live as SVGs (great for the web, unusable
# elsewhere). Keynote/Canva/scripts/LLM tools can't reliably rasterize SVG, and
# the marks are theme-neutral — wave uses stroke="currentColor", the wordmark
# pulls font + color from the page's CSS — so standalone they render black/empty.
# This script paints them for dark backgrounds (white + brand blue) and emits
# authoritative PNGs with real alpha. Re-run whenever a source SVG changes.
#
# Requires:  rsvg-convert  (brew install librsvg)   and the Geist font installed
#            (Google Fonts / vercel-geist). See BRAND.md.
#
set -euo pipefail
cd "$(dirname "$0")/.."                       # -> website/
SRC="assets"; OUT="assets/brand"; CSS="scripts/brand-theme-dark.css"; Z="${ZOOM:-4}"

command -v rsvg-convert >/dev/null 2>&1 || {
  echo "error: rsvg-convert not found.  brew install librsvg" >&2; exit 1; }
fc-list 2>/dev/null | grep -i geist >/dev/null || \
  echo "warning: Geist font not found — the wordmark may render empty. See BRAND.md." >&2

mkdir -p "$OUT"
rm -f "$OUT"/*.png                            # deterministic output set
echo "Exporting brand PNGs -> $OUT (zoom ${Z}x, transparent)"

# App icon: self-contained (own gradient) — export as-is.
rsvg-convert -z "$Z" "$SRC/kampa-app-icon.svg"            -o "$OUT/kampa-app-icon.png"

# Wave mark: themed white (primary) and brand-blue.
rsvg-convert -z "$Z" --stylesheet "$CSS" "$SRC/kampa-wave-mark.svg" -o "$OUT/kampa-wave-white.png"
printf '* { color: #4A8CD6; }\n' > /tmp/_kampa_blue.css
rsvg-convert -z "$Z" --stylesheet /tmp/_kampa_blue.css "$SRC/kampa-wave-mark.svg" -o "$OUT/kampa-wave-blue.png"

# Wordmark + horizontal lockup: white text, ā in brand blue.
rsvg-convert -z "$Z" --stylesheet "$CSS" "$SRC/kampa-wordmark.svg"           -o "$OUT/kampa-wordmark.png"
rsvg-convert -z "$Z" --stylesheet "$CSS" "$SRC/kampa-lockup-horizontal.svg"  -o "$OUT/kampa-lockup.png"

echo "Done."
