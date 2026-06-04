import Foundation

/// Central home for the app's legal / compliance URLs.
///
/// The privacy policy URL is **mandatory** in App Store Connect and is surfaced
/// in-app (auth screen, Settings, and the health-data consent step) because
/// Empirical Tracker processes GDPR special-category health data.
///
/// The document text lives in the repo at `docs/legal/privacy-policy.md` and
/// `docs/legal/terms-of-service.md`; rendered pages are served via GitHub Pages
/// from `docs/` on the main branch.
///
/// After merging, enable GitHub Pages in repo Settings ▸ Pages (Source: main / docs/)
/// then paste `privacyPolicyURL` into App Store Connect ▸ App Privacy.
enum Legal {
    /// Public privacy policy. Also entered in App Store Connect ▸ App Privacy.
    static let privacyPolicyURL = URL(string: "https://frmingest.github.io/empirical-tracker/privacy")!

    /// Terms of service / user agreement.
    static let termsOfServiceURL = URL(string: "https://frmingest.github.io/empirical-tracker/terms")!
}
