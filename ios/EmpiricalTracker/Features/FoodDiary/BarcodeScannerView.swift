import Core
import SwiftUI
import VisionKit

/// Outcome of a barcode scan session.
enum BarcodeScanResult: Sendable {
    case code(String)
    case cancelled
    case failure
}

/// Native barcode scanning via VisionKit's `DataScannerViewController`. Replaces the
/// web's manual barcode field (Sprint 6). Barcodes route to Open Food Facts only.
/// Falls back to a clear message on devices/simulators without live camera scanning.
struct BarcodeScannerView: View {
    let completion: (BarcodeScanResult) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerRepresentable(completion: completion)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .bottom) { hint }
                } else {
                    unsupported
                }
            }
            .navigationTitle(String(localized: "food.scan.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { completion(.cancelled) }
                }
            }
        }
    }

    private var hint: some View {
        Text(String(localized: "food.scan.hint"))
            .font(.bodySmall)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(.bottom, 32)
    }

    private var unsupported: some View {
        EmptyStateView(
            icon: "barcode.viewfinder",
            title: String(localized: "food.scan.unsupported.title"),
            message: String(localized: "food.scan.unsupported.message")
        )
    }
}

// MARK: - UIKit bridge

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let completion: (BarcodeScanResult) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let completion: (BarcodeScanResult) -> Void
        private var didFinish = false

        init(completion: @escaping (BarcodeScanResult) -> Void) {
            self.completion = completion
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didFinish else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    didFinish = true
                    dataScanner.stopScanning()
                    completion(.code(payload))
                    return
                }
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            guard !didFinish else { return }
            didFinish = true
            completion(.failure)
        }
    }
}
