import SwiftUI
import Core

@main
struct EmpiricalTrackerApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .preferredColorScheme(nil) // respects system; Sprint 1 wires user override
        }
    }
}
