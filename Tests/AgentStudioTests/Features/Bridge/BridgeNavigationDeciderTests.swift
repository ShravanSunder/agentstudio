import Foundation
import Testing

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
@Suite(.serialized)
final class BridgeNavigationDeciderTests {

    // MARK: - Allowed

    @Test
    func test_allowedSchemes_agentstudio() {
        #expect(BridgeNavigationDecider.allowedSchemes.contains("agentstudio"))
    }

    @Test
    func test_allowedSchemes_about() {
        #expect(BridgeNavigationDecider.allowedSchemes.contains("about"))
    }

    @Test
    func test_allowedSchemes_exactCount() {
        #expect(BridgeNavigationDecider.allowedSchemes.count == 2)
    }

    // MARK: - External (opened in default browser, not loaded in pane)

    @Test
    func test_externalSchemes_https() {
        #expect(BridgeNavigationDecider.externalSchemes.contains("https"))
        #expect(!(BridgeNavigationDecider.allowedSchemes.contains("https")))
    }

    @Test
    func test_externalSchemes_http() {
        #expect(BridgeNavigationDecider.externalSchemes.contains("http"))
        #expect(!(BridgeNavigationDecider.allowedSchemes.contains("http")))
    }

    @Test
    func test_externalSchemes_exactCount() {
        #expect(BridgeNavigationDecider.externalSchemes.count == 2)
    }

    // MARK: - Blocked (silently dropped, not opened anywhere)

    @Test
    func test_blockedSchemes_file() {
        #expect(!(BridgeNavigationDecider.allowedSchemes.contains("file")))
        #expect(!(BridgeNavigationDecider.externalSchemes.contains("file")))
    }

    @Test
    func test_blockedSchemes_javascript() {
        #expect(!(BridgeNavigationDecider.allowedSchemes.contains("javascript")))
        #expect(!(BridgeNavigationDecider.externalSchemes.contains("javascript")))
    }

    @Test
    func test_blockedSchemes_data() {
        #expect(!(BridgeNavigationDecider.allowedSchemes.contains("data")))
        #expect(!(BridgeNavigationDecider.externalSchemes.contains("data")))
    }
}
