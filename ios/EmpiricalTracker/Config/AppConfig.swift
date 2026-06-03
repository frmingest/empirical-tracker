import Foundation
import OSLog
import AppAuth

/// Resolves runtime configuration from the Xcode scheme environment and `Info.plist`.
///
/// ## Configuring credentials
///
/// `Info.plist` carries the Supabase coordinates directly under the `SupabaseURL`
/// and `SupabaseAnonKey` keys, with **literal** production values committed to the
/// repo. The anon key is a *public* client key (role `anon`), safe to ship in the
/// binary — it is NOT the service-role/secret key, which must never appear here.
/// Committing the literal values is deliberate: it makes Release/Archive builds
/// self-contained, so an archive resolves real credentials at runtime and never
/// trips the production guard below — even on a machine or CI runner that does not
/// have the git-ignored `Config.xcconfig`.
///
/// To point a *local* build at a different Supabase project (e.g. staging), edit
/// the `SupabaseURL` / `SupabaseAnonKey` values in `Info.plist`. (`Config.xcconfig`
/// holds the same coordinates for reference and for `EMPIRICAL_API_URL`, but the
/// Supabase keys are consumed from `Info.plist`, not substituted from xcconfig —
/// so changing only the xcconfig has no effect on the resolved Supabase creds.)
///
/// ## Demo / development mode
///
/// Set `DEMO_MODE=1` in the Xcode scheme (Product > Scheme > Edit Scheme > Run >
/// Arguments > Environment Variables) to bypass Supabase and use mock data. This is
/// a Run-scheme environment variable only: it is absent from Archive builds, so a
/// shipped/TestFlight build can never silently start in demo mode.
enum AppConfig {

    private static let log = Logger(subsystem: "app.empirical.tracker", category: "AppConfig")

    /// True when the app is running against `MockAuthService` (demo / unconfigured).
    /// Surfaced in the UI so a misconfigured build is never mistaken for the real account.
    static let isUsingMockAuth: Bool = {
        if ProcessInfo.processInfo.environment["DEMO_MODE"] == "1" { return true }
        return resolvedSupabaseCredentials() == nil
    }()

    static var authService: any AuthServiceProtocol {
        if ProcessInfo.processInfo.environment["DEMO_MODE"] == "1" {
            log.notice("DEMO_MODE=1 — using MockAuthService.")
            return MockAuthService()
        }
        guard let creds = resolvedSupabaseCredentials() else {
            // Keys not configured — fall back to mock so the app is runnable in dev.
            // ⚠️ In DEBUG this means any login silently becomes the demo user
            // (demo@empirical.app) and all API calls carry a fake token.
            log.error("""
                ⚠️ Supabase is NOT configured (SupabaseURL / SupabaseAnonKey missing or unresolved). \
                Falling back to MockAuthService — you are NOT signed in to your real account, \
                and backend calls will fail. Set SUPABASE_URL / SUPABASE_ANON_KEY via Config.xcconfig.
                """)
#if DEBUG
            return MockAuthService()
#else
            fatalError("SupabaseURL and SupabaseAnonKey must be set in Info.plist for production builds.")
#endif
        }
        return SupabaseAuthService(supabaseURL: creds.url, supabaseAnonKey: creds.anonKey)
    }

    /// Reads and validates the Supabase credentials from `Info.plist`.
    /// Returns `nil` when a value is missing, empty, or still an unresolved
    /// build-setting placeholder like `$(SUPABASE_URL)`.
    private static func resolvedSupabaseCredentials() -> (url: URL, anonKey: String)? {
        guard
            let urlString = plistString("SupabaseURL"),
            let anonKey = plistString("SupabaseAnonKey"),
            let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true
        else { return nil }
        return (url, anonKey)
    }

    /// Returns a trimmed, non-empty, fully-resolved Info.plist string, or `nil`.
    private static func plistString(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reject empties and unresolved `$(VAR)` placeholders left by missing build settings.
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
}
