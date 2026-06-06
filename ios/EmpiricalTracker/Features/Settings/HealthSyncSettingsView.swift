import Core
import Foundation
import HealthSync
import SwiftUI
import UIKit

/// Settings ▸ Apple Health (Sprint 9, ADR-022). Granular per-type import toggles,
/// connection management, and the disconnect/revoke guidance. Mirrors the Body-tab
/// card's connection state (both read the single `AppEnvironment.healthSyncState`).
struct HealthSyncSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingDisconnectConfirmation = false

    // Access healthSyncState through env directly rather than declaring a local
    // computed property with an explicit HealthSyncState type annotation, which
    // can confuse the compiler when the type is defined in a peer feature folder.

    var body: some View {
        List {
            if env.healthSyncState.connection == .unavailable {
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
            switch env.healthSyncState.connection {
            case .notConnected:
                Button {
                    Task { await env.healthSyncState.connect() }
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
                    Task { await env.healthSyncState.syncNow() }
                } label: {
                    Label(
                        String(localized: env.healthSyncState.isSyncing ? "healthsync.syncing" : "healthsync.sync_now"),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .foregroundStyle(Color.accent)
                }
                .disabled(env.healthSyncState.isSyncing)

                if let summary = env.healthSyncState.lastSummary, !env.healthSyncState.isSyncing,
                   env.healthSyncState.errorMessage == nil {
                    Text(summaryText(summary))
                        .font(.bodySmall)
                        .foregroundStyle(Color.textMuted)
                }

                if env.healthSyncState.showPermissionsHint {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "healthsync.permissions.hint"))
                            .font(.bodySmall)
                            .foregroundStyle(Color.outRange)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label(String(localized: "healthsync.open_health_settings"), systemImage: "gear")
                                .font(.bodySmall)
                                .foregroundStyle(Color.accent)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Button(role: .destructive) {
                    showingDisconnectConfirmation = true
                } label: {
                    Label(String(localized: "healthsync.disconnect"), systemImage: "xmark.circle")
                }
                .confirmationDialog(
                    String(localized: "healthsync.disconnect.confirm.title"),
                    isPresented: $showingDisconnectConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "healthsync.disconnect"), role: .destructive) {
                        env.healthSyncState.disconnect()
                    }
                    Button(String(localized: "Cancel"), role: .cancel) {}
                } message: {
                    Text(String(localized: "healthsync.disconnect.confirm.message"))
                }
            case .unavailable:
                EmptyView()
            }

            if let error = env.healthSyncState.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.bodySmall)
                    .foregroundStyle(Color.outRange)
            }
        } header: {
            Text(String(localized: "healthsync.section.title"))
        } footer: {
            if env.healthSyncState.connection == .connected {
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
                        get: { env.healthSyncState.isEnabled(type) },
                        set: { env.healthSyncState.setEnabled(type, $0) }
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

    private func summaryText(_ summary: HealthSyncManager.SyncSummary) -> String {
        if summary.isEmpty && summary.uploadsFailed == 0 {
            return String(localized: "healthsync.no_new")
        }
        var parts: [String] = []
        if summary.weight > 0              { parts.append("\(summary.weight) weight") }
        if summary.bloodPressure > 0       { parts.append("\(summary.bloodPressure) BP") }
        if summary.restingHeartRate > 0    { parts.append("\(summary.restingHeartRate) resting HR") }
        if summary.heartRateVariability > 0 { parts.append("\(summary.heartRateVariability) HRV") }
        if summary.heartRate > 0           { parts.append("\(summary.heartRate) avg HR") }
        var result = parts.isEmpty ? "No new readings" : "Imported: \(parts.joined(separator: ", "))"
        if summary.uploadsFailed > 0 { result += " · \(summary.uploadsFailed) failed" }
        return result
    }

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
        guard let date = env.healthSyncState.lastSyncDate else {
            return String(localized: "healthsync.never")
        }
        return date.formatted(Date.RelativeFormatStyle(presentation: .named))
    }
}
