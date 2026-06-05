import Foundation
import Observation

/// Local form state for `AuthView`. Kept outside `AuthStore` so the store
/// stays free of UI concerns and is testable without SwiftUI.
@MainActor
@Observable
final class SignInViewModel {

    /// Whether the form is collecting credentials to sign in or to create an account.
    enum Mode: CaseIterable {
        case signIn, signUp
    }

    var mode: Mode = .signIn
    var email: String = ""
    var password: String = ""
    /// Only used in `.signUp` mode — must match `password`.
    var confirmPassword: String = ""

    /// Minimum password length the form enforces locally before hitting the backend.
    /// Supabase's default minimum is 6; keep these in sync.
    static let minPasswordLength = 6

    var isValidForm: Bool {
        let credentialsValid = email.contains("@") && password.count >= Self.minPasswordLength
        switch mode {
        case .signIn:
            return credentialsValid
        case .signUp:
            return credentialsValid && password == confirmPassword
        }
    }

    var emailFieldError: String? {
        guard !email.isEmpty && !email.contains("@") else { return nil }
        return String(localized: "auth.field.email.invalid")
    }

    /// Surfaced under the confirm-password field once the user has typed something
    /// that doesn't match — only in sign-up mode.
    var confirmPasswordError: String? {
        guard mode == .signUp, !confirmPassword.isEmpty, password != confirmPassword else {
            return nil
        }
        return String(localized: "auth.field.confirm_password.mismatch")
    }

    /// Toggles between sign-in and sign-up, resetting the confirm field so a stale
    /// value can't leak between modes.
    func toggleMode() {
        mode = (mode == .signIn) ? .signUp : .signIn
        confirmPassword = ""
    }
}
