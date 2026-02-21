import Testing
import Foundation

@testable import AgentStudio

/// Tests for OAuthService configuration, URL construction, and error types.
/// Note: Actual ASWebAuthenticationSession flows require a running app
/// and are verified via visual testing.
@Suite(.serialized)
struct OAuthServiceTests {

    // MARK: - Provider Configuration


    @Test
    func test_githubConfigExists() {
        let config = OAuthService.providerConfigs[.github]!
        #expect(config.authorizeURL.contains("github.com"))
        #expect(!config.clientId.isEmpty)
        #expect(!config.scopes.isEmpty)
    }


    @Test
    func test_googleConfigExists() {
        let config = OAuthService.providerConfigs[.google]!
        #expect(config.authorizeURL.contains("accounts.google.com"))
        #expect(!config.clientId.isEmpty)
        #expect(!config.scopes.isEmpty)
    }

    // MARK: - Redirect URI


    @Test
    func test_redirectURI_github() {
        let uri = OAuthService.redirectURI(for: .github)
        #expect(uri == "agentstudio://oauth/callback")
    }


    @Test
    func test_redirectURI_google() {
        let uri = OAuthService.redirectURI(for: .google)
        #expect(uri == "agentstudio://oauth/callback")
    }

    // MARK: - Callback Scheme


    @Test
    func test_callbackScheme() {
        #expect(OAuthService.callbackScheme == "agentstudio")
    }


    @Test
    func test_callbackPath() {
        #expect(OAuthService.callbackPath == "/oauth/callback")
    }

    // MARK: - Authorization URL Construction


