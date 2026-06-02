import Foundation
import OSLog
import AppAuth

/// Resolves runtime configuration from the Xcode scheme environment and `Info.plist`.
///
/// ## Configuring credentials
///
/// The recommended path is an **xcconfig** file so secrets never land in git.
/// Copy `Config.xcconfig.example` → `Config.xcconfig`, fill in your values, and
/// set it as the configuration file for the `EmpiricalTracker` target (Project ▸
/// Info ▸ Configurations). `Config.xcconfig` is git-ignored. It must define:
/// ```
/// SUPABASE_URL      = https://YOUR_PROJECT.supabase.co
/// SUPABASE_ANON_KEY = YOUR_ANON_KEY
/// EMPIRICAL_API_URL = https://your-api.up.railway.app
/// ```
/// `Info.plist` already maps `SupabaseURL → $(SUPABASE_URL)` and
/// `SupabaseAnonKey → $(SUPABASE_ANON_KEY)`, so these flow through at build time.
///
/// ## Demo / development mode
///
/// Set `DEMO_MODE=1` in the Xcode scheme (Product > Scheme > Edit Scheme > Run >
/// Arguments > Environment Variables) to bypass Supabase and use mock data.
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
