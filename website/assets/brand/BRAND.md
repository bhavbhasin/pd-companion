# Kampa — Brand Kit

Authoritative brand assets and the one-command pipeline that regenerates them.
**If you need the logo as a PNG, use the files in this folder — don't re-screenshot the site.**

## Naming (two registers)

- **Logo / wordmark:** `kāmpa` — lowercase *k*, macron over the first *a*, the `ā` in brand blue.
- **In prose / sentences / headlines:** `Kampa` — capital *K*, no macron.
- **Legal / entity:** `Kampa Health`.
- **Domain / handle:** `kampa.health` (lowercase, no macron).
- **Etymology (italic when referenced):** *Kampavata* — the classical Ayurvedic term for the tremor disorder now called Parkinson's.

## Colors

| Token | Hex | Use |
|---|---|---|
| `--blue` | `#4A8CD6` | **Primary brand blue.** Accents, the macron `ā`, icons on dark. |
| `--blue-deep` | `#2F5D99` | Gradient end (app-icon squircle), deep accents. |
| white | `#FFFFFF` | Marks/text on dark surfaces. |
| dark text | `#1A1D22` | Wordmark on *light* surfaces (the SVG default fill). |
| card background | `#0B0B0C` | Near-black used for social cards. |

> Note: brand blue is `#4A8CD6`, **not** Apple system blue `#0A84FF`. Earlier social cards drifted to `#0A84FF` — use `#4A8CD6`.

## Font

**Geist** (Vercel, OFL — free). Loaded on the web via Google Fonts (weights 400/500/600).
The wordmark is **Geist Medium (500)**, `letter-spacing: -0.02em`, with the `ā` recolored to `--blue`.
For local rasterization/design tools, install Geist: download from Google Fonts or
`https://github.com/google/fonts/tree/main/ofl/geist` and drop the `.ttf` in `~/Library/Fonts`.

## Assets

**Sources** (`website/assets/*.svg`) — edit these:
- `kampa-app-icon.svg` — squircle app icon (own gradient, self-contained).
- `kampa-wave-mark.svg` / `kampa-wave-mark-blue.svg` — the steady-wave mark (uses `currentColor`).
- `kampa-wordmark.svg` — `kāmpa` text (font + color come from CSS, not the SVG).
- `kampa-lockup-horizontal.svg` — icon + wordmark lockup.

**Generated PNGs** (`website/assets/brand/*.png`) — high-res, transparent, dark-theme:
- `kampa-app-icon.png` · `kampa-wave-white.png` · `kampa-wave-blue.png` · `kampa-wordmark.png` · `kampa-lockup.png`

## Regenerating the PNGs

The SVGs are **theme-neutral** — the wave uses `stroke="currentColor"` and the wordmark
pulls its font/color from the page's CSS — so standalone they render black or empty.
`scripts/export-brand.sh` paints them for dark backgrounds (white + `#4A8CD6`) via an
rsvg stylesheet (`scripts/brand-theme-dark.css`) and emits PNGs with real alpha.

```sh
brew install librsvg          # one-time: provides rsvg-convert
# one-time: install the Geist .ttf into ~/Library/Fonts (see Font, above)
./scripts/export-brand.sh     # re-run whenever a source SVG changes
```

Without Geist installed, the wordmark renders empty (the script warns). Without
`librsvg`, it errors with the install hint.
