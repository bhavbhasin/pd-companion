#!/usr/bin/env bash
#
# refresh-bhaani-folder.sh
# Re-snapshots the Kampa onboarding files into ~/Documents/Kampa-for-Bhaani/
# with flattened, numbered names, ready to drag into Google Drive.
#
# Run from anywhere:  bash scripts/refresh-bhaani-folder.sh
# Safe to re-run: it overwrites the staged copies, never touches the repo originals.
#
# It also AUDITS the repo for any .md files that are neither included nor
# deliberately excluded, and flags them so you can decide whether Bhaani
# should have them. The script never auto-adds new files - it only flags.

set -euo pipefail

# Repo root = the parent of this script's directory, so it works regardless of CWD.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/Documents/Kampa-for-Bhaani"

# --- INCLUDED: "source-relative-path  =>  destination filename" -------------
# Edit this list when you decide a new doc belongs in Bhaani's folder.
INCLUDE=(
  "README.md=>01 - README.md"
  "ParkinsonsProject.md=>02 - Project Context (ParkinsonsProject).md"
  "docs/intelligence-architecture.md=>03 - Intelligence Architecture.md"
  "PD Companion/PD_Companion_Competitive_Analysis_Roadmap.md=>04 - Competitive Analysis and Roadmap.md"
  "BACKLOG.md=>05 - Backlog.md"
  "analysis/NOTES.md=>06 - Analysis Notes.md"
  "marketing/CONTRIBUTOR_GUIDE.md=>07 - Contributor Guide (READ THIS).md"
  "marketing/linkedin/README.md=>08 - LinkedIn Tracker.md"
  "marketing/linkedin/2026-06-17-privacy/post.md=>09 - Example Post - Privacy.md"
  "marketing/linkedin/2026-06-20-three-insights/post.md=>10 - Example Post - Three Insights.md"
  "website/assets/brand/BRAND.md=>11 - Brand Guide.md"
)

# --- EXCLUDED ON PURPOSE: repo-relative paths to NOT flag in the audit ------
# Add a path here once you've consciously decided it should never go to Bhaani,
# so the audit stops nagging you about it.
EXCLUDE=(
  "Scratchpad.md"    # Bhav's personal notepad for ideas to discuss - never share
)

# ---------------------------------------------------------------------------
mkdir -p "$DEST"
echo "Refreshing $DEST from $REPO ..."

for entry in "${INCLUDE[@]}"; do
  src="${entry%%=>*}"
  dst="${entry##*=>}"
  if [ -f "$REPO/$src" ]; then
    cp "$REPO/$src" "$DEST/$dst"
    echo "  copied: $dst"
  else
    echo "  MISSING SOURCE (skipped): $src  ->  $dst"
  fi
done

# "00 - Start Here.md" is hand-written and intentionally NOT overwritten.
if [ ! -f "$DEST/00 - Start Here.md" ]; then
  echo "  WARNING: '00 - Start Here.md' is missing - it is not auto-generated. Re-create it manually."
fi

echo "Done. $(ls -1 "$DEST" | wc -l | tr -d ' ') files in $DEST"

# --- AUDIT: find unclassified .md files ------------------------------------
echo ""
echo "Auditing repo for new .md files ..."

# Build a lookup of paths already accounted for (included + excluded).
known=$'\n'
for entry in "${INCLUDE[@]}"; do known+="${entry%%=>*}"$'\n'; done
for path  in "${EXCLUDE[@]}"; do known+="$path"$'\n'; done

flagged=0
while IFS= read -r -d '' file; do
  rel="${file#"$REPO"/}"
  case "$known" in
    *$'\n'"$rel"$'\n'*) : ;;                       # already known - ignore
    *) echo "  NEW / UNCLASSIFIED: $rel"; flagged=$((flagged+1)) ;;
  esac
done < <(find "$REPO" -type f -name "*.md" \
           -not -path "*/.git/*" \
           -not -path "*/node_modules/*" \
           -not -path "*/.venv/*" \
           -not -path "*/site-packages/*" \
           -print0)

if [ "$flagged" -eq 0 ]; then
  echo "  None. Every repo .md file is either included or deliberately excluded."
else
  echo ""
  echo "  ^ $flagged file(s) above are new. To resolve each one, edit this script:"
  echo "    - belongs in Bhaani's folder -> add a line to INCLUDE"
  echo "    - should never be shared      -> add the path to EXCLUDE"
fi

echo ""
echo "Next: drag the folder into Google Drive to update Bhaani's copy."
