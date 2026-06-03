import SwiftUI
import UIKit

/// Wraps `UIActivityViewController` so SwiftUI can present the system share sheet.
/// Used by the GDPR data export to hand a saved file off to Files, Mail, AirDrop, etc.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
