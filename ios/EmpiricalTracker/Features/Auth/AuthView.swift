import SwiftUI
import Core
import Auth

/// Login screen. Mirrors `/login` on the web app.
/// Supports email/password sign-in + a debug-only "Demo mode" shortcut.
struct AuthView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm = SignInViewModel()
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                headerSection
                formCard
                #if DEBUG
                demoButton
                #endif
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgBase)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 64))
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)
            Text(String(localized: "auth.title"))
                .font(.displayMedium)
                .foregroundStyle(Color.textPrimary)
            Text(String(localized: "auth.subtitle"))
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 48)
    }

    // MARK: - Form

    private var formCard: some View {
        CardView {
            VStack(spacing: 20) {
                emailField
                passwordField
                errorBanner
                signInButton
            }
        }
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "auth.field.email"))
                .font(.labelLarge)
                .foregroundStyle(Color.textSecondary)
            TextField(String(localized: "auth.field.email.placeholder"), text: $vm.email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focus, equals: .email)
                .submitLabel(.next)
                .onSubmit { focus = .password }
                .fieldStyle()
                .accessibilityLabel(String(localized: "auth.field.email"))
            if let hint = vm.emailFieldError {
                Text(hint)
                    .font(.bodySmall)
                    .foregroundStyle(Color.outRange)
            }
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "auth.field.password"))
                .font(.labelLarge)
                .foregroundStyle(Color.textSecondary)
            SecureField(String(localized: "auth.field.password.placeholder"), text: $vm.password)
                .textContentType(.password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { submit() }
                .fieldStyle()
                .accessibilityLabel(String(localized: "auth.field.password"))
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = env.authStore.error {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.outRange)
                Text(error.localizedDescription)
                    .font(.bodySmall)
                    .foregroundStyle(Color.outRange)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.outRange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(error.localizedDescription)
        }
    }

    private var signInButton: some View {
        Button { submit() } label: {
            ZStack {
                if env.authStore.isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Text(String(localized: "auth.sign_in"))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!vm.isValidForm || env.authStore.isLoading)
        .animation(.easeOut(duration: 0.15), value: env.authStore.isLoading)
        .accessibilityLabel(String(localized: "auth.sign_in"))
        .accessibilityHint(String(localized: "auth.sign_in.hint"))
    }

    // MARK: - Demo (debug only)

    private var demoButton: some View {
        Button {
            Task { await env.authStore.signIn(email: "demo@empirical.app", password: "demo1234") }
        } label: {
            Text(String(localized: "auth.demo"))
                .font(.bodyMedium)
                .foregroundStyle(Color.accent)
        }
        .disabled(env.authStore.isLoading)
        .accessibilityLabel(String(localized: "auth.demo.a11y"))
    }

    // MARK: - Actions

    private func submit() {
        guard vm.isValidForm, !env.authStore.isLoading else { return }
        focus = nil
        Task { await env.authStore.signIn(email: vm.email, password: vm.password) }
    }
}

// MARK: - Field modifier

private extension View {
    func fieldStyle() -> some View {
        self
            .padding(12)
            .background(Color.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview("Sign in") {
    AuthView()
        .environment(AppEnvironment.preview())
}

#Preview("Sign in — loading") {
    let env = AppEnvironment.preview()
    // Simulate loading state
    AuthView()
        .environment(env)
}
