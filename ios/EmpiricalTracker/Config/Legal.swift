import Foundation

/// Central home for the app's legal / compliance URLs.
///
/// The privacy policy URL is **mandatory** in App Store Connect and is surfaced
/// in-app (auth screen, Settings, and the health-data consent step) because
/// Empirical Tracker processes GDPR special-category health data.
///
/// The document text lives in the repo at `docs/legal/privacy-policy.md` and
/// `docs/legal/terms-of-service.md`.
///
/// > Important: ⚠️ The URLs below are **placeholders** on the unconfirmed
/// > `empirical.app` domain. We have **not yet decided where to host** these
/// > pages. Once a domain is chosen and the documents are published, update both
/// > URLs and paste the privacy-policy URL into App Store Connect. See
/// > `docs/legal/README.md` for the open items.
enum Legal {
    /// Public privacy policy. Also entered in App Store Connect ▸ App Privacy.
    static let privacyPolicyURL = URL(string: "https://empirical.app/privacy")!

    /// Terms of service / user agreement.
    static let termsOfServiceURL = URL(string: "https://empirical.app/terms")!
}
