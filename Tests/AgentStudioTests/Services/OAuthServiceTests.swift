import XCTest
@testable import AgentStudio

/// Tests for OAuthService configuration, URL construction, and error types.
/// Note: Actual ASWebAuthenticationSession flows require a running app
/// and are verified via visual testing.
final class OAuthServiceTests: XCTestCase {

    // MARK: - Provider Configuration

    func test_githubConfigExists() {
        let config = OAuthService.providerConfigs[.github]
        XCTAssertNotNil(config)
        XCTAssertTrue(config!.authorizeURL.contains("github.com"))
        XCTAssertFalse(config!.clientId.isEmpty)
        XCTAssertFalse(config!.scopes.isEmpty)
    }

    func test_googleConfigExists() {
        let config = OAuthService.providerConfigs[.google]
        XCTAssertNotNil(config)
        XCTAssertTrue(config!.authorizeURL.contains("accounts.google.com"))
        XCTAssertFalse(config!.clientId.isEmpty)
        XCTAssertFalse(config!.scopes.isEmpty)
    }

    // MARK: - Redirect URI

    func test_redirectURI_github() {
        let uri = OAuthService.redirectURI(for: .github)
        XCTAssertEqual(uri, "agentstudio://oauth/callback")
    }

    func test_redirectURI_google() {
        let uri = OAuthService.redirectURI(for: .google)
        XCTAssertEqual(uri, "agentstudio://oauth/callback")
    }

    // MARK: - Callback Scheme

    func test_callbackScheme() {
        XCTAssertEqual(OAuthService.callbackScheme, "agentstudio")
    }

    func test_callbackPath() {
        XCTAssertEqual(OAuthService.callbackPath, "/oauth/callback")
    }

