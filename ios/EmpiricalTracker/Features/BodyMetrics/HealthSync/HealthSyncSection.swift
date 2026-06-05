import Core
import HealthSync
import SwiftUI

/// The Apple Health card at the top of the Body tab (Sprint 9, ADR-022).
///
/// Renders the connect CTA, or — once connected — the last-sync line, a "Sync now"
/// action, and the most recent import summary. Hidden entirely when HealthKit is
/// unavailable so a device without Health shows no dead control. Withings data
/// arrives here via the user's Health Mate app writing to Apple Health.
struct HealthSyncSection: View {
    /// Read-only here (no `$` bindings); Observation still tracks property reads in `body`.
    let state: HealthSyncState

    @State private var showingResetConfirmation = false

    var body: some View {
        if state.connection != .unavailable {
            Section {
                switch state.connection {
                case .notConnected: connectRow
                case .connected:     connectedRows
                case .unavailable:   EmptyView()
                }
            } header: {
                Text(String(localized: "healthsync.section.title"))
            } footer: {
                if state.connection == .connected {
                    Text(String(localized: "healthsync.privacy"))
                        .font(.bodySmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    // MARK: - Not connected

    private var connectRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "healthsync.connect.subtitle"))
                .font(.bodySmall)
                .foregroundStyle(Color.textSecondary)
            Button {
                Task { await state.connect() }
            } label: {
                Label(String(localized: "healthsync.connect"), systemImage: "heart.text.square")
                    .font(.headlineSmall)
            }
            .buttonStyle(.borderedProminent)
            if let error = state.errorMessage {
                errorLabel(error)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Connected

    @ViewBuilder
    private var connectedRows: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.text.square.fill")
                .foregroundStyle(Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "healthsync.connected"))
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
                String(localized: state.isSyncing ? "healthsync.syncing" : "healthsync.sync_now"),
                systemImage: "arrow.triangle.2.circlepath"
            )
            .foregroundStyle(Color.accent)
        }
        .disabled(state.isSyncing)

        Button(role: .destructive) {
            showingResetConfirmation = true
        } label: {
            Label("Clear data & re-sync", systemImage: "trash.circle")
        }
        .disabled(state.isSyncing)
        .confirmationDialog(
            "Clear all Apple Health data?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear & Re-sync", role: .destructive) {
                Task { await state.resetAndResync() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All health-synced readings will be deleted from your account and re-imported fresh from Apple Health.")
        }

        if let summary = state.lastSummary, state.errorMessage == nil {
            Text(summaryText(summary))
                .font(.bodySmall)
                .foregroundStyle(Color.textMuted)
        }

        if let error = state.errorMessage {
            errorLabel(error)
        }
    }

    // MARK: - Helpers

    private var lastSyncText: String {
        guard let date = state.lastSyncDate else {
            return String(localized: "healthsync.never")
        }
        let relative = date.formatted(.relative(presentation: .named))
        return String(format: String(localized: "healthsync.last_sync"), relative)
    }

    private func summaryText(_ summary: HealthSyncManager.SyncSummary) -> String {
        if summary.isEmpty {
            return String(localized: "healthsync.no_new")
        }
        return String(
            format: String(localized: "healthsync.summary"),
            summary.weight, summary.bloodPressure
        )
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.bodySmall)
            .foregroundStyle(Color.outRange)
    }
}
