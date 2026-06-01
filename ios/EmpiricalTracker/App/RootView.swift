import SwiftUI
import Core
import Auth

/// Root navigator. Switches between `AuthView` (unauthenticated) and the main
/// `TabView` (authenticated) based on live `AuthStore` state.
/// The cross-fade animation makes the transition feel intentional.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.authStore.isAuthenticated {
                MainTabView()
            } else {
                AuthView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: env.authStore.isAuthenticated)
    }
}

// MARK: - Main Tab Bar

/// Five-tab shell declared in the migration plan §1.4.
/// Each destination is a placeholder until its sprint ships.
struct MainTabView: View {
    var body: some View {
        TabView {
            Tab(String(localized: "tab.home"), systemImage: "chart.line.uptrend.xyaxis") {
                DashboardView()
            }
            Tab(String(localized: "tab.diary"), systemImage: "fork.knife") {
                DiaryPlaceholderView()
            }
            Tab(String(localized: "tab.plan"), systemImage: "calendar") {
                PlanPlaceholderView()
            }
            Tab(String(localized: "tab.body"), systemImage: "figure.walk") {
                BodyPlaceholderView()
            }
            Tab(String(localized: "tab.settings"), systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(Color.accent)
    }
}

// MARK: - Placeholder screens (replaced sprint-by-sprint)

private struct DiaryPlaceholderView: View {
    var body: some View {
        EmptyStateView(
            icon: "fork.knife",
            title: String(localized: "tab.diary"),
            message: String(localized: "placeholder.sprint", defaultValue: "Sprint 6 — coming soon.")
        )
    }
}

private struct PlanPlaceholderView: View {
    var body: some View {
        EmptyStateView(
            icon: "calendar",
            title: String(localized: "tab.plan"),
            message: String(localized: "placeholder.sprint", defaultValue: "Sprint 7 — coming soon.")
        )
    }
}

private struct BodyPlaceholderView: View {
    var body: some View {
        EmptyStateView(
            icon: "figure.walk",
            title: String(localized: "tab.body"),
            message: String(localized: "placeholder.sprint", defaultValue: "Sprint 8 — coming soon.")
        )
    }
}
