# Tapping demo - video generation prompt

## ✅ SHIPPED Aug 8 2026 - and NOT from a video model

`tap-demo-light.mp4` / `tap-demo-dark.mp4` (1028x648, 24fps, 4.0s, ~120 KB each), played by
`TapDemoVideo`. **Neither Gemini's image model nor Omni ever produced a usable clip** - Omni
returned the 530-word prompt silently to the text box twice. What shipped was built from a single
**static** Gemini image, animated programmatically:

1. **Watermark** - the sparkle was 48x48 at x[1264-1311] y[624-671]; removed by solving Laplace over
   the patch with the surrounding ring as boundary, so it reproduces the arm's gradient. 0 residual.
2. **Plate** - hand removed, hidden geometry rebuilt. Screen shading = robust quadratic fit on
   visible interior (rms 0.6) extrapolated underneath. ⛔ Body edge needs **per-edge** inward
   profiles: upper edges are bright (~230), lower edges shaded dark (~161). Using one profile for
   all four left a visible step where the reconstruction met the original.
3. **Targets** - drawn in the phone's plane at protocol geometry and warped through a homography
   fitted to the phone's own edges (all four edges rms < 0.8 px). Corners TOP(635,153)
   RIGHT(1031,473) BOTTOM(769,617) LEFT(398,283); opposite-edge ratios 1.02/1.10 (near-affine).
   ⭐ Protocol forces block height = 3.5x box width ⇒ box width ≤ 0.456 of screen width; at 0.45 the
   fingertip falls inside the top box, at 0.40 it sits on the edge.
4. **Hand sprite** - unmixed against the plate (`F = (obs-(1-α)·plate)/α`), padded 80 px by edge
   replication. ⛔ The hand may only travel **down-right** from its source pose; up-left drags its
   frame-edge cut into view. Travel = (187.8, 156.8) px = one box-pitch through the homography.
5. **Loop** - wrap 2.708 mean abs diff vs median adjacent step 4.796. Frame-exact at source.

⚠️ **Known, inherited from the source image, not fixable in post**: the whole hand translates
rigidly (a real tap pivots at the finger), and the thumb also contacts the lower box. Only a clean
re-generation fixes either.

⚠️ Light is the **native** cut here and dark is derived - the opposite of Rotation, because this
render came back on white. Dark is a border flood-fill, ⛔ **not** a luma key: the phone body (~240)
is not separable from white (255). It works only because the phone is enclosed.

The stills `tap-demo-light.png` / `tap-demo-dark.png` live in this folder, ⛔ not in `Resources/` -
nothing in the app references them and they would ship as dead weight.

---


Source prompt for the Tapping instructions loop (`LogMovementCheckScreen`, currently
`TapDemoIllustration.swift`). Sibling of `rotation-demo-video-prompt.md` - same shot grammar, same
void, same post-production, so the two Movement check screens read as one family. Kampa palette
baked in so no recolor is needed in post.

## Palette (from `MovementCheckStyle`, `LogMovementCheckScreen.swift`)

| Token | Hex |
|---|---|
| Background | `#000000` |
| Limb | `#423F8C` |
| Limb shade | `#32306F` |
| Phone body | `#E7E7F4` |
| Phone screen | `#F9F9FD` |
| Target (tint) | `#5856D6` |

## ⛔ Use the VIDEO model, not the image model

A `Gemini_Generated_Image_*.png` came back from a first attempt. That is Nano Banana, Gemini's
**image** model - it cannot produce motion no matter how the prompt is worded.

The video model in the Gemini app is **Gemini Omni** (Omni Flash, launched at I/O on 19 May 2026).
⛔ Not Veo - Omni replaced it in the app. Everything below assumes Omni.

**⭐ Omni accepts an image as input and reasons across it.** Prefer that path here: render the two
targets as a still PNG at the exact protocol geometry (below), feed it as the conditioning image,
and let the prompt animate the hand over it. The boxes then inherit measured geometry instead of the
model's approximation of "1 : 1.5". ⚠️ This fixes frame 1, not frame 200 - still judge drift.

## Palette maths for the two targets

Derived from `targetView` in `LogMovementCheckScreen.swift`, composited over the `#F9F9FD` screen so
the prompt can name flat hexes (a video model cannot be told "indigo at 18% opacity"):

| State | Source | Flat hex |
|---|---|---|
| Resting box fill | `tint` @ 0.18 | `#DCDCF6` |
| Pressed box fill | `tint` @ 0.50 | `#A9A8EA` |
| Border, both states | `tint` @ 1.0, 2 pt | `#5856D6` |

Geometry by protocol: each box `30x45 mm` (so 1 : 1.5), stacked vertically with a `15 mm` gap - the
gap is one third of a box's height. Corner radius is roughly a sixth of the box width.

## Prompt

⚠️ **Keep this at ~315 words.** A 530-word draft returned silently to the text box with no output;
the Rotation prompt that works is 313. Length is the first thing to cut when a take won't generate.

