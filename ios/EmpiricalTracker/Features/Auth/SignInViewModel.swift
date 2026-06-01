import Foundation
import Observation

/// Local form state for `AuthView`. Kept outside `AuthStore` so the store
/// stays free of UI concerns and is testable without SwiftUI.
@MainActor
@Observable
final class SignInViewModel {
    var email: String = ""
    var password: String = ""

    var isValidForm: Bool {
        email.contains("@") && password.count >= 6
    }

    var emailFieldError: String? {
        guard !email.isEmpty && !email.contains("@") else { return nil }
        return String(localized: "auth.field.email.invalid")
    }
}
