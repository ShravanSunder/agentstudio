import Foundation
import Testing

@testable import AgentStudio

/// Tests for WebviewNavigationDecider URL scheme policy.
///
/// Note: These tests verify the static policy logic using the actual
/// `WebviewNavigationDecider.allowedSchemes` set. Full NavigationDeciding
/// integration (with real WebPage.NavigationAction) requires a running WebKit
/// instance and is covered by visual verification.
@Suite(.serialized)
struct WebviewNavigationDeciderTests {
    // MARK: - Allowed Schemes

    @Test
    func test_allowedSchemes_https() {
        #expect(WebviewNavigationDecider.allowedSchemes.contains("https"))
    }

    @Test
    func test_allowedSchemes_http() {
        #expect(WebviewNavigationDecider.allowedSchemes.contains("http"))
    }

    @Test
    func test_allowedSchemes_about() {
        #expect(WebviewNavigationDecider.allowedSchemes.contains("about"))
    }

    @Test
    func test_allowedSchemes_file() {
        #expect(WebviewNavigationDecider.allowedSchemes.contains("file"))
    }

    @Test
    func test_allowedSchemes_agentstudio() {
        #expect(WebviewNavigationDecider.allowedSchemes.contains("agentstudio"))
    }

    @Test
    func test_allowedSchemes_exactCount() {
        // Ensures no schemes are accidentally added or removed without updating tests
        #expect(WebviewNavigationDecider.allowedSchemes.count == 5)
    }

    // MARK: - Blocked Schemes

    @Test
    func test_blockedSchemes_javascript() {
        #expect(!WebviewNavigationDecider.allowedSchemes.contains("javascript"))
    }

    @Test
    func test_blockedSchemes_data() {
        #expect(!WebviewNavigationDecider.allowedSchemes.contains("data"))
    }

    @Test
    func test_blockedSchemes_blob() {
        #expect(!WebviewNavigationDecider.allowedSchemes.contains("blob"))
    }

    @Test
    func test_blockedSchemes_unknown() {
        #expect(!WebviewNavigationDecider.allowedSchemes.contains("custom-unknown"))
    }

    @Test
    func test_blockedSchemes_empty() {
        #expect(!WebviewNavigationDecider.allowedSchemes.contains(""))
    }
}
