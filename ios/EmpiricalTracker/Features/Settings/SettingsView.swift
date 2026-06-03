import SwiftUI
import Core
import AppAuth

/// Global settings tab.
/// Sprint 1: theme toggle, language toggle, account info, sign-out.
/// Extended in Sprint 11: GDPR export, account deletion, HealthKit/Withings management.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showRestartNotice = false
    @State private var legalURL: URL?

    var body: some View {
        @Bindable var settings = env.settings

        NavigationStack {
            List {
                appearanceSection(settings: settings)
                dataSection
                devicesSection
                accountSection
                legalSection
            }
            .navigationTitle(String(localized: "settings.title"))
            .listStyle(.insetGrouped)
            .sheet(item: $legalURL) { url in
                SafariSheet(url: url)
                    .ignoresSafeArea()
            }
            // Resolve Withings Cloud availability so its row appears here even if the
            // Body tab hasn't been opened yet (Sprint 10).
            .task { await env.withingsCloudState.refreshStatus() }
            .alert(
                String(localized: "settings.language.restart.title"),
                isPresented: $showRestartNotice
            ) {
                Button(String(localized: "settings.language.restart.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings.language.restart.message"))
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func appearanceSection(settings: SettingsStore) -> some View {
        Section(String(localized: "settings.section.appearance")) {
            // Theme
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.theme.label"))
                    .font(.labelLarge)
                    .foregroundStyle(Color.textSecondary)
                @Bindable var s = settings
                Picker(String(localized: "settings.theme.label"), selection: $s.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(String(localized: "settings.theme.label"))
            }
            .padding(.vertical, 4)

            // Language
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.language.label"))
                    .font(.labelLarge)
                    .foregroundStyle(Color.textSecondary)
                @Bindable var s = settings
                Picker(String(localized: "settings.language.label"), selection: $s.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.language) { showRestartNotice = true }
                .accessibilityLabel(String(localized: "settings.language.label"))
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var dataSection: some View {
        Section(String(localized: "settings.section.data")) {
            NavigationLink {
                DietEventManagerView()
            } label: {
                Label(
                    String(localized: "diet_events.title"),
                    systemImage: "fork.knife.circle"
                )
                .foregroundStyle(Color.textPrimary)
            }
        }
    }

    /// Connected health-data sources (Sprint 9: Apple Health; Sprint 10: Withings Cloud).
    /// Each row hides when its path is unavailable — Apple Health when HealthKit is
    /// absent, Withings Cloud until the backend exposes the `/withings/*` endpoints.
    @ViewBuilder
    private var devicesSection: some View {
        let showHealth = env.healthSyncState.connection != .unavailable
        let showWithings = env.withingsCloudState.connection != .unavailable
        if showHealth || showWithings {
            Section(String(localized: "settings.section.devices")) {
                if showHealth {
                    NavigationLink {
                        HealthSyncSettingsView()
                    } label: {
                        Label(
                            String(localized: "healthsync.settings.title"),
                            systemImage: "heart.text.square"
                        )
                        .foregroundStyle(Color.textPrimary)
                    }
                }
                if showWithings {
                    NavigationLink {
                        WithingsCloudSettingsView()
                    } label: {
                        Label(
                            String(localized: "withings.settings.title"),
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                        .foregroundStyle(Color.textPrimary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section(String(localized: "settings.section.account")) {
            // Demo-mode diagnostic: when Supabase isn't configured the app signs in
            // as the hardcoded demo user, not the real account. Make that obvious.
            if AppConfig.isUsingMockAuth {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Demo mode — backend not configured")
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        Text(verbatim: "Login and data are simulated. Set Supabase/API keys to use your real account.")
                            .font(.bodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .accessibilityElement(children: .combine)
            }

            // Signed-in email
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(env.authStore.email ?? "—")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Text(String(localized: "settings.account.signed_in"))
                        .font(.bodySmall)
                        .foregroundStyle(Color.textSecondary)
                }
            } icon: {
                Image(systemName: "person.circle")
                    .foregroundStyle(Color.accent)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(localized: "settings.account.signed_in") + " " + (env.authStore.email ?? "")
            )

            // Sign out
            Button(role: .destructive) {
                Task { await env.signOut() }
            } label: {
                Label(
                    String(localized: "settings.sign_out"),
                    systemImage: "rectangle.portrait.and.arrow.right"
                )
            }
            .accessibilityLabel(String(localized: "settings.sign_out"))
            .accessibilityHint(String(localized: "settings.sign_out.hint"))
        }
    }

    /// Privacy policy + terms. The privacy-policy link is required in-app for a
    /// HealthKit app and must match the URL published in App Store Connect.
    @ViewBuilder
    private var legalSection: some View {
        Section(String(localized: "settings.section.legal")) {
            Button {
                legalURL = Legal.privacyPolicyURL
            } label: {
                Label(String(localized: "legal.privacy_policy"), systemImage: "hand.raised")
                    .foregroundStyle(Color.textPrimary)
            }
            Button {
                legalURL = Legal.termsOfServiceURL
            } label: {
                Label(String(localized: "legal.terms"), systemImage: "doc.text")
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment.preview())
}
