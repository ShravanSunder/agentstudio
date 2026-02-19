import XCTest
@testable import AgentStudio

/// Tests for WebviewNavigationDecider URL scheme policy.
///
/// Note: These tests verify the static policy logic using the actual
/// `WebviewNavigationDecider.allowedSchemes` set. Full NavigationDeciding
/// integration (with real WebPage.NavigationAction) requires a running WebKit
/// instance and is covered by visual verification.
final class WebviewNavigationDeciderTests: XCTestCase {

    // MARK: - Allowed Schemes

    func test_allowedSchemes_https() {
        XCTAssertTrue(WebviewNavigationDecider.allowedSchemes.contains("https"))
    }

    func test_allowedSchemes_http() {
        XCTAssertTrue(WebviewNavigationDecider.allowedSchemes.contains("http"))
    }

    func test_allowedSchemes_about() {
        XCTAssertTrue(WebviewNavigationDecider.allowedSchemes.contains("about"))
    }

    func test_allowedSchemes_file() {
        XCTAssertTrue(WebviewNavigationDecider.allowedSchemes.contains("file"))
    }

    func test_allowedSchemes_agentstudio() {
        XCTAssertTrue(WebviewNavigationDecider.allowedSchemes.contains("agentstudio"))
    }

    func test_allowedSchemes_exactCount() {
        // Ensures no schemes are accidentally added or removed without updating tests
        XCTAssertEqual(WebviewNavigationDecider.allowedSchemes.count, 5)
    }

    // MARK: - Blocked Schemes

    func test_blockedSchemes_javascript() {
        XCTAssertFalse(WebviewNavigationDecider.allowedSchemes.contains("javascript"))
    }

    func test_blockedSchemes_data() {
        XCTAssertFalse(WebviewNavigationDecider.allowedSchemes.contains("data"))
    }

    func test_blockedSchemes_blob() {
        XCTAssertFalse(WebviewNavigationDecider.allowedSchemes.contains("blob"))
    }

    func test_blockedSchemes_unknown() {
        XCTAssertFalse(WebviewNavigationDecider.allowedSchemes.contains("custom-unknown"))
    }

    func test_blockedSchemes_empty() {
        XCTAssertFalse(WebviewNavigationDecider.allowedSchemes.contains(""))
    }

}
