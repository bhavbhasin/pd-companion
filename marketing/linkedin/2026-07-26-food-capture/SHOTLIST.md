# Shot list — food capture post (2026-07-26)

## Video (the lead asset)

**The money shot is `EventDetailSheet` — "Entry" above, "Detected" chips below** (`Views/EventDetailSheet.swift:58-83`).
That single screen is the whole thesis: raw human sentence in, engine-legible attributes out.

⚠ **Flow reality — plan for two beats, not one.** Classification runs at *commit*
(`Voice/VoiceLogView.swift:233`), then the sheet dismisses. The chips do **not** animate in while you
speak. So don't try to film a single continuous "watch it decompose" take — it doesn't exist and
faking it in the edit would be a claim about the product that isn't true.

**Sequence (~12-15s, silent, captioned):**
1. `+` screen, thumb moves to the mic. (1s)
2. Tap → recording state. Say something with **multiple attributes and a non-Western dish** — the
   caption on screen carries the audio. Good candidates from real entries:
   **"Chai, almonds, walnuts and a date"** → caffeine · protein · fiber · fat · sugar (5/5 chips, best
   payoff), or **"Rice, daal and okra roti"** → protein · fiber · fat.
3. Transcript appears in the confirm state, editable. Hold 1.5s — this beat proves it's correcting for
   dictation, not just transcribing.
4. Commit. Sheet dismisses to the timeline.
5. Tap the new food entry → `EventDetailSheet` opens: **Entry** = the sentence, **Detected** = the chips.
   Hold 3s on the chips. End frame.

**Capture:** iOS screen recording, then trim. Portrait 9:16 or 4:5 — LinkedIn crops 16:9 badly on mobile.
Silent + burned-in captions (most feed views are muted). Use a real logged meal, not a staged one.

## Stills

| #   | Shot                                         | Where                                    | Why it's in the post                                                                                                                                                    |
| --- | -------------------------------------------- | ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **Entry + Detected chips**                   | `EventDetailSheet`, tap any food event   | The decomposition claim, proven. Non-negotiable — this is the hero still if the video slips.                                                                            |
| 2   | **Barcode scanner live**                     | Log Food → "Scan a package barcode"      | Tangible. Shoot mid-scan with the code in frame, real product, hand visible (auto-capture, no shutter tap = the tremor-friendly design, though don't say why publicly). |
| 3   | **Resolved scan**                            | `LogEntrySheet` right after a hit        | Shows the product name auto-filled + the "Scanned - recording: …" note. Pick a product that resolves cleanly — verify before shooting.                                  |
| 4   | **Mic entry point**                          | `+` screen bottom, "Tap to log by voice" | Establishes there are three doors in.                                                                                                                                   |
| 5   | *(optional)* **Food events on the timeline** | Day in Review                            | Context: food sitting alongside tremor + meds. Only if the post runs as a carousel.                                                                                     |

## Explainer card (optional, carousel slide 2)

Only if you want the engineering beat to land visually. Brand per `docs/brand-guide.md` —
blue `#4A8CD6`, ink `#1A1D22`, Geist Medium, wave mark at `#4A8CD6` (**not** `#2F5D99`).

```
2,000,000 rows        USDA Branded Foods, raw
        ↓             dedupe (each product resubmitted ~4.3×)
  439,082 products    unique barcodes
        ↓             5 nutrients, 1 byte each + a known/unknown flags byte
     11.8 MB          sorted, binary-searched, bundled in the app
        ↓
   no network call
```

## Do not shoot

- Anything showing a **barcode miss** — the "not recognized" state is honest in the app but reads as
  broken in a feed, and OCR (the fix) is deferred.
- Any screen with **real tremor/health data** that identifies the person logging it.
- Real product packaging shot as an endorsement — keep brands incidental, not featured.

## Pre-flight

- [ ] Confirm the scanned product still resolves on the current build before filming shot 3.
- [ ] Check chips render in both light and dark mode; pick one and stay consistent across all stills.
- [ ] Numbers in the copy (2.0M → 439,082 → 11.8 MB) match `docs/design/barcode-capture.md`.
