import SwiftUI
import Core
import Account
import AppAuth

/// Global settings tab.
/// Sprint 1: theme toggle, language toggle, account info, sign-out.
/// Extended in Sprint 11: GDPR export, account deletion, HealthKit/Withings management.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showRestartNotice = false

    // Account data (GDPR): export download + type-to-confirm deletion.
    @State private var showExportFormatDialog = false
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var shareItem: ShareItem?
    @State private var showDeleteAccount = false

    var body: some View {
        @Bindable var settings = env.settings

        NavigationStack {
            List {
                appearanceSection(settings: settings)
                dataSection
                devicesSection
                accountSection
                dangerZoneSection
            }
            .navigationTitle(String(localized: "settings.title"))
            .listStyle(.insetGrouped)
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
            .confirmationDialog(
                String(localized: "settings.account.export.format"),
                isPresented: $showExportFormatDialog,
                titleVisibility: .visible
            ) {
                Button(String(verbatim: "JSON")) { startExport(.json) }
                Button(String(verbatim: "CSV (ZIP)")) { startExport(.csv) }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountView()
            }
            .alert(
                String(localized: "settings.account.export.error.title"),
                isPresented: Binding(
                    get: { exportError != nil },
                    set: { if !$0 { exportError = nil } }
                )
            ) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(exportError ?? "")
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

            // Export my data (GDPR Art. 20 — data portability)
            Button {
                showExportFormatDialog = true
            } label: {
                HStack {
                    Label(
                        String(localized: "settings.account.export"),
                        systemImage: "square.and.arrow.up"
                    )
                    .foregroundStyle(Color.textPrimary)
                    if isExporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)
            .accessibilityLabel(String(localized: "settings.account.export"))
            .accessibilityHint(String(localized: "settings.account.export.hint"))

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

    /// Irreversible account actions, fenced off in their own section with a
    /// warning footer (Apple Guideline 5.1.1(v) / GDPR right to erasure).
    @ViewBuilder
    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteAccount = true
            } label: {
                Label(
                    String(localized: "settings.account.delete"),
                    systemImage: "trash"
                )
            }
            .accessibilityLabel(String(localized: "settings.account.delete"))
            .accessibilityHint(String(localized: "settings.account.delete.hint"))
        } header: {
            Text(String(localized: "settings.account.danger_zone"))
        } footer: {
            Text(String(localized: "settings.account.delete.footer"))
        }
    }

    // MARK: - Export

    /// Downloads the export, writes it to a temp file, and hands it to the share sheet.
    private func startExport(_ format: AccountRepository.ExportFormat) {
        guard !isExporting else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let data = try await env.account.exportData(format: format)
                shareItem = ShareItem(url: try writeExportFile(data, format: format))
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    /// Persists the raw export bytes to a temp file named to match the backend's
    /// `Content-Disposition` (JSON document, or a CSV zip archive).
    private func writeExportFile(
        _ data: Data,
        format: AccountRepository.ExportFormat
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        let stamp = formatter.string(from: Date())
        let ext = format == .csv ? "zip" : "json"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("empirical-export-\(stamp).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Identifiable wrapper so a freshly written export file URL can drive `.sheet(item:)`.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

#Preview {
    SettingsView()
        .environment(AppEnvironment.preview())
}
