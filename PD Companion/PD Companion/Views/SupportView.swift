import SwiftUI
import WatchConnectivity

/// Contact-support screen.
///
/// Deliberately NOT built on `MFMailComposeViewController`: that only works when Apple
/// Mail is configured, so it fails outright for anyone whose mail lives in the Gmail or
/// Outlook app. The self-contained path is primary here — the address and the diagnostics
/// are on screen, copyable, and shareable through any channel. Opening a mail app is one
/// optional route out, not the only one.
///
/// The diagnostics are shown in full before they go anywhere. In a health app the user
/// should be able to read exactly what they are about to send, and confirm for themselves
/// that it contains no health values.
struct SupportView: View {
    let tremorCount: Int
    let tremorFirst: Date?
    let tremorLast: Date?
    let foodCount: Int
    let foodFirst: Date?
    let foodLast: Date?

    @EnvironmentObject private var healthKit: HealthKitManager
    @State private var didCopy = false

    private var diagnostics: String {
        SupportDiagnostics.text(
            healthAuthorized: healthKit.isAuthorized,
            tremorCount: tremorCount,
            tremorFirst: tremorFirst,
            tremorLast: tremorLast,
            foodCount: foodCount,
            foodFirst: foodFirst,
            foodLast: foodLast
        )
    }

    var body: some View {
        List {
            Section {
                Text(SupportDiagnostics.supportEmail)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Insight.brandBlue)
                    .textSelection(.enabled)
                    .accessibilityLabel("Support email address, \(SupportDiagnostics.supportEmail)")
            } header: {
                Text("Email us")
            } footer: {
                Text("Tell us what happened in your own words. If it helps, include the details below — they say which version you're on and how much data you have, and nothing about your health.")
            }

            Section {
                Button {
                    UIPasteboard.general.string = diagnostics
                    withAnimation { didCopy = true }
                } label: {
                    Label(didCopy ? "Copied" : "Copy details", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }

                Button {
                    ShareSheetPresenter.present(items: [diagnostics])
                } label: {
                    Label("Share details", systemImage: "square.and.arrow.up")
                }

                if let mailURL = SupportDiagnostics.mailURL(body: diagnostics) {
                    Link(destination: mailURL) {
                        Label("Open in email app", systemImage: "envelope")
                    }
                }
            } footer: {
                Text("Copy pastes the details wherever you like. Share sends them through Messages, Mail, or anything else on your phone.")
            }

            Section {
                Text(diagnostics)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            } header: {
                Text("Details")
            }
        }
        .navigationTitle("Contact support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Builds the support diagnostics block.
///
/// ⛔ Counts and status only — never a health value. A support message should never carry
/// a tremor reading, a dose, or a symptom. Sizes and spans are enough to reproduce almost
/// any bug worth reporting, and they cost the user nothing to disclose.
enum SupportDiagnostics {
    /// Single point of truth for the address. A Namecheap forwarder points this at the
    /// real inbox, so routing can change without shipping an app update.
    static let supportEmail = "support@kampa.health"

    static var versionAndBuild: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static func text(
        healthAuthorized: Bool,
        tremorCount: Int,
        tremorFirst: Date?,
        tremorLast: Date?,
        foodCount: Int,
        foodFirst: Date?,
        foodLast: Date?
    ) -> String {
        var lines = [
            "Kampa \(versionAndBuild)",
            "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion), \(deviceModel)",
            "Apple Watch paired: \(isWatchPaired)",
            "Health access: \(healthAuthorized ? "granted" : "not granted")",
            "Tremor readings: \(tremorCount)\(span(tremorFirst, tremorLast))",
            "Food events: \(foodCount)\(span(foodFirst, foodLast))"
        ]
        lines.append("Sent \(Self.timestampFormatter.string(from: Date()))")
        return lines.joined(separator: "\n")
    }

    /// `mailto:` rather than `MFMailComposeViewController` — this opens whatever the user
    /// set as their default mail app, so it works for Gmail and Outlook users too.
    static func mailURL(body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Kampa support"),
            URLQueryItem(name: "body", value: "\n\n\(body)")
        ]
        return components.url
    }

    private static func span(_ first: Date?, _ last: Date?) -> String {
        guard let first, let last else { return "" }
        let from = dayFormatter.string(from: first)
        let to = dayFormatter.string(from: last)
        return from == to ? " (\(from))" : " (\(from) to \(to))"
    }

    /// The hardware identifier, e.g. `iPhone17,1`. `UIDevice.model` only ever says
    /// "iPhone", which is useless for reproducing a device-specific bug.
    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static var isWatchPaired: String {
        guard WCSession.isSupported() else { return "not supported" }
        return WCSession.default.isPaired ? "yes" : "no"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm zzz"
        return formatter
    }()
}
