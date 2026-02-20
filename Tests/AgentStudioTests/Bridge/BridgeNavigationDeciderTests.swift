import XCTest
@testable import AgentStudio

/// Tests for BridgeNavigationDecider URL scheme policy.
///
/// Bridge panes use a strict allowlist: only `agentstudio` (bundled React app)
/// and `about` (initial blank page). All web schemes are blocked to prevent
/// bridge panes from navigating to external content.
///
/// Note: These tests verify the static policy logic using the actual
/// `BridgeNavigationDecider.allowedSchemes` set. Full NavigationDeciding
/// integration (with real WebPage.NavigationAction) requires a running WebKit
/// instance and is covered by visual verification.
final class BridgeNavigationDeciderTests: XCTestCase {

    // MARK: - Allowed

    func test_allowedSchemes_agentstudio() {
        XCTAssertTrue(BridgeNavigationDecider.allowedSchemes.contains("agentstudio"))
    }

    func test_allowedSchemes_about() {
        XCTAssertTrue(BridgeNavigationDecider.allowedSchemes.contains("about"))
    }

    func test_allowedSchemes_exactCount() {
        XCTAssertEqual(BridgeNavigationDecider.allowedSchemes.count, 2)
    }

    // MARK: - Blocked (bridge panes must NOT navigate to web)

    func test_blockedSchemes_https() {
        XCTAssertFalse(BridgeNavigationDecider.allowedSchemes.contains("https"))
    }

    func test_blockedSchemes_http() {
        XCTAssertFalse(BridgeNavigationDecider.allowedSchemes.contains("http"))
    }

    func test_blockedSchemes_file() {
        XCTAssertFalse(BridgeNavigationDecider.allowedSchemes.contains("file"))
    }

    func test_blockedSchemes_javascript() {
        XCTAssertFalse(BridgeNavigationDecider.allowedSchemes.contains("javascript"))
    }

    func test_blockedSchemes_data() {
        XCTAssertFalse(BridgeNavigationDecider.allowedSchemes.contains("data"))
    }
}
