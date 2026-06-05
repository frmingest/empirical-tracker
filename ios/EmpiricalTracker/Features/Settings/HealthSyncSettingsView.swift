import Core
import HealthSync
import SwiftUI

/// Settings ▸ Apple Health (Sprint 9, ADR-022). Granular per-type import toggles,
/// connection management, and the disconnect/revoke guidance. Mirrors the Body-tab
/// card's connection state (both read the single `AppEnvironment.healthSyncState`).
struct HealthSyncSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    private var state: HealthSyncState { env.healthSyncState }

    var body: some View {
        List {
            if state.connection == .unavailable {
                unavailableSection
            } else {
                statusSection
                typesSection
                aboutSection
            }
        }
        .navigationTitle(String(localized: "healthsync.settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }

    // MARK: - Unavailable

    private var unavailableSection: some View {
        Section {
            Label(String(localized: "healthsync.unavailable"), systemImage: "heart.slash")
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        Section {
            switch state.connection {
            case .notConnected:
                Button {
                    Task { await state.connect() }
                } label: {
                    Label(String(localized: "healthsync.connect"), systemImage: "heart.text.square")
                        .foregroundStyle(Color.accent)
                }
            case .connected:
                LabeledContent {
                    Text(lastSyncText).foregroundStyle(Color.textSecondary)
                } label: {
                    Label(String(localized: "healthsync.connected"), systemImage: "checkmark.seal")
                        .foregroundStyle(Color.textPrimary)
                }
                Button {
                    Task { await state.syncNow() }
                } label: {
                    Label(
                        String(localized: state.isSyncing ? "healthsync.syncing" : "healthsync.sync_now"),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .foregroundStyle(Color.accent)
                }
                .disabled(state.isSyncing)
                Button(role: .destructive) {
                    state.disconnect()
                } label: {
                    Label(String(localized: "healthsync.disconnect"), systemImage: "xmark.circle")
                }
            case .unavailable:
                EmptyView()
            }

            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.bodySmall)
                    .foregroundStyle(Color.outRange)
            }
        } header: {
            Text(String(localized: "healthsync.section.title"))
        } footer: {
            if state.connection == .connected {
                Text(String(localized: "healthsync.disconnect.hint"))
            }
        }
    }

    // MARK: - Per-type toggles

    private var typesSection: some View {
        Section {
            ForEach(HealthMetricType.allCases) { type in
                Toggle(
                    label(for: type),
                    isOn: Binding(
                        get: { state.isEnabled(type) },
                        set: { state.setEnabled(type, $0) }
                    )
                )
                .tint(Color.accent)
            }
        } header: {
            Text(String(localized: "healthsync.types.header"))
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            Text(String(localized: "healthsync.about"))
                .font(.bodySmall)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Helpers

    private func label(for type: HealthMetricType) -> String {
        switch type {
        case .weight:               return String(localized: "healthsync.type.weight")
        case .bloodPressure:        return String(localized: "healthsync.type.bloodPressure")
        case .restingHeartRate:     return String(localized: "healthsync.type.restingHeartRate")
        case .heartRateVariability: return String(localized: "healthsync.type.heartRateVariability")
        case .heartRate:            return String(localized: "healthsync.type.heartRate")
        }
    }

    private var lastSyncText: String {
        guard let date = state.lastSyncDate else {
            return String(localized: "healthsync.never")
        }
        return date.formatted(.relative(presentation: .named))
    }
}
