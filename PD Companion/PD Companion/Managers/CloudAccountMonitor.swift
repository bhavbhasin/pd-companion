import CloudKit
import Combine
import Foundation

/// Reports whether this device has a working iCloud account, which is the difference
/// between "the record survives a lost phone" and "it doesn't".
///
/// CloudKit is the ONLY restore path (CSV import was retired Jul 31 2026), and SwiftData's
/// `cloudKitDatabase: .automatic` gives us no hook to observe sync at all — it either works
/// or it quietly doesn't. `accountStatus()` is the one signal Apple does expose, so it is
/// what both the Settings footer and the backup banner are built on.
///
/// ⚠️ What this CANNOT see: a signed-in account whose storage is FULL. `CKAccountStatus`
/// has no case for it — a user at their quota reports `.available` while sync has silently
/// stopped. Detecting that needs a probe write to the private database catching
/// `CKError.quotaExceeded`; filed in BACKLOG, deliberately not built here.
@MainActor
final class CloudAccountMonitor: ObservableObject {
    static let shared = CloudAccountMonitor()

    /// `nil` until the first check completes. Distinct from `.couldNotDetermine`: nil means
    /// "not asked yet", so no surface claims anything before we have an answer.
    @Published private(set) var status: CKAccountStatus?

    private var accountChangeObserver: NSObjectProtocol?

    private init() {
        // Re-check when the user signs in or out of iCloud while the app is installed.
        // Without this the banner would persist until relaunch after the user fixes it —
        // the worst moment to look wrong, since they just did what we asked.
        accountChangeObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        #if DEBUG
        // Test the not-backed-up surfaces WITHOUT signing out of iCloud — signing out on a device
        // holding the real record is not a safe way to check a banner. Set in the Xcode scheme:
        // Product → Scheme → Edit Scheme → Run → Arguments → Arguments Passed On Launch:
        //
        //   -KampaDebugCloudStatus 3   → no account   (banner + "Not backing up" footer)
        //   -KampaDebugCloudStatus 2   → restricted   (banner + "unavailable on this device")
        //   -KampaDebugCloudStatus 4   → temporarily unavailable (footer only, NO banner —
        //                                 this is the case we deliberately stay quiet about)
        //   -KampaDebugCloudStatus 1   → available    (normal state, for comparison)
        //   -KampaDebugResetBannerDismissal YES  → clears a previous dismissal on launch
        //
        // Remove the argument (or uncheck it) and the real account status returns.
        // ⛔ Compiled out of Release — this cannot reach a TestFlight or App Store build.
        if UserDefaults.standard.bool(forKey: "KampaDebugResetBannerDismissal") {
            UserDefaults.standard.removeObject(forKey: "icloud.backupBannerDismissedStatus")
        }
        if UserDefaults.standard.object(forKey: "KampaDebugCloudStatus") != nil {
            let raw = UserDefaults.standard.integer(forKey: "KampaDebugCloudStatus")
            status = CKAccountStatus(rawValue: raw) ?? .couldNotDetermine
            return
        }
        #endif
        do {
            status = try await CKContainer.default().accountStatus()
        } catch {
            status = .couldNotDetermine
        }
    }

    /// Stable identifier for the current state, for views that need to remember WHICH state
    /// they acted on (the banner's dismissal) without importing CloudKit to do it. -1 = not
    /// yet checked, and deliberately never equal to a real status.
    var statusToken: Int { status?.rawValue ?? -1 }

    /// True only for a definite, user-fixable failure. `.temporarilyUnavailable` and
    /// `.couldNotDetermine` are transient or unknown — telling someone their data isn't
    /// backed up on the strength of a failed lookup would be a false alarm, and this
    /// warning only works if it is never wrong.
    var isDefinitelyNotBackingUp: Bool {
        status == .noAccount || status == .restricted
    }

    /// One line for the support email, mirroring the Health-access line beside it.
    var diagnosticDescription: String {
        switch status {
        case .available:              return "available"
        case .noAccount:              return "no account"
        case .restricted:             return "restricted"
        case .temporarilyUnavailable: return "temporarily unavailable"
        case .couldNotDetermine:      return "could not determine"
        case .none:                   return "not checked"
        @unknown default:             return "unknown"
        }
    }

    /// The Settings → Your data footer. Says what is true right now rather than asserting
    /// backup as a fact, and carries the full Settings path because the banner cannot —
    /// there is no supported deep link to the iCloud pane (`openSettingsURLString` opens
    /// Kampa's own page, which has no iCloud toggle).
    var settingsFooterText: String {
        switch status {
        case .available:
            return "Backed up automatically to your private iCloud."
        case .noAccount:
            return "Not backing up — losing this iPhone would lose your record. "
                 + "Turn on iCloud: Settings → your name → iCloud → Saved to iCloud → See All → Kampa."
        case .restricted:
            return "iCloud is unavailable on this device, so your Kampa data is not backed up."
        case .temporarilyUnavailable, .couldNotDetermine:
            return "Can't reach iCloud right now. Your data is safe on this iPhone; backup resumes on its own."
        case .none:
            return "Checking iCloud…"
        @unknown default:
            return "Checking iCloud…"
        }
    }
}
