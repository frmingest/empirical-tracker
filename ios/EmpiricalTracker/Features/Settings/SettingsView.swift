import SwiftUI
import Core
import Auth

/// Global settings tab.
/// Sprint 1: theme toggle, language toggle, account info, sign-out.
/// Extended in Sprint 11: GDPR export, account deletion, HealthKit/Withings management.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showRestartNotice = false

    var body: some View {
        @Bindable var settings = env.settings

        NavigationStack {
            List {
                appearanceSection(settings: settings)
                accountSection
            }
            .navigationTitle(String(localized: "settings.title"))
            .listStyle(.insetGrouped)
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
    private var accountSection: some View {
        Section(String(localized: "settings.section.account")) {
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
                Task { await env.authStore.signOut() }
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
}

#Preview {
    SettingsView()
        .environment(AppEnvironment.preview())
}
