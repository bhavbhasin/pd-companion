import Foundation
import SwiftData

/// Raw, independent per-minute dyskinesia capture from CMDyskineticSymptomResult.
///
/// Deliberately a separate stream from `TremorReading` rather than a field merged onto it:
/// Apple emits tremor and dyskinesia as two independent one-minute series, and a minute can
/// have a dyskinesia bucket with no matching tremor bucket (tremor has a `percentUnknown`
/// abstain state, dyskinesia does not). Merging would silently drop those minutes — the
/// reduce-at-capture mistake this whole change exists to avoid, on a non-refetchable
/// (~7-day rolling) source.
///
/// Apple guarantees `percentUnlikely + percentLikely == 1.0`, so only `percentLikely` is
/// stored (the other is `1 - percentLikely`). This is the RAW signal; display-time
/// thresholding/noise-floor lives in a later display task, NOT here.
@Model
final class DyskinesiaReading {
    // Defaults required for CloudKit (NSPersistentCloudKitContainer).
    var startDate: Date = Date.distantPast
    var endDate: Date = Date.distantPast
    var percentLikely: Double = 0

    init(startDate: Date, endDate: Date, percentLikely: Double) {
        self.startDate = startDate
        self.endDate = endDate
        self.percentLikely = percentLikely
    }

    convenience init(from sample: DyskinesiaSample) {
        self.init(
            startDate: sample.startDate,
            endDate: sample.endDate,
            percentLikely: sample.percentLikely
        )
    }
}
