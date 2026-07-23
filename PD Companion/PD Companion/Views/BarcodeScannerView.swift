import SwiftUI
import VisionKit
import Vision
import AVFoundation

/// Live barcode scanner presented as a sheet (VisionKit `DataScannerViewController`).
/// Reports the first recognized barcode string via `onScan`, then the caller dismisses
/// and looks it up in `BarcodeCorpus`. Camera-only, fully on-device — no network.
/// Degrades to a clear message when the camera is unavailable or access is denied; the
/// caller always still offers manual/voice entry, so scanning is never a dead end.
struct BarcodeScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var state: ScanState = .checking

    private enum ScanState { case checking, ready, denied, unsupported }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .checking:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready:
                    DataScannerRepresentable { code in
                        onScan(code)
                        dismiss()
                    }
                    .ignoresSafeArea(edges: .bottom)
                case .denied:
                    unavailable("Camera access is off",
                                "Turn it on in Settings › Kampa › Camera to scan. You can still type the item instead.")
                case .unsupported:
                    unavailable("Scanning isn't available",
                                "This device can't scan barcodes. Type the item instead.")
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await resolveAccess() }
    }

    private func unavailable(_ title: String, _ message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "barcode.viewfinder")
        } description: {
            Text(message)
        }
    }

    private func resolveAccess() async {
        guard DataScannerViewController.isSupported else { state = .unsupported; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            state = .ready
        case .notDetermined:
            state = await AVCaptureDevice.requestAccess(for: .video) ? .ready : .denied
        default:
            state = .denied
        }
    }
}

/// UIKit bridge for the live scanner. Restricted to the symbologies packaged food uses
/// (EAN-13 / UPC-A-as-EAN-13, EAN-8, UPC-E) so it doesn't fire on QR codes etc.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var fired = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            report(addedItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            report([item])
        }

        // First valid barcode wins; guard against the delegate firing repeatedly while the
        // sheet dismisses.
        private func report(_ items: [RecognizedItem]) {
            guard !fired else { return }
            for case let .barcode(barcode) in items {
                if let value = barcode.payloadStringValue, !value.isEmpty {
                    fired = true
                    onScan(value)
                    return
                }
            }
        }
    }
}
