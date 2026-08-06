import SwiftUI

/// The looping "how to do it" animation on the Rotation instructions screen: an outstretched
/// arm, the phone clasped flat across the palm, the forearm pronating and supinating 180°.
///
/// ⭐ **Ported from a Claude Design comp, and the idea worth keeping is why four hand-rolled
/// attempts failed before it.** A flat glyph has no back — rotating one is a swivel, not a turn.
/// This draws TWO faces (palm up with the fingers curled over the far edge and the thumb over
/// the near one; turned over with knuckles and the phone's camera showing beneath) and swaps
/// them as the rotation crosses 90°. That swap is the whole trick.
///
/// ⛔ Drawn in SwiftUI rather than shipped as SVG assets or a WKWebView. The shapes are almost
/// all rounded rectangles, so a native port keeps it vector, themeable and reviewable, with no
/// asset-catalog round-trip and no web view in the app for a decorative loop.
struct RotationDemoIllustration: View {
    /// Everything is authored in this 360x220 space and scaled to whatever the caller asks for,
    /// so the coordinates below stay identical to the comp's SVG.
    private static let design = CGSize(width: 360, height: 220)

    var width: CGFloat = 300

    private var scale: CGFloat { width / Self.design.width }

    var body: some View {
        // ⚠️ `repeating: true` and a trigger-free keyframe track — the animation is ambient and
        // owns its own clock, so nothing on the instructions screen has to drive it.
        KeyframeAnimator(initialValue: 0.0, repeating: true) { angle in
            canvas(angle: angle)
        } keyframes: { _ in
            // The comp's timing, kept: a beat at rest, an overshoot past 180° as the wrist
            // reaches its limit, a settle, then the same coming back. Total 2.1 s.
            KeyframeTrack {
                LinearKeyframe(0, duration: 0.168)
                CubicKeyframe(186, duration: 0.714)
                CubicKeyframe(180, duration: 0.126)
                LinearKeyframe(180, duration: 0.168)
                CubicKeyframe(-6, duration: 0.714)
                CubicKeyframe(0, duration: 0.126)
                LinearKeyframe(0, duration: 0.084)
            }
        }
        .frame(width: width, height: Self.design.height * scale)
        .accessibilityHidden(true)
    }

    private func canvas(angle: Double) -> some View {
        // ⚠️ **The WHOLE arm rotates, upper arm included.** The comp held the upper arm still
        // and turned only the forearm, which is anatomically what pronation does — but on a flat
        // 2D drawing it leaves a visible seam at the elbow where a moving shape meets a static
        // one, and it reads as a mechanism rather than a limb. Rotating everything costs nothing
        // visually: the upper arm is a rectangle centred on the rotation axis, so it barely
        // changes shape — it just stops being a separate piece.
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 13, topTrailingRadius: 13)
                .fill(RotationStyle.limb)
                .frame(width: 75, height: 60)
                .offset(x: 0, y: 80)