    @Test
    func test_githubAuthURL_containsRequiredParams() {
        let config = OAuthService.providerConfigs[.github]!
        var components = URLComponents(string: config.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: OAuthService.redirectURI(for: .github)),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: "test-state"),
            URLQueryItem(name: "response_type", value: "code"),
        ]

        let url = components.url!
        let query = url.query!
        #expect(query.contains("client_id="))
        #expect(query.contains("redirect_uri="))
        #expect(query.contains("scope="))
        #expect(query.contains("state=test-state"))
        #expect(query.contains("response_type=code"))
    }


    @Test
    func test_googleAuthURL_containsRequiredParams() {
        let config = OAuthService.providerConfigs[.google]!
        var components = URLComponents(string: config.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: OAuthService.redirectURI(for: .google)),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: "test-state"),
            URLQueryItem(name: "response_type", value: "code"),
        ]

        let url = components.url!
        let query = url.query!
        #expect(query.contains("client_id="))
        #expect(query.contains("redirect_uri="))
        #expect(query.contains("scope="))
        #expect(query.contains("state=test-state"))
        #expect(query.contains("response_type=code"))
    }

    // MARK: - OAuth Provider


    @Test
    func test_allProviders() {
        #expect(OAuthProvider.allCases.count == 2)
        #expect(OAuthProvider.allCases.contains(.github))
        #expect(OAuthProvider.allCases.contains(.google))
    }

    // MARK: - OAuthError


    @Test
    func test_errorDescriptions() {
        #expect(OAuthError.unsupportedProvider.errorDescription != nil)
        #expect(OAuthError.invalidURL.errorDescription != nil)
        #expect(OAuthError.cancelled.errorDescription != nil)
        #expect(OAuthError.missingCode.errorDescription != nil)
        #expect(OAuthError.invalidCallback.errorDescription != nil)
        #expect(OAuthError.stateMismatch.errorDescription != nil)
        #expect(OAuthError.startFailed.errorDescription != nil)
    }


    @Test
    func test_cancelledError_description() {
        let error = OAuthError.cancelled
        #expect(error.errorDescription == "Authentication was cancelled")
    }


    @Test
    func test_stateMismatchError_description() {
        let error = OAuthError.stateMismatch
        #expect( (error.errorDescription?.contains("CSRF") ?? false) )
    }


    @Test
    func test_invalidCallbackError_description() {
        let error = OAuthError.invalidCallback
        #expect( (error.errorDescription?.contains("callback") ?? false) )
    }

    // MARK: - isCancelled


    @Test
    func test_isCancelled_true_forCancelled() {
        #expect(OAuthError.cancelled.isCancelled)
    }


    @Test
    func test_isCancelled_false_forOtherErrors() {
        #expect(!OAuthError.unsupportedProvider.isCancelled)
        #expect(!OAuthError.invalidURL.isCancelled)
        #expect(!OAuthError.missingCode.isCancelled)
        #expect(!OAuthError.invalidCallback.isCancelled)
        #expect(!OAuthError.stateMismatch.isCancelled)
        #expect(!OAuthError.startFailed.isCancelled)
    }


    @Test
    func test_isCancelled_false_forSessionFailed() {
        let inner = NSError(domain: "test", code: 0)
        #expect(!OAuthError.sessionFailed(inner).isCancelled)
    }

    // MARK: - SessionFailed wraps inner error


    @Test
    func test_sessionFailed_includesInnerErrorDescription() {
        let inner = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "connection lost"])
        let error = OAuthError.sessionFailed(inner)
        #expect( (error.errorDescription?.contains("connection lost") ?? false) )
    }

    // MARK: - Callback Validation (Security)

    @Test
    func test_validateCallback_validURL_returnsCode() throws {
        let url = URL(string: "agentstudio://oauth/callback?code=abc123&state=expected-state")!
        let code = try OAuthService.validateCallback(url: url, expectedState: "expected-state")
        #expect(code == "abc123")
    }


    @Test
    func test_validateCallback_wrongHost_throwsInvalidCallback() {
        let url = URL(string: "agentstudio://evil/callback?code=abc123&state=s")!
        do {
            _ = try OAuthService.validateCallback(url: url, expectedState: "s")
            Issue.record("Expected invalidCallback, got no error")
        } catch let error {
            guard case OAuthError.invalidCallback = error else {
                Issue.record("Expected invalidCallback, got \(error)")
                return
            }
        }
    }


    @Test
    func test_validateCallback_wrongPath_throwsInvalidCallback() {
        let url = URL(string: "agentstudio://oauth/evil?code=abc123&state=s")!
        do {
            _ = try OAuthService.validateCallback(url: url, expectedState: "s")
            Issue.record("Expected invalidCallback, got no error")
        } catch let error {
            guard case OAuthError.invalidCallback = error else {
                Issue.record("Expected invalidCallback, got \(error)")
                return
            }
        }
    }


    @Test
    func test_validateCallback_missingCode_throwsMissingCode() {
        let url = URL(string: "agentstudio://oauth/callback?state=s")!
        do {
            _ = try OAuthService.validateCallback(url: url, expectedState: "s")
            Issue.record("Expected missingCode, got no error")
        } catch let error {
            guard case OAuthError.missingCode = error else {
                Issue.record("Expected missingCode, got \(error)")
                return
            }
        }
    }


    @Test
    func test_validateCallback_emptyCode_throwsMissingCode() {
        let url = URL(string: "agentstudio://oauth/callback?code=&state=s")!
        do {
            _ = try OAuthService.validateCallback(url: url, expectedState: "s")
            Issue.record("Expected missingCode, got no error")
        } catch let error {
            guard case OAuthError.missingCode = error else {
                Issue.record("Expected missingCode, got \(error)")
                return
            }
        }
    }


    @Test
    func test_validateCallback_stateMismatch_throwsStateMismatch() {
        let url = URL(string: "agentstudio://oauth/callback?code=abc123&state=wrong")!
        do {
            _ = try OAuthService.validateCallback(url: url, expectedState: "expected")
            Issue.record("Expected stateMismatch, got no error")
        } catch let error {
            guard case OAuthError.stateMismatch = error else {
                Issue.record("Expected stateMismatch, got \(error)")
                return
            }
        }
    }


    @Test
    func test_validateCallback_missingState_throwsStateMismatch() {
        let url = URL(string: "agentstudio://oauth/callback?code=abc123")!
        do {
            _ = try OAuthService.validateCallback(url: url, expectedState: "expected")
            Issue.record("Expected stateMismatch, got no error")
        } catch let error {
            guard case OAuthError.stateMismatch = error else {
                Issue.record("Expected stateMismatch, got \(error)")
                return
            }
        }
    }


    @Test
    func test_validateCallback_extraPathSegment_throwsInvalidCallback() {
        let url = URL(string: "agentstudio://oauth/callback/extra?code=abc123&state=s")!
        do {
            _ = try OAuthService.validateCallback(url: url, expectedState: "s")
            Issue.record("Expected invalidCallback, got no error")
        } catch let error {
            guard case OAuthError.invalidCallback = error else {
                Issue.record("Expected invalidCallback, got \(error)")
                return
            }
        }
    }

    // MARK: - Placeholder Validation


    @Test
    func test_githubClientId_isPlaceholder() {
        // Current config uses placeholders — this test documents that OAuth
        // won't work until real client IDs are configured.
        let config = OAuthService.providerConfigs[.github]!
        #expect(config.clientId.hasPrefix("PLACEHOLDER"))
    }


    @Test
    func test_googleClientId_isPlaceholder() {
        let config = OAuthService.providerConfigs[.google]!
        #expect(config.clientId.hasPrefix("PLACEHOLDER"))
    }


    @Test
    func test_notConfigured_errorDescription_includesProvider() {
        let error = OAuthError.notConfigured(.github)
        #expect(error.errorDescription != nil)
        guard let description = error.errorDescription else {
            return
        }
        #expect(description.contains("github"))
        #expect(description.contains("not configured"))
    }


    @Test
    func test_notConfigured_isCancelled_returnsFalse() {
        #expect(!OAuthError.notConfigured(.github).isCancelled)
    }
}
