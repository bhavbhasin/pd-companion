import SwiftUI

/// The looping "how to do it" demo on the Tapping instructions screen: an index finger alternating
/// between two stacked targets, the touched one deepening on contact.
///
/// Sibling of `RotationDemoVideo`, playing through the same `LoopingVideoLayer` so the two Movement
/// check screens loop identically.
///
/// ⛔ **Unlike Rotation, there is no vector fallback and that is deliberate.** `TapDemoIllustration`
/// (a SwiftUI-drawn index finger crossing two boxes) was built before the clip existed and deleted
/// once it shipped — two pieces of art for one picture only drift. Rotation keeps
/// `RotationDemoIllustration` because it solved a real problem the clip inherited (a flat glyph has
/// no back); nothing here needed solving twice. A bundle miss falls back to the plain category
/// glyph, which is what the screen showed before either existed.
///
/// ⭐ **The targets are composited, not generated.** The generator was asked for the two boxes and
/// could not hold them still; the shipped clip draws them in post, warped onto the screen plane
/// through a homography fitted to the phone's own edges. That is why they carry the protocol's real
/// proportions — `30x45 mm` with a `15 mm` gap, the same ratios `LogMovementCheckScreen` draws — and
/// why the touched box uses the app's actual `flashing` value (tint @ 0.5) against resting @ 0.18.
/// A re-generated clip has to redo that step; see `docs/design/tapping-demo-video-prompt.md`.
///
/// ⚠️ **Both cuts come from one generation.** The source render sits on pure white, so the light cut
/// is the native one and the dark cut replaces the background by flood-filling from the frame edges
/// — *not* a luma key, which cannot work here because the phone body (luma ~240) is barely separable
/// from the white ground (255). The fill works because the phone is enclosed, so its screen is never
/// reached. Re-measure on any new generation.
///
/// ⛔ Unlike Rotation, the light cut is the *unmodified* one and the dark cut is derived — the
/// opposite of that clip, because Gemini rendered this one on white rather than black.
struct TapDemoVideo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Both cuts are 1028x648. Hard-coded rather than read off the track so the layout is settled
    /// on the first frame — measuring the asset would reflow the screen once it loads.
    private static let aspect: CGFloat = 1028.0 / 648.0

    /// ⚠️ Root lookup FIRST because that is where the files actually land: the synchronized group
    /// flattens `Resources/` away, so the built bundle holds them at the top level. Same lookup
    /// order as `RotationDemoVideo` — see the note there.
    private static func assetURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mp4")
            ?? Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "Resources")
    }

    /// ⚠️ Named light/dark explicitly, unlike Rotation's bare `rotation-demo` for its dark cut.
    /// There the unmodified generation *was* the dark one; here it is the light one, so a bare
    /// name would mean the opposite thing on the neighbouring screen.
    private static let lightURL = assetURL(named: "tap-demo-light")
    private static let darkURL = assetURL(named: "tap-demo-dark")

    private var url: URL? { colorScheme == .dark ? Self.darkURL : Self.lightURL }

    var body: some View {
        Group {
            if let url {
                // ⚠️ Reduce Motion pauses rather than hides, matching Rotation. The clip is
                // instructional: a still showing two stacked targets with a finger on one of them
                // still carries the shape of the test, so motion sensitivity never costs the
                // picture.
                LoopingVideoLayer(url: url, isPlaying: !reduceMotion)
                    .aspectRatio(Self.aspect, contentMode: .fit)
            } else {
                // Bundle miss shouldn't happen, but a missing decoration must never cost the
                // instructions screen its picture. Same glyph Tapping wears on the timeline, the
                // legend and the `+` sheet, so a fallback still reads as this feature.
                Image(systemName: MovementCheckStyle.timelineSymbol)
                    .font(.system(size: 44))
                    .foregroundStyle(MovementCheckStyle.tint)
            }
        }
        .accessibilityHidden(true)
    }
}
