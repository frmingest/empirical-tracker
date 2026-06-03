import SwiftUI
import SafariServices

/// Thin `SFSafariViewController` wrapper so legal pages (privacy policy, terms)
/// open in-app rather than bouncing out to Safari. Presented via
/// `.sheet(item:)` against an optional `URL`.
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Lets a plain `URL` drive `.sheet(item:)`. The absolute string is a stable,
/// unique identity for the presented page.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
