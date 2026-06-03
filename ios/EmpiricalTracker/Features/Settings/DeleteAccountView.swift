import Account
import Core
import SwiftUI

/// Type-to-confirm account deletion (Apple Guideline 5.1.1(v) / GDPR Art. 17).
/// Presented as a sheet from Settings. The user must type the literal word
/// `DELETE` before the destructive action unlocks; on success the account and
/// all its data are erased server-side and the local session is cleared.
struct DeleteAccountView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    /// The fixed token the user must type. Intentionally not localized so the
    /// confirmation gesture is unambiguous and matches the repository contract.
    private let confirmationWord = "DELETE"

    @State private var typed = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var canDelete: Bool {
        typed.trimmingCharacters(in: .whitespaces) == confirmationWord && !isDeleting
    }

    var body: some View {
        NavigationStack {
            List {
                warningSection
                confirmSection
                deleteSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "settings.account.delete.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                        .foregroundStyle(Color.accent)
                        .disabled(isDeleting)
                }
            }
            .alert(
                String(localized: "settings.account.delete.error.title"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(isDeleting)
    }

    // MARK: - Sections

    private var warningSection: some View {
        Section {
            Label {
                Text(String(localized: "settings.account.delete.warning"))
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.outRange)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var confirmSection: some View {
        Section {
            TextField(confirmationWord, text: $typed)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .disabled(isDeleting)
                .accessibilityLabel(String(localized: "settings.account.delete.field.a11y"))
        } footer: {
            Text(String(localized: "settings.account.delete.prompt"))
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                performDelete()
            } label: {
                HStack {
                    Text(String(localized: "settings.account.delete.confirm"))
                    if isDeleting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!canDelete)
            .accessibilityHint(String(localized: "settings.account.delete.confirm.hint"))
        }
    }

    // MARK: - Action

    private func performDelete() {
        isDeleting = true
        Task {
            do {
                try await env.account.deleteAccount(confirmation: confirmationWord)
                // Erasure succeeded — drop the local session so the app returns to
                // the auth screen. env.signOut never throws, always clears locally,
                // and also resets the health-data consent flag for this device.
                await env.signOut()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isDeleting = false
            }
        }
    }
}

#Preview {
    DeleteAccountView()
        .environment(AppEnvironment.preview())
}
