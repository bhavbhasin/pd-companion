import Foundation

// MARK: - Kampa sleep score
//
// A faithful reimplementation of Apple Health's Sleep Score, so a user reading our FAQ and
// comparing our number to Apple's finds them agreeing (not "close-ish"). Apple hasn't published
// exact code, but the methodology is documented well enough to reproduce; where a figure is
// undisclosed we say so below. Components + weights are Apple's: Duration 50, Bedtime 30,
// Interruptions 20. We show the number and the three components as raw facts — NO verbal grade
// ("Low"/"High"), per the app's facts-over-verdict stance.
//
// Sources: the5krunner "How Apple Watch's Sleep Score Is Calculated" (2025-10-06); Apple Support.
//
// The ONE irreducibly-estimated piece is the deep/REM "low stage" thresholds (the 5 + 5 inside
// Duration): Apple doesn't disclose them, and its own stage detection is ~63% accurate. Those
// two constants (`deepTargetFraction`, `remTargetFraction`) are our defensible estimate; every
// other number below traces to Apple's published behavior.

struct SleepScore: Equatable {
    let total: Int                 // 0–100
    let duration: Component        // /50
    let bedtime: Component?        // /30 — nil until a personal-bedtime baseline exists
    let interruptions: Component   // /20

    struct Component: Equatable {
        let points: Int
        let max: Int
        let fact: String           // the raw value shown beside the sub-score
    }

    // MARK: Duration (50)

    /// No deduction at/above 7 h 50 m (Apple's baseline). Below it, points come off on a curve
    /// `deduction = a·S + b·S²` (S = minutes short) EMPIRICALLY FIT to Apple's actual duration
    /// sub-score across 7 measured nights spanning 3 h 24 m – 8 h 25 m. The fit reproduces Apple's
    /// number exactly on 6 of those 7 nights (the 7th, an otherwise-full night, differs by ~2 —
    /// Apple's undisclosed deep/REM "stage quality" penalty). Rather than model deep/REM
    /// separately (Apple's thresholds are secret and its staging is ~63% accurate), the curve
    /// FOLDS the typical stage effect in, which is why it tracks Apple's total so closely.
    static let durationBaselineMinutes = 470.0
    static let durationMax = 50
    static let durationDeductLinear = 0.1130      // a: points per minute short
    static let durationDeductQuad = 0.000071      // b: points per minute² short

    // MARK: Bedtime (30) — vs the average of the last 13 nights

    static let bedtimeMax = 30
    /// Deviation later than usual is free up to ~15 min, then a linear deduction reaching the
    /// full 30 at 150 min late. Slope fits Apple's anchors (60 min → −10, 150 min → −30).
    static let bedtimeFreeMinutesLate = 15.0
    static let bedtimeFullDeductMinutesLate = 150.0
    /// Earlier than usual is free to 60 min, then a gentle −1 per 30 min, capped at −6.
    static let bedtimeFreeMinutesEarly = 60.0
    static let bedtimeEarlyMinutesPerPoint = 30.0
    static let bedtimeEarlyMaxDeduct = 6.0
    /// Apple uses the trailing 13 nights; below that there's no honest baseline → bedtime omitted.
    static let baselineNights = 13

    // MARK: Interruptions (20)

    static let interruptionsMax = 20
    static let awakeFreeMinutes = 11.0            // first 11 min awake unpenalized
    static let awakeMinutesPerPoint = 4.0         // then −1 per 4 min
    static let wakeEventsFree = 2                 // 2 wake events free
    static let wakeEventsPerPoint = 2.0           // then −1 per 2 further events

    // MARK: Scoring

    /// Score one night. `baselineBedtimeMinutes` is the usual bedtime (minutes since 6 PM, the
    /// sleep-day boundary) averaged over the trailing 13 nights, or nil during cold-start. When
    /// bedtime is unavailable the total renormalizes over the two components we DO have (out of
    /// 70 → rescaled to 100) so the number stays on a 0–100 scale and comparable across nights.
    static func score(_ night: NightSleep, baselineBedtimeMinutes: Double?) -> SleepScore {
        let duration = durationComponent(night)
        let interruptions = interruptionsComponent(awakeMinutes: night.awakeMinutes,
                                                    wakeUps: night.wakeUps)
        let bedtime = bedtimeComponent(night.bedtime, baselineMinutes: baselineBedtimeMinutes)

        let earned: Int
        let possible: Int
        if let bedtime {
            earned = duration.points + bedtime.points + interruptions.points
            possible = 50 + bedtimeMax + interruptionsMax
        } else {
            earned = duration.points + interruptions.points
            possible = 50 + interruptionsMax
        }
        let total = Int((Double(earned) / Double(possible) * 100).rounded())
        return SleepScore(total: total, duration: duration,
                          bedtime: bedtime, interruptions: interruptions)
    }

