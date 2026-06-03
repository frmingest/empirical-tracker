import Foundation

/// Central home for the app's legal / compliance URLs.
///
/// The privacy policy URL is **mandatory** in App Store Connect and is surfaced
/// in-app (auth screen, Settings, and the health-data consent step) because
/// Empirical Tracker processes GDPR special-category health data.
///
/// > Important: These point at the canonical `empirical.app` domain. Update them
/// > to the live, publicly reachable policy/terms pages before submitting to
/// > App Review and paste the same privacy-policy URL into App Store Connect.
enum Legal {
    /// Public privacy policy. Also entered in App Store Connect ▸ App Privacy.
    static let privacyPolicyURL = URL(string: "https://empirical.app/privacy")!

    /// Terms of service / user agreement.
    static let termsOfServiceURL = URL(string: "https://empirical.app/terms")!
}
