import Biomarkers
import Core
import SwiftUI
import UserNotifications

/// Settings section for the opt-in local reminders: the daily meal-log nudge, the
/// morning weigh-in, and the one-shot "~3 months since your last panel" lab-cadence
/// nudge. Toggling a reminder on requests notification permission; if the user has
/// denied it system-wide, the toggle reverts and an alert points to iOS Settings.
struct ReminderSettingsSection: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showDeniedAlert = false

    var body: some View {
        @Bindable var prefs = env.reminders

        Section {
            Toggle(isOn: $prefs.mealReminderEnabled) {
                Label(String(localized: "settings.reminders.meal"), systemImage: "fork.knife")
                    .foregroundStyle(Color.textPrimary)
            }
            .onChange(of: prefs.mealReminderEnabled) { _, isOn in handleToggle(isOn) }
            // Anchor the lab nudge to the real latest panel when it's enabled here.
            .task {
                if env.biomarkers.panels.isEmpty {
                    await env.biomarkers.loadPanels()
                }
            }
            .alert(
                String(localized: "settings.reminders.denied.title"),
                isPresented: $showDeniedAlert
            ) {
                Button(String(localized: "settings.reminders.denied.open")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings.reminders.denied.message"))
            }

            if prefs.mealReminderEnabled {
                DatePicker(
                    String(localized: "settings.reminders.time"),
                    selection: $prefs.mealReminderTime,
                    displayedComponents: .hourAndMinute
                )
                .onChange(of: prefs.mealReminderMinutes) { resync() }
            }

            Toggle(isOn: $prefs.weightReminderEnabled) {
                Label(String(localized: "settings.reminders.weight"), systemImage: "scalemass")
                    .foregroundStyle(Color.textPrimary)
            }
            .onChange(of: prefs.weightReminderEnabled) { _, isOn in handleToggle(isOn) }

            if prefs.weightReminderEnabled {
                DatePicker(
                    String(localized: "settings.reminders.time"),
                    selection: $prefs.weightReminderTime,
                    displayedComponents: .hourAndMinute
                )
                .onChange(of: prefs.weightReminderMinutes) { resync() }
            }

            Toggle(isOn: $prefs.labReminderEnabled) {
                Label(String(localized: "settings.reminders.lab"), systemImage: "calendar.badge.clock")
                    .foregroundStyle(Color.textPrimary)
            }
            .onChange(of: prefs.labReminderEnabled) { _, isOn in handleToggle(isOn) }
        } header: {
            Text(String(localized: "settings.section.reminders"))
        } footer: {
            Text(String(localized: "settings.reminders.footer"))
        }
    }

    // MARK: - Actions

    /// On enable: ask for permission first; revert the toggle if notifications are
    /// denied system-wide. On disable (or after a granted enable): re-sync schedules.
    private func handleToggle(_ isOn: Bool) {
        Task {
            if isOn {
                let granted = await ReminderScheduler.requestAuthorization()
                guard granted else {
                    // Reverting flips the toggle back; the resulting onChange lands in
                    // the `else` branch below and harmlessly re-syncs.
                    revertAll()
                    showDeniedAlert = true
                    return
                }
            }
            await env.syncReminders()
        }
    }

    private func resync() {
        Task { await env.syncReminders() }
    }

    /// Turns off whichever reminder was just optimistically enabled without permission.
    private func revertAll() {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .denied else { return }
            env.reminders.mealReminderEnabled = false
            env.reminders.weightReminderEnabled = false
            env.reminders.labReminderEnabled = false
        }
    }
}

#Preview {
    List {
        ReminderSettingsSection()
    }
    .environment(AppEnvironment.preview())
}
