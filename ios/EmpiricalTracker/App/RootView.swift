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
    case home, nutrition, body, settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home:      return String(localized: "tab.home")
        case .nutrition: return String(localized: "tab.nutrition")
        case .body:      return String(localized: "tab.body")
        case .settings:  return String(localized: "tab.settings")
        }
    }

    var icon: String {
        switch self {
        case .home:      return "house.fill"
        case .nutrition: return "fork.knife"
        case .body:      return "figure.walk"
        case .settings:  return "gearshape"
        }
    }
}

/// Tab shell. Each destination is kept alive in a `ZStack` (toggled via
/// opacity) so view-model state and scroll position survive tab switches — the
/// behaviour the system `TabView` gave us for free — while a translucent floating
/// capsule replaces the opaque system bar.
struct MainTabView: View {
    @State private var selection: AppTab = .home
    // Tracks which tabs have been visited at least once. A tab is only rendered
    // after its first selection, preventing all six views from firing their
    // network tasks simultaneously on launch.
    @State private var activated: Set<AppTab> = [.home]

    var body: some View {
        ZStack {
            screen(.home)      { DashboardView() }
            screen(.nutrition) { NutritionHubView() }
            screen(.body)      { BodyMetricsView() }
            screen(.settings)  { SettingsView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $selection)
        }
        .onChange(of: selection) { _, newTab in
            activated.insert(newTab)
        }
    }

    /// Layers one tab's screen, visible only when selected. Tabs that have never
    /// been visited are not rendered at all, so their `.task` modifiers don't fire
    /// until first use. Once rendered, the view stays in the hierarchy (opacity 0)
    /// so state and scroll position survive tab switches.
    @ViewBuilder
    private func screen<Content: View>(_ tab: AppTab, @ViewBuilder _ content: () -> Content) -> some View {
        let isActive = selection == tab
        if activated.contains(tab) {
            content()
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(isActive)
                .accessibilityHidden(!isActive)
                .zIndex(isActive ? 1 : 0)
        }
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
                    .foregroundStyle(selection == tab && tab != .home ? Color.accent : Color.textMuted)
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
