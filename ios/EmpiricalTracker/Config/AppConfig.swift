import Foundation
import Auth

/// Resolves runtime configuration from the Xcode scheme environment and `Info.plist`.
///
/// ## Configuring credentials
///
/// Add these keys to `EmpiricalTracker/Info.plist` (or an xcconfig file):
/// ```
/// SupabaseURL     → https://YOUR_PROJECT.supabase.co
/// SupabaseAnonKey → YOUR_ANON_KEY
/// ```
///
/// ## Demo / development mode
///
/// Set `DEMO_MODE=1` in the Xcode scheme (Product > Scheme > Edit Scheme > Run >
/// Arguments > Environment Variables) to bypass Supabase and use mock data.
enum AppConfig {

    static var authService: any AuthServiceProtocol {
        if ProcessInfo.processInfo.environment["DEMO_MODE"] == "1" {
            return MockAuthService()
        }
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let url = URL(string: urlString), !urlString.isEmpty,
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
            !anonKey.isEmpty
        else {
            // Keys not configured — fall back to mock so the app is runnable in dev.
#if DEBUG
            return MockAuthService()
#else
            fatalError("SupabaseURL and SupabaseAnonKey must be set in Info.plist for production builds.")
#endif
        }
        return SupabaseAuthService(supabaseURL: url, supabaseAnonKey: anonKey)
    }
}