> A single continuous locked-off animated shot, no cuts. High three-quarter view looking down at a
> smartphone lying flat and level, screen up, filling the middle of frame. A right hand reaches in
> from the lower right, index finger extended, the other fingers curled into a loose fist; the wrist
> and forearm exit the bottom right corner.
>
> On the screen are exactly two shapes: two identical vertical rounded rectangles, stacked one above
> the other, centred. Each is one and a half times taller than it is wide, and the gap between them
> is one third of a box's height. Each has a 2-pixel indigo (#5856D6) outline and a pale lavender
> (#DCDCF6) fill. The boxes stay locked in the same place, at the same size, for the whole clip.
>
> The index finger taps the centre of the top box, lifts clear, taps the centre of the bottom box,
> lifts clear, and repeats briskly - about five complete cycles. Each tap is a distinct press and
> release, never a slide or a hover. As the fingertip touches a box, that box deepens to a stronger
> indigo (#A9A8EA) and shrinks slightly, then returns to pale the instant the finger lifts. Only the
> box under the finger changes.
>
> The phone never moves. Begin and end on the identical pose, fingertip on the top box, so the clip
> loops seamlessly.
>
> Style: matte, softly lit dimensional forms on a pure black (#000000) seamless void. The hand, wrist
> and forearm are solid deep indigo (#423F8C) with darker indigo (#32306F) in the shadowed planes -
> no skin texture, no fingernails, no wireframe or mesh lines, no specular highlights. The phone is
> pale ice white (#E7E7F4) with a near-white (#F9F9FD) screen. One gentle key light from the upper
> left, no cast shadow, no table, no floor, no room. Calm, clinical, minimal.
>
> Camera completely static: no pan, zoom, push-in or orbit.
>
> No text, labels, arrows, icons, status bar, logos, watermarks, app interface or end card at any
> point.

## Light and dark come from ONE generation, not two

Same as Rotation: generate once against the black void, then key the black out for the light cut.
Do **not** generate a light-background variant - two takes would not match.

This is why the prompt insists the background is literally `#000000` and that nothing else in frame
is near-black. The key is a luma ramp with the subject starting at luma 13, and the palette clears
it: limb `#423F8C` = 73, limb shade `#32306F` = 56, and both box fills are near-white. ⚠️ Re-measure
the histogram on every new generation anyway.

## Fallback: composite the targets in post

⚠️ The prompt above asks the model for the two boxes. The likely failure is drift - boxes that
wobble, resize, or gain invented UI across 200 frames. Judge that first (see Notes). If a take is
good everywhere except the boxes, re-run asking for a **blank pale white screen, completely empty,
no interface of any kind**, and overlay the targets instead:

- The phone is static and the camera is locked off, so the screen is a fixed quadrilateral for the
  whole clip. Two rounded rectangles perspective-warped onto it **once** and overlaid gives targets
  that are pixel-exact, on-brand, and identical to what the user is about to see.
- It also keeps the artwork honest: `30x45 mm` with a `15 mm` gap, the same ratios the screen draws.
  Baked into a render, they can never be corrected without a re-generation.

Build a transparent PNG of the two targets, warp it to the screen corners measured off frame 1,
overlay it for the whole clip:

```
ffmpeg -i CLEAN.mp4 -i targets.png \
  -filter_complex "[1]perspective=x0=..:y0=..:x1=..:y1=..:x2=..:y2=..:x3=..:y3=..:sense=destination[t];\
[0][t]overlay=0:0:format=auto" \
  -an -c:v libx264 -profile:v high -crf 26 -pix_fmt yuv420p -movflags +faststart out.mp4
```

⚠️ Measure the screen's four corners off an actual frame. Guessing them is what puts the targets
subtly off-plane, which reads as a sticker floating above the glass.

## Post-production (identical to Rotation - see that doc for the measured detail)

1. **Watermark**: fixed bottom-right. Paint it black exactly rather than blurring, and **re-measure
   the box on every new generation** - a guess was 40 px off last time and clipped the subject.
2. **Loop**: trim to a whole number of tap cycles and verify the wrap frame differs from the start
   frame by no more than a normal adjacent-frame step.
3. **Crop** to 1280x630 so it drops into the same layout slot as the Rotation clip.
4. **Light cut**: a second file with the black keyed out over white, using the explicit `geq` luma
   ramp - ⛔ not `lumakey`, which smears the edge. Re-measure the luma histogram; the ramp is only
   clean because the source is literally black behind the subject.
5. Both cuts run full-bleed. ⛔ No card, inset or corner radius - that was tried on Rotation and
   rejected, because framing the black slab makes it deliberate rather than absent.

## Notes

- Judge a take on, in this order: (1) do the two boxes stay **pixel-still and identical** for the
  whole clip - scrub frame by frame, drift and resize are the expected failure; (2) does the
  highlight land on the box **under the fingertip**, on contact, and clear on lift - a highlight that
  leads or lags the finger reads as broken; (3) does the fingertip actually **contact** the glass and
  lift clear (not hover, not slide); (4) does the phone stay perfectly still. Fail (1) and take the
  composite fallback rather than burning generations.
- Hands are what video models are worst at, and this clip is almost entirely hand at close range.
  Expect more attempts than Rotation needed. A curled fist with one finger out is the specific
  failure risk: watch for the other fingers sprouting or the finger count drifting between cycles.
- The tap rhythm in the clip is deliberately slower than a real trial ("as fast as you can"). At
  genuine tapping speed the finger blurs and the alternation stops being legible.
- `TapDemoIllustration.swift` stays in the repo as the fallback for a bundle miss, exactly as
  `RotationDemoIllustration` does for the Rotation clip.
