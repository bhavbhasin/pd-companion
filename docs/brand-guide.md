# Kampa Brand Reference

The single source of truth for any Kampa artifact - PDFs, reports, emails, social, decks.
When in doubt, match this. Reference implementations: the neurologist report
(`PD Companion/PD Companion/Reports/ClinicalReportPDF.swift` → `drawHeader`) and the onboarding
guide (`docs/Kampa-Getting-Started.html`).

## Colors

| Token | Hex | Use |
|---|---|---|
| **Brand blue** | `#4A8CD6` | The wave mark, the **ā** in the wordmark, links, accents, eyebrows, rule accents. This is *the* Kampa blue. |
| Deep blue | `#2F5D99` | **Only** the app-icon squircle gradient (bottom stop). Do **not** use for the wave mark or the wordmark ā. |
| Ink | `#1A1D22` | Body text, the `k` and `mpa` of the wordmark. |
| Gray | `#6B7280` | Secondary text, captions, disclaimers. |
| Hairline | `#E0E0E0` | Header rule / dividers on light backgrounds. |
| Light tint | `#F4F8FD` (border `#D9E6F5`) | Callout/note boxes on light backgrounds. |
| Website dark | bg `#0a0a0a`, surfaces `#111113` / `#1c1c1e`, border `#2c2c2e` | Website only. |

> ⚠️ Common mistake (fixed Jun 22, 2026): the wave mark must be **`#4A8CD6`**, not the darker `#2F5D99`.
> The repo asset `website/assets/kampa-wave-mark-blue.svg` is drawn in `#2F5D99` - recolor to `#4A8CD6` when using it as a mark.

## Typeface

**Geist** (Regular 400 / Medium 500 / SemiBold 600). TTFs: `PD Companion/PD Companion/Fonts/`.
Wordmark and display use Geist; the website also loads Inter for long-form body copy.

## Wordmark

- `kāmpa` - all lowercase, with the macron **ā** (Unicode U+0101).
- `k` and `mpa` = ink `#1A1D22`; **ā** = brand blue `#4A8CD6`.
- **Geist Medium (500)**, letter-spacing **-0.02em** (= -0.48 kern at 24pt).
- Document-header size: **24pt**.

## Wave mark ("steady wave")

- SVG, viewBox `0 0 240 144` (**aspect 1.667 : 1**):
  - path `M8 90 C 28 90, 30 30, 56 30 C 78 30, 80 110, 104 95 C 124 82, 126 60, 150 60 C 168 60, 172 78, 192 78 L 232 78`, `stroke-width 8`, round caps + joins
  - endpoint dot: `circle cx=232 cy=78 r=5`
- Color: **`#4A8CD6`**.
- Document-header size: **height 32pt** (≈1.3× the 24pt wordmark), ~8-10px gap before the wordmark, vertically centered.

## Document header lockup (PDFs / reports)

```
[ wave mark 32pt ]  kāmpa(24pt)            EYEBROW TITLE (blue, 11pt, caps)
                                            Subtitle (gray, 11.5pt)
──────────────────────────────────────────────────────────  (hairline #E0E0E0)
```

## App icon (icon contexts only - not a document mark)

Rounded squircle (`rx 32` on a 140 box), vertical gradient `#4A8CD6` (top) → `#2F5D99` (bottom),
white wave stroke + white endpoint dot.

## Voice & claims

Calibrated, never overstated - lead with capability, show confidence tiers, always carry
"your data, not medical advice." **Never disclose Bhav's own PD** in any public artifact.

## How to render a PDF artifact

1. Edit the HTML template (e.g. `docs/Kampa-Getting-Started.html`).
2. Render with headless Chrome:
   ```
   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
     --no-pdf-header-footer --allow-file-access-from-files \
     --print-to-pdf="docs/OUT.pdf" "file:///Users/bhav/documents/ParkinsonsProject/docs/IN.html"
   ```
   (Fonts are referenced by absolute `file://` path, so they embed correctly.)
