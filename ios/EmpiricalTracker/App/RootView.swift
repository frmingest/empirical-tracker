import SwiftUI
import Core
import AppAuth

/// Root navigator. Switches between `AuthView` (unauthenticated) and the main
/// `TabView` (authenticated) based on live `AuthStore` state.
/// The cross-fade animation makes the transition feel intentional.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if !env.authStore.isAuthenticated {
                AuthView()
            } else if !env.consent.hasConsented {
                // GDPR special-category (health) data requires explicit consent
                // before the app starts processing it.
                ConsentView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: env.authStore.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: env.consent.hasConsented)
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
                FoodDiaryView()
            }
            Tab(String(localized: "tab.plan"), systemImage: "calendar") {
                MealPlanCalendarView()
            }
            Tab(String(localized: "tab.body"), systemImage: "figure.walk") {
                BodyMetricsView()
            }
            Tab(String(localized: "tab.settings"), systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(Color.accent)
    }
}

// All five tabs are now backed by real feature screens.
