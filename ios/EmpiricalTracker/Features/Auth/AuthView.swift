import SwiftUI
import Core
import AppAuth

/// Login screen. Mirrors `/login` on the web app.
/// Supports email/password sign-in, in-app account creation (toggle to "Create
/// account"), and a debug-only "Demo mode" shortcut. New sign-ups flow into the
/// `ConsentView` gate before the main app (see `RootView`).
struct AuthView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm = SignInViewModel()
    @State private var legalURL: URL?
    @State private var isSampleExplorePresented = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email, password, confirmPassword }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                headerSection
                formCard
                modeToggle
                sampleDataButton
                #if DEBUG
                demoButton
                #endif
                legalFooter
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgBase)
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $legalURL) { url in
            SafariSheet(url: url)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isSampleExplorePresented) {
            SampleDataExploreView()
        }
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
                if vm.mode == .signUp {
                    confirmPasswordField
                }
                errorBanner
                noticeBanner
                primaryButton
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
                .textContentType(vm.mode == .signUp ? .newPassword : .password)
                .focused($focus, equals: .password)
                .submitLabel(vm.mode == .signUp ? .next : .go)
                .onSubmit {
                    if vm.mode == .signUp { focus = .confirmPassword } else { submit() }
                }
                .fieldStyle()
                .accessibilityLabel(String(localized: "auth.field.password"))
            if vm.mode == .signUp {
                Text(String(localized: "auth.field.password.requirement"))
                    .font(.bodySmall)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    @ViewBuilder
    private var confirmPasswordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "auth.field.confirm_password"))
                .font(.labelLarge)
                .foregroundStyle(Color.textSecondary)
            SecureField(String(localized: "auth.field.confirm_password.placeholder"),
                        text: $vm.confirmPassword)
                .textContentType(.newPassword)
                .focused($focus, equals: .confirmPassword)
                .submitLabel(.go)
                .onSubmit { submit() }
                .fieldStyle()
                .accessibilityLabel(String(localized: "auth.field.confirm_password"))
            if let hint = vm.confirmPasswordError {
                Text(hint)
                    .font(.bodySmall)
                    .foregroundStyle(Color.outRange)
            }
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

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = env.authStore.notice {
            HStack(spacing: 8) {
                Image(systemName: "envelope.circle.fill")
                    .foregroundStyle(Color.accent)
                Text(notice)
                    .font(.bodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(notice)
        }
    }

    private var primaryButton: some View {
        Button { submit() } label: {
            ZStack {
                if env.authStore.isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Text(primaryButtonTitle)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!vm.isValidForm || env.authStore.isLoading)
        .animation(.easeOut(duration: 0.15), value: env.authStore.isLoading)
        .accessibilityLabel(primaryButtonTitle)
        .accessibilityHint(String(localized: vm.mode == .signUp ? "auth.sign_up.hint" : "auth.sign_in.hint"))
    }

    private var primaryButtonTitle: String {
        String(localized: vm.mode == .signUp ? "auth.sign_up" : "auth.sign_in")
    }

    // MARK: - Mode toggle

    /// Switches the form between signing in and creating an account. A plain text
    /// link (matching the legal/demo links) rather than a new design-system primitive.
    private var modeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                vm.toggleMode()
                env.authStore.clearMessages()
                focus = nil
            }
        } label: {
            Text(String(localized: vm.mode == .signUp
                        ? "auth.toggle.have_account"
                        : "auth.toggle.no_account"))
                .font(.bodyMedium)
                .foregroundStyle(Color.accent)
                .multilineTextAlignment(.center)
        }
        .accessibilityLabel(String(localized: vm.mode == .signUp
                                   ? "auth.toggle.have_account.a11y"
                                   : "auth.toggle.no_account.a11y"))
    }

    // MARK: - Sample data

    /// Lets a visitor browse a seeded dashboard before committing to an account —
    /// the value proposition shown, not described. Entirely local; see
    /// `SampleDataExploreView`.
    private var sampleDataButton: some View {
        Button {
            isSampleExplorePresented = true
        } label: {
            Label(String(localized: "auth.sample"), systemImage: "sparkles")
                .font(.bodyMedium)
                .foregroundStyle(Color.accent)
        }
        .accessibilityLabel(String(localized: "auth.sample.a11y"))
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

    // MARK: - Legal

    /// Privacy policy + terms links. A privacy-policy link on the auth screen is
    /// expected for a HealthKit app and reachable before the user signs in.
    private var legalFooter: some View {
        VStack(spacing: 6) {
            Text(String(localized: vm.mode == .signUp
                        ? "auth.legal.preamble.sign_up"
                        : "auth.legal.preamble"))
                .font(.bodySmall)
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button(String(localized: "legal.privacy_policy")) {
                    legalURL = Legal.privacyPolicyURL
                }
                Button(String(localized: "legal.terms")) {
                    legalURL = Legal.termsOfServiceURL
                }
            }
            .font(.bodySmall)
            .tint(Color.accent)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func submit() {
        guard vm.isValidForm, !env.authStore.isLoading else { return }
        focus = nil
        let email = vm.email
        let password = vm.password
        switch vm.mode {
        case .signIn:
            Task { await env.authStore.signIn(email: email, password: password) }
        case .signUp:
            Task { @MainActor in
                await env.authStore.signUp(email: email, password: password)
                // If the project requires email confirmation, no session is issued —
                // drop the user back to sign-in so they can log in once confirmed.
                // (When confirmation is off, `session` is set and RootView advances
                // to the consent gate before this runs.)
                if env.authStore.notice != nil {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.mode = .signIn
                        vm.confirmPassword = ""
                    }
                }
            }
        }
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
