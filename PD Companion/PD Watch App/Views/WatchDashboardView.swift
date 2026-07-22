import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject var movementManager: MovementDisorderManager

    var body: some View {
        // NavigationStack so the .toolbar top-bar item actually renders — this puts
        // the brand inline with the system clock (top-right) and frees the content
        // space the in-content header was eating.
        NavigationStack {
            ScrollView {
                VStack(spacing: 6) {
                    if !movementManager.isAvailable {
                        unavailableView
                    } else if movementManager.isMotionDenied {
                        motionDeniedView
                    } else if movementManager.recentTremorSamples.isEmpty {
                        monitoringActiveView
                    } else {
                        latestReadingView
                        TremorSparkline(values: todayHourlyTremor, maxValue: 4)
                            .frame(height: 28)
                        captionView
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .toolbar {
                // Nudge up so the lockup sits level with the system clock on the right.
            ToolbarItem(placement: .topBarLeading) { KampaLockup().offset(y: -3) }
            }
        }
    }

    // MARK: - States

    private var unavailableView: some View {
        Text("Movement tracking unavailable on this device")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
    }

    // Motion & Fitness is off — the real reason tremor stays empty. Tell the user how to
    // fix it instead of showing a false "Monitoring active".
    private var motionDeniedView: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
            Text("Motion access needed")
                .font(.headline)
            Text("Enable Settings → Privacy & Security → Motion & Fitness, and allow Kampa. Tremor tracking can't run without it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var monitoringActiveView: some View {
        VStack(spacing: 6) {
            Text("Monitoring active")
                .font(.headline)
            Text("Tremor data will appear as it becomes available")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            statusFooter
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // Discreet real-state line so an empty screen is diagnosable from a screenshot: when we
    // last checked, how many samples came back, and any surfaced error — instead of a bare
    // reassurance that hides every failure mode behind one message.
    private var statusFooter: some View {
        VStack(spacing: 2) {
            Text(lastCheckedText)
            if let error = movementManager.error {
                Text(error)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.top, 10)
    }

    private var lastCheckedText: String {
        guard let date = movementManager.lastQueryDate else { return "Waiting for first check…" }
        let f = DateFormatter()
        f.timeStyle = .short
        return "Last checked \(f.string(from: date)) · 0 readings"
    }

    private var latestReadingView: some View {
        let latest = movementManager.recentTremorSamples.last
        let score = latest?.tremorScore ?? 0
        return VStack(spacing: 1) {
            Text("Latest Tremor")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f", score))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(colorForScore(score))
            Text(labelForScore(score))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var captionView: some View {
        VStack(spacing: 1) {
            Text("Today's average")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Tremor \(String(format: "%.1f", todayAverages.tremor))  ·  Dys \(String(format: "%.1f", todayAverages.dyskinesia))")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Derived data

    /// Hourly-averaged tremor for today (00:00 → now), for a clean sparkline.
    private var todayHourlyTremor: [Double] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let todaySamples = movementManager.recentTremorSamples.filter { $0.timestamp >= startOfDay }
        guard !todaySamples.isEmpty else { return [] }
        var buckets: [Int: (sum: Double, count: Int)] = [:]
        for s in todaySamples {
            let hour = cal.component(.hour, from: s.timestamp)
            let cur = buckets[hour] ?? (0, 0)
            buckets[hour] = (cur.sum + s.tremorScore, cur.count + 1)
        }
        let currentHour = cal.component(.hour, from: Date())
        return (0...currentHour).map { hour in
            guard let b = buckets[hour], b.count > 0 else { return 0 }
            return b.sum / Double(b.count)
        }
    }

    private var todayAverages: (tremor: Double, dyskinesia: Double) {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todaySamples = movementManager.recentTremorSamples.filter { $0.timestamp >= startOfDay }
        guard !todaySamples.isEmpty else { return (0, 0) }
        let t = todaySamples.reduce(0.0) { $0 + $1.tremorScore } / Double(todaySamples.count)
        let d = todaySamples.reduce(0.0) { $0 + $1.dyskinesiaScore } / Double(todaySamples.count)
        return (t, d)
    }

    private func colorForScore(_ score: Double) -> Color {
        switch score {
        case 0..<1: return .green
        case 1..<2: return .yellow
        case 2..<3: return .orange
        default: return .red
        }
    }

    private func labelForScore(_ score: Double) -> String {
        switch score {
        case 0..<0.5: return "None"
        case 0.5..<1.5: return "Slight"
        case 1.5..<2.5: return "Mild"
        case 2.5..<3.5: return "Moderate"
        default: return "Strong"
        }
    }
}

// MARK: - Brand pieces

extension Color {
    /// The Kampa brand blue (#4A8CD6). Not the icon-gradient deep blue.
    static let kampaBlue = Color(red: 74 / 255, green: 140 / 255, blue: 214 / 255)
}

/// The kāmpa wordmark + wave mark, sized for the top bar.
struct KampaLockup: View {
    var body: some View {
        HStack(spacing: 3) {
            KampaWaveMark()
                .stroke(Color.kampaBlue, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .frame(width: 19, height: 11)
            // Geist isn't bundled on the Watch target; system font keeps the brand
            // legible at this size, with the macron ā carrying the brand blue.
            (Text("k") + Text("ā").foregroundColor(.kampaBlue) + Text("mpa"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

/// The "steady wave" mark, drawn from the brand path (240×144 viewBox).
struct KampaWaveMark: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 240, sy = rect.height / 144
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        path.move(to: p(8, 90))
        path.addCurve(to: p(56, 30), control1: p(28, 90), control2: p(30, 30))
        path.addCurve(to: p(104, 95), control1: p(78, 30), control2: p(80, 110))
        path.addCurve(to: p(150, 60), control1: p(124, 82), control2: p(126, 60))
        path.addCurve(to: p(192, 78), control1: p(168, 60), control2: p(172, 78))
        path.addLine(to: p(232, 78))
        return path
    }
}

/// A minimal tremor sparkline: brand-blue line + soft area fill, no axes/labels.
/// Lower on screen = lower tremor (None at the bottom).
struct TremorSparkline: View {
    let values: [Double]
    let maxValue: Double

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count >= 2 {
                    areaPath(pts, size: geo.size)
                        .fill(LinearGradient(
                            colors: [Color.kampaBlue.opacity(0.30), Color.kampaBlue.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                    linePath(pts)
                        .stroke(Color.kampaBlue,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            let clamped = min(max(v, 0), maxValue)
            let y = size.height - (CGFloat(clamped) / CGFloat(maxValue)) * size.height
            return CGPoint(x: CGFloat(i) * stepX, y: y)
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: pts[0])
        for pt in pts.dropFirst() { path.addLine(to: pt) }
        return path
    }

    private func areaPath(_ pts: [CGPoint], size: CGSize) -> Path {
        var path = linePath(pts)
        path.addLine(to: CGPoint(x: pts.last!.x, y: size.height))
        path.addLine(to: CGPoint(x: pts.first!.x, y: size.height))
        path.closeSubpath()
        return path
    }
}
