import SwiftUI
import Core

/// Health-data consent gate, shown after sign-in and before the main app the
/// first time a user reaches it (and again whenever the consent version is
/// bumped). Captures the explicit, affirmative consent GDPR requires for
/// processing special-category (health) data, and surfaces the privacy policy
/// and terms inline.
///
/// Declining signs the user back out — the app does not process health data
/// without consent.
struct ConsentView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var openURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                points
                legalLinks
                actions
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgBase)
        .sheet(item: $openURL) { url in
            SafariSheet(url: url)
                .ignoresSafeArea()
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)
            Text(String(localized: "consent.title"))
                .font(.displayMedium)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            Text(String(localized: "consent.subtitle"))
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var points: some View {
        CardView {
            VStack(alignment: .leading, spacing: 18) {
                point(
                    icon: "heart.text.square",
                    title: String(localized: "consent.point.health.title"),
                    body: String(localized: "consent.point.health.body")
                )
                point(
                    icon: "lock.shield",
                    title: String(localized: "consent.point.storage.title"),
                    body: String(localized: "consent.point.storage.body")
                )
                point(
                    icon: "person.crop.circle.badge.xmark",
                    title: String(localized: "consent.point.rights.title"),
                    body: String(localized: "consent.point.rights.body")
                )
                point(
                    icon: "stethoscope",
                    title: String(localized: "consent.point.notmedical.title"),
                    body: String(localized: "consent.point.notmedical.body")
                )
            }
        }
    }

    private func point(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.labelLarge)
                    .foregroundStyle(Color.textPrimary)
                Text(body)
                    .font(.bodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var legalLinks: some View {
        VStack(spacing: 12) {
            Button {
                openURL = Legal.privacyPolicyURL
            } label: {
                Label(String(localized: "legal.privacy_policy"), systemImage: "doc.text")
            }
            Button {
                openURL = Legal.termsOfServiceURL
            } label: {
                Label(String(localized: "legal.terms"), systemImage: "doc.plaintext")
            }
        }
        .font(.bodyMedium)
        .tint(Color.accent)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                env.consent.accept()
            } label: {
                Text(String(localized: "consent.agree"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityHint(String(localized: "consent.agree.hint"))

            Button(role: .cancel) {
                Task { await env.signOut() }
            } label: {
                Text(String(localized: "consent.decline"))
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
            }
            .accessibilityHint(String(localized: "consent.decline.hint"))
        }
    }
}

#Preview {
    ConsentView()
        .environment(AppEnvironment.preview())
}
