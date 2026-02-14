import XCTest
@testable import AgentStudio

@MainActor
final class WebviewPaneControllerTests: XCTestCase {

    // MARK: - Init

    func test_init_createsPages_fromState() {
        // Arrange
        let tabs = [
            WebviewTabState(url: URL(string: "https://github.com")!, title: "GitHub"),
            WebviewTabState(url: URL(string: "https://docs.swift.org")!, title: "Docs"),
        ]
        let state = WebviewState(tabs: tabs, activeTabIndex: 1)

        // Act
        let controller = WebviewPaneController(paneId: UUID(), state: state)

        // Assert
        XCTAssertEqual(controller.pages.count, 2)
        XCTAssertEqual(controller.activeTabIndex, 1)
        XCTAssertTrue(controller.showNavigation)
    }

    func test_init_clampsActiveTabIndex() {
        // Arrange
        let state = WebviewState(
            tabs: [WebviewTabState(url: URL(string: "https://example.com")!)],
            activeTabIndex: 5
        )

        // Act
        let controller = WebviewPaneController(paneId: UUID(), state: state)

        // Assert
        XCTAssertEqual(controller.activeTabIndex, 0)
    }

    // MARK: - Tab Operations

    func test_newTab_addsPageAndSelectsIt() {
        // Arrange
        let controller = makeController()
        XCTAssertEqual(controller.pages.count, 1)

        // Act
        controller.newTab(url: URL(string: "https://github.com")!)

        // Assert
        XCTAssertEqual(controller.pages.count, 2)
        XCTAssertEqual(controller.activeTabIndex, 1)
    }

    func test_closeTab_removesTab() {
        // Arrange
        let controller = makeController()
        controller.newTab(url: URL(string: "https://github.com")!)
        XCTAssertEqual(controller.pages.count, 2)

        // Act
        controller.closeTab(at: 0)

        // Assert
        XCTAssertEqual(controller.pages.count, 1)
        XCTAssertEqual(controller.activeTabIndex, 0)
    }

    func test_closeTab_preventsClosingLastTab() {
        // Arrange
        let controller = makeController()
        XCTAssertEqual(controller.pages.count, 1)

        // Act
        controller.closeTab(at: 0)

        // Assert — still 1 tab
        XCTAssertEqual(controller.pages.count, 1)
    }

    func test_closeTab_adjustsActiveIndex_whenClosingBefore() {
        // Arrange
        let controller = makeController()
        controller.newTab(url: URL(string: "https://a.com")!)
        controller.newTab(url: URL(string: "https://b.com")!)
        controller.selectTab(at: 2)
        XCTAssertEqual(controller.activeTabIndex, 2)

        // Act — close tab at index 0
        controller.closeTab(at: 0)

        // Assert — active index shifts down
        XCTAssertEqual(controller.activeTabIndex, 1)
        XCTAssertEqual(controller.pages.count, 2)
    }

    func test_closeTab_adjustsActiveIndex_whenClosingAtEnd() {
        // Arrange
        let controller = makeController()
        controller.newTab(url: URL(string: "https://a.com")!)
        controller.selectTab(at: 1)
        XCTAssertEqual(controller.activeTabIndex, 1)

        // Act — close tab at index 1 (the active tab, which is the last)
        controller.closeTab(at: 1)

        // Assert — clamps to last
        XCTAssertEqual(controller.activeTabIndex, 0)
    }

    func test_selectTab_changesActiveIndex() {
        // Arrange
        let controller = makeController()
        controller.newTab(url: URL(string: "https://a.com")!)
        controller.newTab(url: URL(string: "https://b.com")!)

        // Act
        controller.selectTab(at: 1)

        // Assert
        XCTAssertEqual(controller.activeTabIndex, 1)
    }

    func test_selectTab_outOfRange_doesNothing() {
        // Arrange
        let controller = makeController()

        // Act
        controller.selectTab(at: 99)

        // Assert
        XCTAssertEqual(controller.activeTabIndex, 0)
    }

    // MARK: - Snapshot

    func test_snapshot_capturesTabState() {
        // Arrange
        let controller = makeController()
        controller.newTab(url: URL(string: "https://github.com")!)
        controller.selectTab(at: 1)

        // Act
        let snapshot = controller.snapshot()

        // Assert
        XCTAssertEqual(snapshot.tabs.count, 2)
        XCTAssertEqual(snapshot.activeTabIndex, 1)
        XCTAssertTrue(snapshot.showNavigation)
    }

    // MARK: - URL Normalization

    func test_normalizeURLString_addsHttps() {
        XCTAssertEqual(
            WebviewPaneController.normalizeURLString("example.com"),
            "https://example.com"
        )
    }

    func test_normalizeURLString_preservesExistingScheme() {
        XCTAssertEqual(
            WebviewPaneController.normalizeURLString("http://example.com"),
            "http://example.com"
        )
    }

    func test_normalizeURLString_preservesAbout() {
        XCTAssertEqual(
            WebviewPaneController.normalizeURLString("about:blank"),
            "about:blank"
        )
    }

    func test_normalizeURLString_emptyInput() {
        XCTAssertEqual(
            WebviewPaneController.normalizeURLString(""),
            "about:blank"
        )
    }

    func test_normalizeURLString_trimsWhitespace() {
        XCTAssertEqual(
            WebviewPaneController.normalizeURLString("  github.com  "),
            "https://github.com"
        )
    }

    // MARK: - Helpers

    private func makeController() -> WebviewPaneController {
        WebviewPaneController(
            paneId: UUID(),
            state: WebviewState(url: URL(string: "https://example.com")!)
        )
    }
}
