import SwiftUI
import Core
import AppAuth

@main
struct EmpiricalTrackerApp: App {
    @State private var env = AppEnvironment(authService: AppConfig.authService)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                // Theme is applied at the root so every screen inherits it.
                .preferredColorScheme(env.settings.theme.colorScheme)
                // Restore the session silently before the first frame is committed.
                .task { await env.authStore.restoreSession() }
        }
    }
}