    private static func durationComponent(_ night: NightSleep) -> Component {
        let asleepMin = night.asleepHours * 60
        let short = max(0, durationBaselineMinutes - asleepMin)
        let deduction = durationDeductLinear * short + durationDeductQuad * short * short
        let pts = Int(max(0, min(Double(durationMax), Double(durationMax) - deduction)).rounded())
        return Component(points: pts, max: durationMax, fact: hoursMinutes(night.asleepHours))
    }

    private static func interruptionsComponent(awakeMinutes: Double, wakeUps: Int) -> Component {
        let timeDeduct = max(0, (awakeMinutes - awakeFreeMinutes) / awakeMinutesPerPoint)
        let eventDeduct = max(0, Double(wakeUps - wakeEventsFree) / wakeEventsPerPoint)
        let pts = Int(max(0, Double(interruptionsMax) - timeDeduct - eventDeduct).rounded())
        let awakeM = Int(awakeMinutes.rounded())
        let fact = wakeUps == 0
            ? "No interruptions"
            : "\(wakeUps) wake-up\(wakeUps == 1 ? "" : "s"), \(awakeM)m awake"
        return Component(points: pts, max: interruptionsMax, fact: fact)
    }

    private static func bedtimeComponent(_ bedtime: Date?, baselineMinutes: Double?) -> Component? {
        guard let bedtime, let baseline = baselineMinutes else { return nil }
        let mins = minutesSince6PM(bedtime)
        let dev = mins - baseline    // + = later than usual, − = earlier
        let deduction: Double
        if dev >= 0 {
            deduction = min(Double(bedtimeMax), max(0, Double(bedtimeMax)
                * (dev - bedtimeFreeMinutesLate)
                / (bedtimeFullDeductMinutesLate - bedtimeFreeMinutesLate)))
        } else {
            deduction = min(bedtimeEarlyMaxDeduct,
                            max(0, (-dev - bedtimeFreeMinutesEarly) / bedtimeEarlyMinutesPerPoint))
        }
        let pts = Int((Double(bedtimeMax) - deduction).rounded())
        let devMin = abs(dev)
        let fact: String
        if devMin < 15 {
            fact = "About your usual bedtime"
        } else {
            let dir = dev > 0 ? "later" : "earlier"
            fact = "\(hoursMinutes(devMin / 60)) \(dir) than usual"
        }
        return Component(points: pts, max: bedtimeMax, fact: fact)
    }

    // MARK: Baseline

    /// Score a whole history causally: each night against the trailing-13 baseline of the nights
    /// BEFORE it. The one place nights are turned into scores — the glance tile, the detail card
    /// and the trend line all read this table, so a night has exactly one score in the app.
    ///
    /// Carries the prior bedtimes forward in one pass. Calling `baselineBedtimeMinutes(nights[..<i])`
    /// per night re-converted the whole prefix just to keep its last 13 — quadratic, and measured at
    /// ~1s over 2,188 nights because every conversion runs `Calendar.dateComponents`.
    static func scoreHistory(_ nights: [NightSleep]) -> [(date: Date, score: SleepScore)] {
        var priorBedtimes: [Double] = []      // minutes since 6 PM, ascending, nights BEFORE this one
        return nights.map { night in
            let baseline: Double? = priorBedtimes.count >= baselineNights
                ? priorBedtimes.suffix(baselineNights).reduce(0, +) / Double(baselineNights)
                : nil
            let s = score(night, baselineBedtimeMinutes: baseline)
            if let b = night.bedtime { priorBedtimes.append(minutesSince6PM(b)) }
            return (night.date, s)
        }
    }

    /// The usual bedtime as minutes since 6 PM, averaged over the trailing `baselineNights` nights
    /// that have one (Apple uses the last 13). Measuring from 6 PM (the sleep-day boundary) keeps
    /// typical late-evening bedtimes off the midnight wrap, so this is a plain mean with no
    /// circular-stats machinery. nil until there are enough nights to be honest about "usual".
    ///
    /// Pass only the nights BEFORE the one being scored. A night included in its own baseline
    /// drags "usual" toward itself and under-reports its own deviation — a 1:38 AM bedtime pulled
    /// the baseline 20 min later and bought back 4 bedtime points.
    static func baselineBedtimeMinutes<C: Collection>(_ nights: C) -> Double? where C.Element == NightSleep {
        let mins = nights.compactMap { $0.bedtime.map(minutesSince6PM) }.suffix(baselineNights)
        guard mins.count >= baselineNights else { return nil }
        return mins.reduce(0, +) / Double(mins.count)
    }

    /// Minutes from 6 PM to the given instant's clock time, wrapped into [0, 1440). A 10:30 PM
    /// bedtime → 270; a 1 AM bedtime → 420.
    static func minutesSince6PM(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutesOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return Double((minutesOfDay - 18 * 60 + 1440) % 1440)
    }

    private static func hoursMinutes(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
