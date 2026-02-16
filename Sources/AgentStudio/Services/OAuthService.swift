import AppKit
import AuthenticationServices
import os.log

private let oauthLogger = Logger(subsystem: "com.agentstudio", category: "OAuthService")

/// Supported OAuth providers.
enum OAuthProvider: String, CaseIterable {
    case github
    case google
}

/// OAuth authentication service using ASWebAuthenticationSession.
///
/// Opens the user's default browser for authentication and receives the
/// authorization code via the `agentstudio://oauth/callback` URL scheme.
/// Uses non-ephemeral sessions so SSO cookies are preserved — if the user
/// is already logged in, authentication completes with zero typing.
///
/// Client IDs are placeholders until OAuth apps are registered on GitHub/Google.
@MainActor
final class OAuthService: NSObject {

    /// Callback URL scheme registered in Info.plist.
    nonisolated static let callbackScheme = "agentstudio"

    /// Callback path used for OAuth redirects.
    nonisolated static let callbackPath = "/oauth/callback"

    /// Full redirect URI for OAuth provider configuration.
    nonisolated static func redirectURI(for provider: OAuthProvider) -> String {
        "\(callbackScheme)://oauth/callback"
    }

    // MARK: - Provider Configuration

    struct ProviderConfig: Sendable {
        let authorizeURL: String
        let clientId: String
        let scopes: [String]
    }

    /// Provider configurations. Client IDs are placeholders — replace with real
    /// values after registering OAuth apps on GitHub and Google.
    nonisolated static let providerConfigs: [OAuthProvider: ProviderConfig] = [
        .github: ProviderConfig(
            authorizeURL: "https://github.com/login/oauth/authorize",
            clientId: "PLACEHOLDER_GITHUB_CLIENT_ID",
            scopes: ["user", "repo"]
        ),
        .google: ProviderConfig(
            authorizeURL: "https://accounts.google.com/o/oauth2/v2/auth",
            clientId: "PLACEHOLDER_GOOGLE_CLIENT_ID",
            scopes: ["openid", "email", "profile"]
        ),
    ]

    // MARK: - State

    private var activeSession: ASWebAuthenticationSession?

    // MARK: - Authenticate

    /// Start an OAuth authentication flow for the given provider.
    ///
    /// Opens the user's default browser to the provider's authorization page.
    /// Returns the authorization code from the callback URL on success.
    ///
    /// - Parameters:
    ///   - provider: The OAuth provider to authenticate with.
    ///   - window: The parent window for the authentication session.
    /// - Returns: The authorization code string.
    /// - Throws: `OAuthError` on failure or cancellation.
    func authenticate(provider: OAuthProvider, window: NSWindow) async throws -> String {
        guard let config = Self.providerConfigs[provider] else {
            throw OAuthError.unsupportedProvider
        }

        // Reject placeholder client IDs — real values must be configured first
        guard !config.clientId.hasPrefix("PLACEHOLDER") else {
            throw OAuthError.notConfigured(provider)
        }

        // Build the authorization URL with required parameters
        let state = UUID().uuidString
        var components = URLComponents(string: config.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI(for: provider)),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "response_type", value: "code"),
        ]

        guard let authURL = components.url else {
            throw OAuthError.invalidURL
        }

        oauthLogger.info("Starting OAuth flow for \(provider.rawValue)")

        // Bridge the completion-handler API to async/await
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme
            ) { callbackURL, error in
                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        oauthLogger.info("OAuth cancelled by user for \(provider.rawValue)")
                        continuation.resume(throwing: OAuthError.cancelled)
                    } else {
                        oauthLogger.error("OAuth error for \(provider.rawValue): \(error.localizedDescription)")
                        continuation.resume(throwing: OAuthError.sessionFailed(error))
                    }
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    oauthLogger.error("OAuth callback missing authorization code for \(provider.rawValue)")
                    continuation.resume(throwing: OAuthError.missingCode)
                    return
                }

                // Verify state parameter to prevent CSRF
                let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
                if returnedState != state {
                    oauthLogger.error("OAuth state mismatch for \(provider.rawValue) — possible CSRF attack")
                    continuation.resume(throwing: OAuthError.stateMismatch)
                    return
                }

                oauthLogger.info("OAuth succeeded for \(provider.rawValue)")
                continuation.resume(returning: code)
            }

            // Keep SSO cookies — if user is already logged in, auth completes instantly
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self

            self.activeSession = session

            if !session.start() {
                oauthLogger.error("Failed to start OAuth session for \(provider.rawValue)")
                continuation.resume(throwing: OAuthError.startFailed)
            }
        }
    }

    /// Cancel any active authentication session.
    func cancel() {
        activeSession?.cancel()
        activeSession = nil
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return the key window, or fall back to any available window
        NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }
}

// MARK: - OAuthError

enum OAuthError: Error, LocalizedError {
    case unsupportedProvider
    case notConfigured(OAuthProvider)
    case invalidURL
    case cancelled
    case sessionFailed(Error)
    case missingCode
    case stateMismatch
    case startFailed

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider: return "Unsupported OAuth provider"
        case .notConfigured(let provider): return "\(provider.rawValue) OAuth is not configured — register an OAuth app and set the client ID"
        case .invalidURL: return "Failed to construct authorization URL"
        case .cancelled: return "Authentication was cancelled"
        case .sessionFailed(let error): return "Authentication failed: \(error.localizedDescription)"
        case .missingCode: return "Authorization code not found in callback"
        case .stateMismatch: return "OAuth state parameter mismatch (possible CSRF attack)"
        case .startFailed: return "Failed to start authentication session"
        }
    }
}