            frontFace.opacity(showsFront(angle) ? 1 : 0)
            // Pre-flipped so its artwork lands right way up once the arm reaches 180°.
            backFace
                .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
                .opacity(showsFront(angle) ? 0 : 1)
        }
        .frame(width: Self.design.width, height: Self.design.height, alignment: .topLeading)
        // Anchored near the elbow rather than the centre: for an x-axis rotation the anchor's x
        // only shapes the perspective, and putting it there makes the hand swing further than
        // the upper arm — which is what a real arm does.
        .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0),
                          anchor: UnitPoint(x: 0.17, y: 0.5), perspective: 0.35)
        // ⛔ No tilt. The comp carried a -9° lean; he wants the arm dead horizontal, and it does
        // read cleaner — the lean made it look like the arm was drifting upward.
        .scaleEffect(scale)
        .frame(width: width, height: Self.design.height * scale)
    }

    /// ⚠️ Derived from the angle rather than from the clock. The comp switched faces on timed
    /// keyframes, which has to be kept in sync by hand with the rotation track; keying on which
    /// way the unit is actually facing can't drift.
    private func showsFront(_ angle: Double) -> Bool {
        cos(angle * .pi / 180) >= 0
    }

    // MARK: - The two faces

    private var frontFace: some View {
        ZStack(alignment: .topLeading) {
            limb
            // Phone, clasped landscape: the long axis square across the forearm.
            box(198, 36, 68, 148, 14, RotationStyle.phoneBody)
            box(205, 43, 54, 134, 8, RotationStyle.phoneGlass)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(RotationStyle.tint.opacity(0.45), lineWidth: 1.5)
                .frame(width: 54, height: 134)
                .offset(x: 205, y: 43)
            box(220, 48, 24, 5, 2.5, RotationStyle.phoneBody.opacity(0.5))
            box(257, 36, 9, 112, 4.5, RotationStyle.phoneEdge)

            fingers
            // The bend past the phone's far edge, in shadow.
            box(283, 75, 19, 19, 9.5, RotationStyle.limbShade)
            box(289, 95, 19, 19, 9.5, RotationStyle.limbShade)
            box(286, 115, 19, 19, 9.5, RotationStyle.limbShade)
            box(277, 135, 19, 19, 9.5, RotationStyle.limbShade)

            // ⚠️ Limb-coloured, NOT shaded, and its base is buried inside the palm. The comp's
            // thumb was a darker wedge starting at the palm's edge, which read as a bolted-on
            // part — "amateur robotics", and he was right. Same colour plus an overlapping base
            // makes it one continuous hand.
            thumbFront.fill(RotationStyle.limb)
        }
    }

    private var backFace: some View {
        ZStack(alignment: .topLeading) {
            // Phone is underneath now — drawn first so the hand covers it.
            box(198, 36, 68, 148, 14, RotationStyle.phoneBack)
            Circle().fill(RotationStyle.phoneGlass)
                .frame(width: 18, height: 18).offset(x: 207, y: 157)
            Circle().fill(RotationStyle.tint.opacity(0.5))
                .frame(width: 7, height: 7).offset(x: 212.5, y: 162.5)
            box(257, 36, 9, 112, 4.5, RotationStyle.phoneEdgeBack)

            limb
            // Knuckles read as the back of the hand.
            ForEach([85.0, 105, 125, 145], id: \.self) { y in
                Circle().fill(RotationStyle.limbShade.opacity(0.8))
                    .frame(width: 10, height: 10).offset(x: 239, y: y - 5)
            }
            fingers
            thumbBack.fill(RotationStyle.limb)
        }
    }

    /// Forearm and palm, shared by both faces.
    private var limb: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 56, y: 84))
                p.addLine(to: CGPoint(x: 120, y: 84))
                p.addCurve(to: CGPoint(x: 154, y: 98),
                           control1: CGPoint(x: 142, y: 84), control2: CGPoint(x: 154, y: 90))
                p.addLine(to: CGPoint(x: 154, y: 122))
                p.addCurve(to: CGPoint(x: 120, y: 136),
                           control1: CGPoint(x: 154, y: 130), control2: CGPoint(x: 142, y: 136))
                p.addLine(to: CGPoint(x: 56, y: 136))
                p.closeSubpath()
            }
            .fill(RotationStyle.limb)
            box(146, 72, 106, 76, 22, RotationStyle.limb)
        }
    }

    private var fingers: some View {
        ZStack(alignment: .topLeading) {
            box(244, 75, 58, 19, 9.5, RotationStyle.limb)
            box(244, 95, 64, 19, 9.5, RotationStyle.limb)
            box(244, 115, 61, 19, 9.5, RotationStyle.limb)
            box(244, 135, 52, 19, 9.5, RotationStyle.limb)
        }
    }

    private var thumbFront: Path {
        Path { p in
            p.move(to: CGPoint(x: 150, y: 116))
            p.addCurve(to: CGPoint(x: 210, y: 160),
                       control1: CGPoint(x: 156, y: 142), control2: CGPoint(x: 180, y: 156))
            p.addCurve(to: CGPoint(x: 244, y: 147),
                       control1: CGPoint(x: 230, y: 163), control2: CGPoint(x: 244, y: 157))
            p.addCurve(to: CGPoint(x: 218, y: 133),
                       control1: CGPoint(x: 244, y: 138), control2: CGPoint(x: 233, y: 134))
            p.addCurve(to: CGPoint(x: 164, y: 102),
                       control1: CGPoint(x: 196, y: 131), control2: CGPoint(x: 178, y: 121))
            p.closeSubpath()
        }
    }

    private var thumbBack: Path {
        Path { p in
            // The same thumb mirrored about the hand's centreline — the flip carries it to the
            // opposite edge, which is what a real hand does.
            p.move(to: CGPoint(x: 150, y: 104))
            p.addCurve(to: CGPoint(x: 210, y: 60),
                       control1: CGPoint(x: 156, y: 78), control2: CGPoint(x: 180, y: 64))
            p.addCurve(to: CGPoint(x: 244, y: 73),
                       control1: CGPoint(x: 230, y: 57), control2: CGPoint(x: 244, y: 63))
            p.addCurve(to: CGPoint(x: 218, y: 87),
                       control1: CGPoint(x: 244, y: 82), control2: CGPoint(x: 233, y: 86))
            p.addCurve(to: CGPoint(x: 164, y: 118),
                       control1: CGPoint(x: 196, y: 89), control2: CGPoint(x: 178, y: 99))
            p.closeSubpath()
        }
    }

    /// SVG-style placement: x/y are the top-left corner in the 360x220 design space.
    private func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     _ radius: CGFloat, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(color)
            .frame(width: w, height: h)
            .offset(x: x, y: y)
    }
}
