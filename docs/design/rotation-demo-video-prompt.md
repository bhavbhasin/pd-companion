# Rotation demo - video generation prompt

Source prompt for regenerating the Rotation instructions loop (`LogRotationScreen`, currently
`RotationDemoIllustration.swift`). Kampa palette baked in so no recolor is needed in post.

## Palette (from `RotationStyle`, `LogRotationScreen.swift:28-34`)

| Token | Hex |
|---|---|
| Background | `#000000` |
| Limb | `#0E6E78` |
| Limb shade | `#0A555E` |
| Phone body | `#E7F4F6` |
| Phone back | `#C6DDE2` |
| Phone glass | `#08343B` |
| Phone edge | `#B4CED4` |

## Prompt

> A single continuous locked-off shot, no cuts. Three-quarter side view of a seated human figure's
> right arm extended straight out in front at shoulder height, elbow soft, forearm and hand filling
> most of the frame with the shoulder and a sliver of torso at the right edge. A smartphone lies
> flat across the open palm, its long edge square to the forearm, fingers curled loosely over the
> far edge and the thumb resting across the near edge.
>
> The forearm pronates and supinates: the hand turns a full 180 degrees so the palm goes from face-up
> to face-down, pauses for a beat, then turns back. Repeat this continuously and briskly, about four
> complete turns across the clip, at the speed of someone performing a timed test. The upper arm and
> shoulder stay still and steady; only the forearm rotates. The phone stays clasped flat against the
> palm throughout and turns with it, so the screen faces the camera edge-on at the halfway point of
> each turn. Begin and end on the identical palm-down pose so the clip loops seamlessly.
>
> Style: matte, softly lit dimensional forms on a pure black seamless void. The arm, hand and figure
> are a single solid deep teal (#0E6E78) with slightly darker teal (#0A555E) in the shadowed planes -
> no skin texture, no wireframe or mesh lines, no polygon grid, no specular highlights, no reflections.
> The phone is pale ice white (#E7F4F6) with a dark teal (#08343B) screen and a soft edge highlight.
> One gentle key light from the upper left, no cast shadow, no floor, no wall, no room, no chair.
> Calm, clinical, minimal - a medical instruction diagram rendered in three dimensions.
>
> Camera is completely static: no pan, no zoom, no push-in, no orbit, no handheld drift.
>
> Absolutely no text, captions, subtitles, labels, arrows, checkmarks, icons, logos, watermarks,
> UI elements, title card or end card at any point.

## Shipped asset (Aug 6, 2026)

`PD Companion/PD Companion/Resources/rotation-demo.mp4` - 1280x630, 190 frames, 7.92 s, 394 KB,
H.264, no audio. Generated from the prompt above (2nd take), then cleaned:

```
ffmpeg -i SOURCE.mp4 \
  -vf "trim=start_frame=17:end_frame=207,setpts=PTS-STARTPTS,\
drawbox=x=1126:y=564:w=68:h=72:color=black:t=fill,crop=1280:630:0:90" \
  -an -c:v libx264 -profile:v high -crf 26 -pix_fmt yuv420p -movflags +faststart out.mp4
```

- **Watermark**: sat at x 1136-1182, y 574-622 on true black, and no teal pixel enters
  x 1126-1194 / y 564-636 on any of the 240 source frames - so it is painted black exactly,
  not blurred. ⚠️ Measure the box again on a new generation; a first guess put it 40 px off and
  clipped the torso rim instead.
- **Loop**: frames 17 and 207 differ by 0.73/255. The clip is 17-206, so the wrap is a normal
  one-frame step (measured 3.13 vs a median adjacent-frame step of 1.72, max 3.74).
- **Crop**: top 90 px is dead space. Bottom is kept so the torso exits frame instead of being
  sliced. Content sits at x 140-1276, arm y 140-600.

**Light mode** ships a second cut, `rotation-demo-light.mp4` (522 KB), with the black keyed out
and re-composited over white. Both run full-bleed; no card, inset or corner radius in either
appearance. ⛔ An inset rounded viewer was tried first and rejected - it makes the black slab
deliberate, not absent, which is not the same thing.

```
ffmpeg -f lavfi -i color=c=white:s=1280x630:r=24 -i rotation-demo.mp4 \
  -filter_complex "[1]format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':\
a='clip(((0.299*r(X,Y)+0.587*g(X,Y)+0.114*b(X,Y))-2)*255/12,0,255)'[fg];\
[0][fg]overlay=format=auto:shortest=1,format=yuv420p" \
  -an -c:v libx264 -profile:v high -crf 26 -movflags +faststart rotation-demo-light.mp4
```

- Luma ramp, not a chroma key, and it only works because the source is literally black behind the
  subject: 74.4% of pixels at luma ≤3, 0.3% in the 4-12 band, subject from 13. Resulting alpha is
  75.7% transparent / 0.46% partial - no halo. ⚠️ Re-measure on any new generation.
- ⛔ `lumakey` was the obvious filter and is wrong here: its softness smeared the background to
  28% fully-transparent instead of 74%. The explicit `geq` ramp is what gives clean edges.
- ⛔ Baked against **white** = `systemBackground` on this sheet. A grouped or tinted light surface
  would show the clip's edges.

Grip note: this take holds the phone clasped at the fingers, matching the shipped copy and the
`LogRotationScreen` comment ("Roche's protocol says hold"). A later take with the phone resting on
a flat open palm was rejected for contradicting that.

## Notes

- Video models render hands badly; expect several attempts. Judge on: does the phone stay flat on
  the palm through the whole turn, and is it a full 180deg (screen edge-on at the midpoint)?
- The generator's own watermark is unavoidable at generation time. It sits fixed bottom-right, so
  `delogo` or a bottom crop removes it in post.
- Alternative framing if the arm-only shot reads too abstract: full seated side profile, chair
  implied not drawn. Costs hand size - the movement gets small at 300pt wide.
