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
            } else if !env.userProfile.hasCompletedSetup {
                // First run after consent: offer to capture profile basics (height,
                // weight, waist, units) or sync with Apple Health. Fully skippable.
                ProfileSetupView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: env.authStore.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: env.consent.hasConsented)
        .animation(.easeInOut(duration: 0.3), value: env.userProfile.hasCompletedSetup)
    }
}

// MARK: - Main Tab Bar

/// The primary destinations, surfaced through a custom floating tab bar
/// (see `FloatingTabBar`) rather than the system `TabView` so the shell matches
/// the redesigned, rounded "glass capsule" look. Includes the Recipes catalogue
/// added in the Sprint 7 recipes module.
enum AppTab: Int, CaseIterable, Identifiable {
    case home, diary, plan, recipes, body, settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home:     return String(localized: "tab.home")
        case .diary:    return String(localized: "tab.diary")
        case .plan:     return String(localized: "tab.plan")
        case .recipes:  return String(localized: "tab.recipes")
        case .body:     return String(localized: "tab.body")
        case .settings: return String(localized: "tab.settings")
        }
    }

    var icon: String {
        switch self {
        case .home:     return "chart.line.uptrend.xyaxis"
        case .diary:    return "fork.knife"
        case .plan:     return "calendar"
        case .recipes:  return "frying.pan"
        case .body:     return "figure.walk"
        case .settings: return "gearshape"
        }
    }
}

/// Tab shell. Each destination is kept alive in a `ZStack` (toggled via
/// opacity) so view-model state and scroll position survive tab switches — the
/// behaviour the system `TabView` gave us for free — while a translucent floating
/// capsule replaces the opaque system bar.
struct MainTabView: View {
    @State private var selection: AppTab = .home

    var body: some View {
        ZStack {
            screen(.home)     { DashboardView() }
            screen(.diary)    { FoodDiaryView() }
            screen(.plan)     { MealPlanCalendarView() }
            screen(.recipes)  { RecipesView() }
            screen(.body)     { BodyMetricsView() }
            screen(.settings) { SettingsView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $selection)
        }
    }

    /// Layers one tab's screen, visible only when selected. Hidden screens stay in
    /// the hierarchy (opacity 0) to preserve state, but ignore touches and drop out
    /// of the accessibility tree.
    @ViewBuilder
    private func screen<Content: View>(_ tab: AppTab, @ViewBuilder _ content: () -> Content) -> some View {
        let isActive = selection == tab
        content()
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }
}

// MARK: - Floating tab bar

/// Translucent, capsule-shaped tab bar that floats above the content with side
/// margins and a soft shadow — the signature element of the redesigned shell.
private struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? Color.accent : Color.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.borderCard.opacity(0.5), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}
