import SwiftUI

/// The looping "how to do it" animation on the Tapping instructions screen: the phone flat on a
/// surface seen from above, a hand reaching in with the index finger extended, the fingertip
/// alternating between the top and bottom targets.
///
/// ⭐ **Drawn in SwiftUI, not rendered as a clip like `RotationDemoVideo` — and the reason the
/// Rotation demo had to become a video does not exist here.** That one failed as a vector because a
/// flat glyph has no back: showing a palm turn over means drawing two faces and swapping them,
/// which reads as a swivel rather than a turn. Nothing in tapping turns over. The phone lies still,
/// the hand stays face-on, and the only thing that moves is a fingertip travelling between two
/// boxes — all of which a vector draws honestly. Staying native keeps it themeable and reviewable,
/// with no asset to cut, no separate light and dark cuts, and no re-render to change a colour.
///
/// ⭐ **The targets are drawn at the protocol's proportions and with the capture screen's own
/// styling** — 1.5 tall-to-wide, a gap one third of a target's height, and the same fill/border/
/// flash values `TapCaptureView` uses. So the picture is a rehearsal of the real screen rather than
/// a decoration next to it, down to the flash the user will see under their own finger.
struct TapDemoIllustration: View {
    /// Everything is authored in this space and scaled to whatever the caller asks for — same
    /// convention as `RotationDemoIllustration`. ⚠️ Narrower than that one's 360x220 on purpose:
    /// Rotation draws an arm lying horizontally, which needs the width. Here the subject is an
    /// upright phone, and a 360-wide frame just left a third of the picture empty.
    private static let design = CGSize(width: 300, height: 220)

    var width: CGFloat = 260

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: CGFloat { width / Self.design.width }

    var body: some View {
        Group {
            if reduceMotion {
                // ⚠️ Holds a frame rather than hiding, matching `RotationDemoVideo`: the demo is
                // instructional, and the single most useful frame — finger resting on the top
                // target, both boxes visible — still shows what the test asks for.
                canvas(position: 0)
            } else {
                // ⚠️ `repeating: true` and a trigger-free track: the animation is ambient and owns
                // its own clock, so nothing on the instructions screen has to drive it.
                KeyframeAnimator(initialValue: 0.0, repeating: true) { position in
                    canvas(position: position)
                } keyframes: { _ in
                    // One second per round trip — two taps a second. ⚠️ Deliberately slower than a
                    // real trial, where the instruction is "as fast as you can". This has to be
                    // legible as an alternation, and at genuine tapping speed a 40pt fingertip
                    // just blurs into a vertical smear. The rest beats matter more than the
                    // travel: they are what makes it read as two distinct targets being hit.
                    KeyframeTrack {
                        LinearKeyframe(0, duration: 0.28)
                        CubicKeyframe(1, duration: 0.22)
                        LinearKeyframe(1, duration: 0.28)
                        CubicKeyframe(0, duration: 0.22)
                    }
                }
            }
        }
        .frame(width: width, height: Self.design.height * scale)
        .accessibilityHidden(true)
    }

    /// `position` is 0 at the top target, 1 at the bottom one.
    private func canvas(position: Double) -> some View {
        ZStack(alignment: .topLeading) {
            phone
            target(index: 0, flashing: contact(position) == 0)
            target(index: 1, flashing: contact(position) == 1)
            // ⭐ A pure translation, no wrist pivot. A real finger does pivot — but this is the
            // view from directly above the glass, which is the one angle where that pivot is
            // invisible and the fingertip simply travels. Faking a rotation here would tilt the
            // finger away from the surface it is supposed to be touching.
            hand.offset(y: Self.travel * position)
        }
        .frame(width: Self.design.width, height: Self.design.height, alignment: .topLeading)
        // ⚠️ **Load-bearing, not tidiness.** The hand is authored to run off the bottom-right
        // corner, and `.offset` does not clip — without this it paints over the "Tapping" title
        // sitting directly below the illustration. Cutting it at the frame is also the right read:
        // the Rotation clip's arm leaves its frame the same way, so the hand continues out of the
        // picture rather than ending in a rounded stump inside it.
        .clipped()
        .scaleEffect(scale)
        .frame(width: width, height: Self.design.height * scale)
    }

    /// Which target the fingertip is resting on, or nil while it is travelling.
    ///
    /// ⚠️ Derived from the animated position rather than from a second timed track — same reason
    /// `RotationDemoIllustration` derives its face swap from the angle. A parallel flash track has
    /// to be kept in sync with the movement by hand, and drifts the moment either is retimed.
    private func contact(_ position: Double) -> Int? {
        if position < 0.04 { return 0 }
        if position > 0.96 { return 1 }
        return nil
    }

    // MARK: - Pieces

