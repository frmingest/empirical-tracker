import Core
import SwiftUI

/// The Withings Cloud card on the Body tab (Sprint 10, ADR-023) — Path B, sitting just
/// below the Apple Health card. Renders the "Connect Withings account" CTA, or — once
/// connected — the last-sync line and a "Sync now" action. Hidden entirely until the
/// backend exposes the Withings endpoints (`connection == .unavailable`), so the card
/// never appears as a dead control. Disconnect lives in Settings, matching Apple Health.
struct WithingsCloudSection: View {
    /// Read-only here (no `$` bindings); Observation still tracks property reads in `body`.
    let state: WithingsCloudState

    var body: some View {
        if state.connection != .unavailable {
            Section {
                switch state.connection {
                case .notConnected:           connectRow
                case .connecting:             connectingRow
                case .connected:              connectedRows
                case .unavailable:            EmptyView()
                }
            } header: {
                Text(String(localized: "withings.section.title"))
            } footer: {
                if state.connection == .connected {
                    Text(String(localized: "withings.privacy"))
                        .font(.bodySmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    // MARK: - Not connected

    private var connectRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "withings.connect.subtitle"))
                .font(.bodySmall)
                .foregroundStyle(Color.textSecondary)
            Button {
                Task { await state.connect() }
            } label: {
                Label(String(localized: "withings.connect"), systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headlineSmall)
            }
            .buttonStyle(.borderedProminent)
            if let error = state.errorMessage {
                errorLabel(error)
            }
        }
        .padding(.vertical, 4)
    }

    private var connectingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(String(localized: "withings.connecting"))
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Connected

    @ViewBuilder
    private var connectedRows: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "withings.connected"))
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Text(lastSyncText)
                    .font(.bodySmall)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if state.isSyncing {
                ProgressView()
            }
        }
        .accessibilityElement(children: .combine)

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

        if let error = state.errorMessage {
            errorLabel(error)
        }
    }

    // MARK: - Helpers

    private var lastSyncText: String {
        guard let date = state.lastSyncDate else {
            return String(localized: "withings.never")
        }
        let relative = date.formatted(.relative(presentation: .named))
        return String(format: String(localized: "withings.last_sync"), relative)
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.bodySmall)
            .foregroundStyle(Color.outRange)
    }
}
