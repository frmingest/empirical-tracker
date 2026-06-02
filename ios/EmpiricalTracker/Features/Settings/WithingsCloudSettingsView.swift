import Core
import SwiftUI

/// Settings ▸ Withings (Sprint 10, ADR-023). Connection management for the Withings
/// **Cloud** path: connect, sync now, disconnect, plus the privacy/about copy. Mirrors
/// the Body-tab card's connection state (both read the single
/// `AppEnvironment.withingsCloudState`).
struct WithingsCloudSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    private var state: WithingsCloudState { env.withingsCloudState }

    var body: some View {
        List {
            statusSection
            aboutSection
        }
        .navigationTitle(String(localized: "withings.settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .task { await state.refreshOnAppear() }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        Section {
            switch state.connection {
            case .notConnected, .unavailable:
                Button {
                    Task { await state.connect() }
                } label: {
                    Label(String(localized: "withings.connect"), systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(Color.accent)
                }
            case .connecting:
                HStack(spacing: 10) {
                    ProgressView()
                    Text(String(localized: "withings.connecting"))
                        .foregroundStyle(Color.textSecondary)
                }
            case .connected:
                LabeledContent {
                    Text(lastSyncText).foregroundStyle(Color.textSecondary)
                } label: {
                    Label(String(localized: "withings.connected"), systemImage: "checkmark.seal")
                        .foregroundStyle(Color.textPrimary)
                }
                Button {
                    Task { await state.syncNow() }
                } label: {
                    Label(
                        String(localized: state.isSyncing ? "withings.syncing" : "withings.sync_now"),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .foregroundStyle(Color.accent)
                }
                .disabled(state.isSyncing)
                Button(role: .destructive) {
                    Task { await state.disconnect() }
                } label: {
                    Label(String(localized: "withings.disconnect"), systemImage: "xmark.circle")
                }
            }

            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.bodySmall)
                    .foregroundStyle(Color.outRange)
            }
        } header: {
            Text(String(localized: "withings.settings.section.title"))
        } footer: {
            if state.connection == .connected {
                Text(String(localized: "withings.disconnect.hint"))
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            Text(String(localized: "withings.about"))
                .font(.bodySmall)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Helpers

    private var lastSyncText: String {
        guard let date = state.lastSyncDate else {
            return String(localized: "withings.never")
        }
        return date.formatted(.relative(presentation: .named))
    }
}
