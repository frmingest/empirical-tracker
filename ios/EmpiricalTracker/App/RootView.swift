import SwiftUI
import Core

/// Root navigator. Switches between `AuthView` (unauthenticated) and the main
/// `TabView` (authenticated). Auth wired fully in Sprint 1.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if env.isAuthenticated {
            MainTabView()
        } else {
            AuthPlaceholderView()
        }
    }
}

// MARK: - Main Tab Bar

/// Five-tab shell declared in the migration plan §1.4.
/// Each destination is a placeholder until its sprint ships.
struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "chart.line.uptrend.xyaxis") {
                DashboardPlaceholderView()
            }
            Tab("Diary", systemImage: "fork.knife") {
                DiaryPlaceholderView()
            }
            Tab("Plan", systemImage: "calendar") {
                PlanPlaceholderView()
            }
            Tab("Body", systemImage: "figure.walk") {
                BodyPlaceholderView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsPlaceholderView()
            }
        }
        .tint(Color.accent)
    }
}

// MARK: - Placeholder screens (replaced sprint-by-sprint)

private struct AuthPlaceholderView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 56))
                .foregroundStyle(Color.accent)
            Text("Empirical Tracker")
                .font(.displayMedium)
                .foregroundStyle(Color.textPrimary)
            Text("Sprint 1 — Auth integration coming next.")
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
            Button("Sign in (demo)") {
                env.isAuthenticated = true
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgBase)
    }
}

private struct DashboardPlaceholderView: View {
    var body: some View { placeholder("chart.bar.doc.horizontal", "Dashboard", "Sprint 2") }
}
private struct DiaryPlaceholderView: View {
    var body: some View { placeholder("fork.knife",           "Food Diary",  "Sprint 6") }
}
private struct PlanPlaceholderView: View {
    var body: some View { placeholder("calendar",             "Meal Plans",  "Sprint 7") }
}
private struct BodyPlaceholderView: View {
    var body: some View { placeholder("figure.walk",          "Body Metrics","Sprint 8") }
}
private struct SettingsPlaceholderView: View {
    var body: some View { placeholder("gearshape",            "Settings",    "Sprint 11") }
}

private func placeholder(_ icon: String, _ title: String, _ sprint: String) -> some View {
    EmptyStateView(
        icon: icon,
        title: title,
        message: "\(sprint) — coming soon."
    )
}
