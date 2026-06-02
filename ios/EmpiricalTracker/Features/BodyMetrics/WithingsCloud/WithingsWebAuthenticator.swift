import AuthenticationServices
import Foundation
import UIKit

/// Abstraction over `ASWebAuthenticationSession` so `WithingsCloudState` can drive the
/// Withings OAuth consent flow without owning UIKit directly, and so previews/tests can
/// substitute a stub. Sprint 10, ADR-023.
@MainActor
protocol WithingsWebAuthenticating {
    /// Presents `url` in a secure, isolated web session and resolves with the redirect
    /// URL the backend bounces back to (the app's custom scheme). Throws
    /// `WithingsAuthError.cancelled` if the user dismisses the sheet.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

enum WithingsAuthError: LocalizedError {
    case cancelled
    case cannotStart

    var errorDescription: String? {
        switch self {
        case .cancelled:  return String(localized: "withings.error.cancelled")
        case .cannotStart: return String(localized: "withings.error.cannot_start")
        }
    }
}

/// Production implementation wrapping `ASWebAuthenticationSession`. The session presents
/// the Withings consent page; on success Withings redirects to the backend
/// `/withings/callback`, which exchanges the code for tokens and then redirects to the
/// app's `empiricaltracker://withings` scheme — which is what this session captures.
@MainActor
final class WithingsWebAuthenticator: NSObject, WithingsWebAuthenticating {

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let asError = error as? ASWebAuthenticationSessionError,
                          asError.code == .canceledLogin {
                    continuation.resume(throwing: WithingsAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? WithingsAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            // Use the system browser's existing Withings login if present, rather than
            // forcing a fresh ephemeral session.
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: WithingsAuthError.cannotStart)
            }
        }
    }
}

extension WithingsWebAuthenticator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