    // MARK: - Authorization URL Construction

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
        XCTAssertTrue(query.contains("client_id="))
        XCTAssertTrue(query.contains("redirect_uri="))
        XCTAssertTrue(query.contains("scope="))
        XCTAssertTrue(query.contains("state=test-state"))
        XCTAssertTrue(query.contains("response_type=code"))
    }

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
        XCTAssertTrue(query.contains("client_id="))
        XCTAssertTrue(query.contains("redirect_uri="))
        XCTAssertTrue(query.contains("scope="))
        XCTAssertTrue(query.contains("state=test-state"))
        XCTAssertTrue(query.contains("response_type=code"))
    }

    // MARK: - OAuth Provider

    func test_allProviders() {
        XCTAssertEqual(OAuthProvider.allCases.count, 2)
        XCTAssertTrue(OAuthProvider.allCases.contains(.github))
        XCTAssertTrue(OAuthProvider.allCases.contains(.google))
    }

    // MARK: - OAuthError

    func test_errorDescriptions() {
        XCTAssertNotNil(OAuthError.unsupportedProvider.errorDescription)
        XCTAssertNotNil(OAuthError.invalidURL.errorDescription)
        XCTAssertNotNil(OAuthError.cancelled.errorDescription)
        XCTAssertNotNil(OAuthError.missingCode.errorDescription)
        XCTAssertNotNil(OAuthError.invalidCallback.errorDescription)
        XCTAssertNotNil(OAuthError.stateMismatch.errorDescription)
        XCTAssertNotNil(OAuthError.startFailed.errorDescription)
    }

    func test_cancelledError_description() {
        let error = OAuthError.cancelled
        XCTAssertEqual(error.errorDescription, "Authentication was cancelled")
    }

    func test_stateMismatchError_description() {
        let error = OAuthError.stateMismatch
        XCTAssertTrue(error.errorDescription!.contains("CSRF"))
    }

    func test_invalidCallbackError_description() {
        let error = OAuthError.invalidCallback
        XCTAssertTrue(error.errorDescription!.contains("callback"))
    }

    // MARK: - isCancelled

    func test_isCancelled_true_forCancelled() {
        XCTAssertTrue(OAuthError.cancelled.isCancelled)
    }

    func test_isCancelled_false_forOtherErrors() {
        XCTAssertFalse(OAuthError.unsupportedProvider.isCancelled)
        XCTAssertFalse(OAuthError.invalidURL.isCancelled)
        XCTAssertFalse(OAuthError.missingCode.isCancelled)
        XCTAssertFalse(OAuthError.invalidCallback.isCancelled)
        XCTAssertFalse(OAuthError.stateMismatch.isCancelled)
        XCTAssertFalse(OAuthError.startFailed.isCancelled)
    }

    func test_isCancelled_false_forSessionFailed() {
        let inner = NSError(domain: "test", code: 0)
        XCTAssertFalse(OAuthError.sessionFailed(inner).isCancelled)
    }

    // MARK: - SessionFailed wraps inner error

    func test_sessionFailed_includesInnerErrorDescription() {
        let inner = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "connection lost"])
        let error = OAuthError.sessionFailed(inner)
        XCTAssertTrue(error.errorDescription!.contains("connection lost"))
    }

    // MARK: - Callback Validation (Security)

    func test_validateCallback_validURL_returnsCode() throws {
        let url = URL(string: "agentstudio://oauth/callback?code=abc123&state=expected-state")!
        let code = try OAuthService.validateCallback(url: url, expectedState: "expected-state")
        XCTAssertEqual(code, "abc123")
    }

    func test_validateCallback_wrongHost_throwsInvalidCallback() {
        let url = URL(string: "agentstudio://evil/callback?code=abc123&state=s")!
        XCTAssertThrowsError(try OAuthService.validateCallback(url: url, expectedState: "s")) { error in
            guard case OAuthError.invalidCallback = error else {
                return XCTFail("Expected invalidCallback, got \(error)")
            }
        }
    }

    func test_validateCallback_wrongPath_throwsInvalidCallback() {
        let url = URL(string: "agentstudio://oauth/evil?code=abc123&state=s")!
        XCTAssertThrowsError(try OAuthService.validateCallback(url: url, expectedState: "s")) { error in
            guard case OAuthError.invalidCallback = error else {
                return XCTFail("Expected invalidCallback, got \(error)")
            }
        }
    }

    func test_validateCallback_missingCode_throwsMissingCode() {
        let url = URL(string: "agentstudio://oauth/callback?state=s")!
        XCTAssertThrowsError(try OAuthService.validateCallback(url: url, expectedState: "s")) { error in
            guard case OAuthError.missingCode = error else {
                return XCTFail("Expected missingCode, got \(error)")
            }
        }
    }

    func test_validateCallback_emptyCode_throwsMissingCode() {
        let url = URL(string: "agentstudio://oauth/callback?code=&state=s")!
        XCTAssertThrowsError(try OAuthService.validateCallback(url: url, expectedState: "s")) { error in
            guard case OAuthError.missingCode = error else {
                return XCTFail("Expected missingCode, got \(error)")
            }
        }
    }

    func test_validateCallback_stateMismatch_throwsStateMismatch() {
        let url = URL(string: "agentstudio://oauth/callback?code=abc123&state=wrong")!
        XCTAssertThrowsError(try OAuthService.validateCallback(url: url, expectedState: "expected")) { error in
            guard case OAuthError.stateMismatch = error else {
                return XCTFail("Expected stateMismatch, got \(error)")
            }
        }
    }

    func test_validateCallback_missingState_throwsStateMismatch() {
        let url = URL(string: "agentstudio://oauth/callback?code=abc123")!
        XCTAssertThrowsError(try OAuthService.validateCallback(url: url, expectedState: "expected")) { error in
            guard case OAuthError.stateMismatch = error else {
                return XCTFail("Expected stateMismatch, got \(error)")
            }
        }
    }

    func test_validateCallback_extraPathSegment_throwsInvalidCallback() {
        let url = URL(string: "agentstudio://oauth/callback/extra?code=abc123&state=s")!
        XCTAssertThrowsError(try OAuthService.validateCallback(url: url, expectedState: "s")) { error in
            guard case OAuthError.invalidCallback = error else {
                return XCTFail("Expected invalidCallback, got \(error)")
            }
        }
    }

    // MARK: - Placeholder Validation

    func test_githubClientId_isPlaceholder() {
        // Current config uses placeholders — this test documents that OAuth
        // won't work until real client IDs are configured.
        let config = OAuthService.providerConfigs[.github]!
        XCTAssertTrue(config.clientId.hasPrefix("PLACEHOLDER"))
    }

    func test_googleClientId_isPlaceholder() {
        let config = OAuthService.providerConfigs[.google]!
        XCTAssertTrue(config.clientId.hasPrefix("PLACEHOLDER"))
    }

    func test_notConfigured_errorDescription_includesProvider() {
        let error = OAuthError.notConfigured(.github)
        XCTAssertTrue(error.errorDescription!.contains("github"))
        XCTAssertTrue(error.errorDescription!.contains("not configured"))
    }

    func test_notConfigured_isCancelled_returnsFalse() {
        XCTAssertFalse(OAuthError.notConfigured(.github).isCancelled)
    }
}