    private var phone: some View {
        ZStack(alignment: .topLeading) {
            // ⚠️ Left of the frame's true centre. The hand occupies the right side, so a
            // geometrically centred phone sits optically right-of-centre; this puts the mass of
            // the picture back in the middle.
            box(80, 8, 112, 204, 17, MovementCheckStyle.phoneBody)
            box(87, 15, 98, 190, 11, MovementCheckStyle.phoneGlass)
        }
    }

    /// The same look `TapCaptureView.targetView` draws mid-trial: 0.18 fill, full-strength border,
    /// and on contact a 0.5 fill with a 0.96 scale over 0.12 s.
    private func target(index: Int, flashing: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(MovementCheckStyle.tint.opacity(flashing ? 0.5 : 0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(MovementCheckStyle.tint, lineWidth: 2.5)
            )
            .scaleEffect(flashing ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: flashing)
            .frame(width: Self.targetSize.width, height: Self.targetSize.height)
            .offset(x: Self.targetX, y: index == 0 ? Self.topTargetY : Self.bottomTargetY)
    }

    /// The index finger entering from the bottom-right corner, with the rest of the hand as a mass
    /// running off the frame behind it.
    ///
    /// ⭐ **Almost nothing but the finger, and that is the lesson from Rotation.** The first cut of
    /// this drew a whole fist face-on — palm, thumb, curled fingers — and it came out as a mitten
    /// with a stick attached, which is the same failure mode ("amateur robotics") that hand-rolled
    /// Rotation art kept hitting. Rotation needs its arm because the FOREARM is the instrument
    /// being measured. Here the finger is, so everything else is drawn as the minimum needed to
    /// stop the finger reading as a floating stick, and no more.
    ///
    /// ⚠️ Bottom-right at 38°, because that is the view you actually have of your own hand over a
    /// phone lying on a table. A finger arriving horizontally reads as resting on the glass; one
    /// arriving from the near corner reads as reaching in to press.
    private var hand: some View {
        ZStack(alignment: .topLeading) {
            // Knuckles, mostly off-frame — a wide round-capped stroke, so no shape has to be
            // drawn for the part the frame doesn't show.
            // ⚠️ Pushed far enough down that it leaves through the BOTTOM edge, not the right one.
            // A long vertical cut down the side of the hand reads as a cropped photograph; a hand
            // entering from the bottom edge, nearest the viewer, reads as a hand.
            limbStroke(from: CGPoint(x: 268, y: 236), to: CGPoint(x: 330, y: 310),
                       width: 112, color: MovementCheckStyle.limbShade)
            // The neighbouring finger, curled, just breaking the bottom edge. One is enough to
            // say "hand" — two started to look like a diagram of a hand.
            limbStroke(from: CGPoint(x: 208, y: 208), to: CGPoint(x: 250, y: 256),
                       width: 26, color: MovementCheckStyle.limbShade)
            // ⚠️ Drawn last, and its round cap's CENTRE is the contact point — that is what sits on
            // the target's centre, not the leading edge of the stroke. ⚠️ The base end is pushed
            // well past the frame so the clip cuts it: end it inside and the finger gets a visible
            // rounded stump sitting on top of the knuckles instead of disappearing into them.
            limbStroke(from: Self.fingertip, to: CGPoint(x: 296, y: 248),
                       width: 26, color: MovementCheckStyle.limb)
        }
    }

    /// A round-capped straight stroke — a capsule with both ends placed by hand. ⚠️ Deliberately
    /// not a `Capsule` shape: positioning one by frame-and-rotate means solving for its centre and
    /// its rotation anchor, and the whole point here is that the tip lands exactly on a target.
    private func limbStroke(from start: CGPoint, to end: CGPoint,
                            width: CGFloat, color: Color) -> some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    // MARK: - Geometry

    /// ⚠️ Proportions, not sizes: 72/48 is the protocol's 45x30 mm target and the 24 gap is its
    /// 15 mm — a third of a target's height. The capture screen draws these at true physical size;
    /// this only has to be recognisably the same shape, so it keeps the ratios and drops the
    /// millimetres.
    private static let targetSize = CGSize(width: 48, height: 72)
    private static let targetX: CGFloat = 112
    private static let topTargetY: CGFloat = 26
    private static let bottomTargetY: CGFloat = 122
    private static let travel = bottomTargetY - topTargetY
    /// Dead centre of the top target — the hand is authored resting here and translated down.
    private static let fingertip = CGPoint(x: targetX + targetSize.width / 2,
                                           y: topTargetY + targetSize.height / 2)

    /// SVG-style placement: x/y are the top-left corner in the 360x220 design space.
    private func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     _ radius: CGFloat, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(color)
            .frame(width: w, height: h)
            .offset(x: x, y: y)
    }
}

#Preview {
    TapDemoIllustration()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
}
