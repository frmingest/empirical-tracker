import SwiftUI
import UIKit

/// Thin wrapper around `UIActivityViewController` so the generated PDF can be
/// shared through the system sheet — including Mail, Messages, Files, AirDrop.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
