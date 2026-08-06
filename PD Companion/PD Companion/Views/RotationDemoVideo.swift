import AVFoundation
import SwiftUI

/// The looping "how to do it" demo on the Rotation instructions screen: an outstretched arm,
/// the phone clasped flat across the palm, the forearm pronating and supinating 180°.
///
/// ⭐ **A rendered clip, not the hand-drawn glyph** (`RotationDemoIllustration`, which stays in
/// the repo and is still the fallback below). The vector version had to fake the turn by swapping
/// a front face for a back face at 90°, because a flat glyph has no back. A real render just has
/// one — the phone's edge is genuinely visible mid-turn, so the movement reads as a turn rather
/// than a swivel. That is the whole reason for the swap.
///
/// ⭐ **Two cuts of the same clip, one per appearance, and that is the point.** The generated
/// footage has a true-black background (`rgb(1,1,1)`), so in dark mode it runs full-bleed with no
/// frame, card or corner radius — there is no visible video rectangle, the arm just floats on the
/// screen. On a light background that same black is a slab, and rounding it only turns it into a
/// *deliberate* slab. So the light cut has the background keyed out and re-composited over white.
///
/// ⚠️ The key is a luma ramp, not a chroma key, and it is only this clean because the source is
/// literally black behind the subject: 74.4% of pixels sit at luma ≤3, just 0.3% land in the 4-12
/// transition band, and the subject starts at 13. Measured on the finished cut the alpha comes out
/// 75.7% fully transparent / 0.46% partial — no halo. A re-generated clip must be re-measured
/// before this is trusted again.
///
/// ⛔ The light cut is baked against **white**, matching `systemBackground` on this sheet. Putting
/// this view on a grouped or tinted light surface would show its edges.
///
/// ⛔ Generated, then cleaned: the generator's watermark is masked out (it sat on pure black, so
/// it is painted over exactly rather than blurred) and the clip is trimmed to a whole number of
/// turns so it wraps without a visible seam. Re-cutting it from a fresh generation means redoing
/// both, for both appearances — see `docs/design/rotation-demo-video-prompt.md`.
struct RotationDemoVideo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Both cuts are 1280x630. Hard-coded rather than read off the track so the layout is settled
    /// on the first frame — measuring the asset would reflow the screen once it loads.
    private static let aspect: CGFloat = 1280.0 / 630.0

    /// ⚠️ Root lookup FIRST because that is where the files actually land: the synchronized group
    /// flattens `Resources/` away, so the built bundle holds them at the top level (verified in
    /// the built `.app` — the Food corpus flattens the same way). The subdirectory lookup is only
    /// a guard in case that flattening ever changes.
    private static func assetURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mp4")
            ?? Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "Resources")
    }

    /// Resolved once each — `Bundle.url(forResource:)` hits the filesystem, and this view
    /// re-evaluates on every appearance change.
    private static let darkURL = assetURL(named: "rotation-demo")
    private static let lightURL = assetURL(named: "rotation-demo-light")

    private var url: URL? { colorScheme == .dark ? Self.darkURL : Self.lightURL }

    var body: some View {
        Group {
            if let url {
                // ⚠️ Reduce Motion pauses rather than hides. The clip is instructional, not
                // decorative — a still of the phone clasped flat on the palm is the single most
                // useful frame, so someone with motion sensitivity still sees the grip.
                LoopingVideoLayer(url: url, isPlaying: !reduceMotion)
                    .aspectRatio(Self.aspect, contentMode: .fit)
            } else {
                // Bundle miss shouldn't happen, but a missing decoration must never cost the
                // instructions screen its picture.
                RotationDemoIllustration(width: 300)
            }
        }
        .accessibilityHidden(true)
    }
}

/// `AVPlayerLayer` behind a SwiftUI view. Deliberately not `VideoPlayer`, which brings transport
/// controls and a tap target with it — this is a picture, not a player.
private struct LoopingVideoLayer: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .clear
        context.coordinator.attach(url: url, to: view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        // ⚠️ The URL changes when the user flips between light and dark — the two appearances are
        // different cuts of the clip. Without this the player would keep the cut it launched with
        // and the background would be wrong until the screen was reopened.
        context.coordinator.attach(url: url, to: uiView.playerLayer)
        context.coordinator.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var player: AVQueuePlayer?
        // ⚠️ Must be held. `AVPlayerLooper` stops looping the moment it deallocates, and the
        // failure is silent — the clip plays through once and freezes on its last frame.
        private var looper: AVPlayerLooper?
        private var attachedURL: URL?

        func attach(url: URL, to layer: AVPlayerLayer) {
            // ⛔ Idempotent: `updateUIView` runs on every state change, and rebuilding the player
            // each time would restart the loop from frame 0 — a visible jump.
            guard url != attachedURL else { return }
            attachedURL = url
            looper?.disableLooping()
            let player = AVQueuePlayer()
            // ⛔ The asset carries no audio track and the player is muted anyway: a decorative
            // loop must never duck or interrupt whatever the user is listening to.
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            layer.player = player
            layer.videoGravity = .resizeAspect
            self.player = player
        }

        func setPlaying(_ playing: Bool) {
            if playing { player?.play() } else { player?.pause() }
        }

        func stop() {
            player?.pause()
            looper?.disableLooping()
        }
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
