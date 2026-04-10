import AppKit
import Testing

@testable import AgentStudio

@MainActor
private final class FakeSurfaceActionPerformer: TerminalSurfaceActionPerforming {
    private(set) var actions: [String] = []

    @discardableResult
    func performBindingAction(_ action: String) -> Bool {
        actions.append(action)
        return true
    }
}

@Suite("TerminalSurfaceScrollView")
@MainActor
struct TerminalSurfaceScrollViewTests {
    @Test("scroll wrapper converts live drag into scroll_to_row")
    func scrollWrapperConvertsLiveDragIntoScrollToRow() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )
        scrollView.simulateLiveScrollForTesting(documentOffsetY: 1200)

        #expect(performer.actions.last?.starts(with: "scroll_to_row:") == true)
    }

    @Test("scroll wrapper owns wheel scrolling and syncs row changes")
    func scrollWrapperOwnsWheelScrollingAndSyncsRowChanges() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )

        scrollView.simulateSurfaceWheelScrollForTesting(deltaY: 40)

        #expect(performer.actions.last?.starts(with: "scroll_to_row:") == true)
    }

    @Test("scroll wrapper clamps host scroll range to content bounds")
    func scrollWrapperClampsHostScrollRangeToContentBounds() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )

        scrollView.simulateLiveScrollForTesting(documentOffsetY: 50_000)

        #expect(scrollView.documentOffsetYForTesting == scrollView.maximumDocumentOffsetYForTesting)
    }

    @Test("scroll wrapper uses Ghostty-style document padding math")
    func scrollWrapperUsesGhosttyStyleDocumentPaddingMath() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )

        #expect(scrollView.documentHeightForTesting == 3800)
        #expect(scrollView.maximumDocumentOffsetYForTesting == 3200)
    }

    @Test("scroll wrapper uses native overlay scroller configuration")
    func scrollWrapperUsesNativeOverlayScrollerConfiguration() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        #expect(scrollView.autohidesScrollersForTesting == false)
        #expect(scrollView.usesOverlayScrollerStyleForTesting == true)
    }

    @Test("follow-bottom keeps viewport pinned when already at bottom")
    func followBottomKeepsViewportPinnedWhenAlreadyAtBottom() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 160, bottom: 200, total: 200),
            cellHeight: 20
        )
        #expect(scrollView.documentOffsetYForTesting == 0)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 170, bottom: 210, total: 210),
            cellHeight: 20
        )

        #expect(scrollView.documentOffsetYForTesting == 0)
    }

    @Test("follow-bottom does not move viewport when reading history")
    func followBottomDoesNotMoveViewportWhenReadingHistory() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )
        let historyOffset = scrollView.documentOffsetYForTesting

        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 210),
            cellHeight: 20
        )

        #expect(scrollView.documentOffsetYForTesting == historyOffset)
    }
}
