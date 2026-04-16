import AppKit
import Testing

@testable import AgentStudio

@MainActor
private final class FakeSurfaceActionPerformer: TerminalSurfaceActionPerforming {
    private(set) var actions: [TerminalSurfaceAction] = []

    @discardableResult
    func performBindingAction(_ action: TerminalSurfaceAction) -> Bool {
        actions.append(action)
        return true
    }
}

@MainActor
private final class FakeTerminalSurfaceHostStateView: NSView, TerminalSurfaceHostStateSource {
    var hostScrollbarState: ScrollbarState?
    var hostConfigSnapshot = GhosttyHostConfigSnapshot(configHandle: nil)
    var reportedCellSize: NSSize?
    var onHostScrollbarStateChanged: (@MainActor @Sendable (ScrollbarState) -> Void)?

    func emitScrollbarState(_ state: ScrollbarState) {
        hostScrollbarState = state
        onHostScrollbarStateChanged?(state)
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

        #expect(performer.actions.last == .scrollToRow(100))
    }

    @Test("scroll wrapper deduplicates repeated live scrolls to the same row")
    func scrollWrapperDeduplicatesRepeatedLiveScrollsToSameRow() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )

        scrollView.simulateLiveScrollForTesting(documentOffsetY: 1200)
        scrollView.simulateLiveScrollForTesting(documentOffsetY: 1200)

        #expect(performer.actions == [.scrollToRow(100)])
    }

    @Test("scroll wrapper converts visible rect changes into row updates")
    func scrollWrapperConvertsVisibleRectChangesIntoRowUpdates() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )

        scrollView.simulateProgrammaticVisibleRectForTesting(documentOffsetY: 40)

        guard case .scrollToRow(let row)? = performer.actions.last else {
            Issue.record("Expected scroll wrapper to emit scrollToRow action")
            return
        }

        #expect(row >= 0)
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

    @Test("no scrollback keeps document height equal to viewport")
    func noScrollbackKeepsDocumentHeightEqualToViewport() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.applyScrollbarState(
            ScrollbarState(top: 0, bottom: 30, total: 30),
            cellHeight: 20
        )

        #expect(scrollView.documentHeightForTesting == 600)
        #expect(scrollView.maximumDocumentOffsetYForTesting == 0)
    }

    @Test("scroll wrapper uses native overlay scroller configuration")
    func scrollWrapperUsesNativeOverlayScrollerConfiguration() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        #expect(scrollView.autohidesScrollersForTesting == false)
        #expect(scrollView.usesOverlayScrollerStyleForTesting == true)
    }

    @Test("scroll wrapper uses host config snapshot to decide vertical scroller visibility")
    func scrollWrapperUsesHostConfigSnapshotToDecideVerticalScrollerVisibility() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        let hostStateView = FakeTerminalSurfaceHostStateView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))

        hostStateView.hostConfigSnapshot = GhosttyHostConfigSnapshot(
            scrollbarPolicy: .never,
            backgroundColor: .black
        )

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.bindHostStateSourceForTesting(hostStateView)
        scrollView.layoutSubtreeIfNeeded()

        #expect(scrollView.hasVerticalScrollerForTesting == false)
    }

    @Test("scroll wrapper exposes a non-empty native scroller frame when scrollbar policy is system")
    func scrollWrapperExposesNonEmptyNativeScrollerFrameWhenScrollbarPolicyIsSystem() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        let hostStateView = FakeTerminalSurfaceHostStateView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))

        hostStateView.hostConfigSnapshot = GhosttyHostConfigSnapshot(
            scrollbarPolicy: .system,
            backgroundColor: .black
        )

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.bindHostStateSourceForTesting(hostStateView)
        scrollView.layoutSubtreeIfNeeded()

        guard let scrollerFrame = scrollView.verticalScrollerFrameForTesting else {
            Issue.record("Expected a native vertical scroller frame")
            return
        }

        #expect(scrollerFrame.width > 0)
        #expect(scrollerFrame.height > 0)
    }

    @Test("scroll wrapper uses host scrollbar cache before runtime replay")
    func scrollWrapperUsesHostScrollbarCacheBeforeRuntimeReplay() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        let hostStateView = FakeTerminalSurfaceHostStateView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        hostStateView.reportedCellSize = NSSize(width: 8, height: 20)
        hostStateView.hostConfigSnapshot = GhosttyHostConfigSnapshot(
            scrollbarPolicy: .system,
            backgroundColor: .black
        )

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.bindHostStateSourceForTesting(hostStateView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        #expect(scrollView.documentOffsetYForTesting == 1600)
    }

    @Test("scroll wrapper converts live drag into scroll_to_row from host state source")
    func scrollWrapperConvertsLiveDragIntoScrollToRowFromHostStateSource() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        let hostStateView = FakeTerminalSurfaceHostStateView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        hostStateView.reportedCellSize = NSSize(width: 8, height: 20)
        hostStateView.hostConfigSnapshot = GhosttyHostConfigSnapshot(
            scrollbarPolicy: .system,
            backgroundColor: .black
        )

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.bindHostStateSourceForTesting(hostStateView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        scrollView.simulateLiveScrollForTesting(documentOffsetY: 1200)

        #expect(performer.actions.last == .scrollToRow(100))
    }

    @Test("zero cellHeight ignores update until valid metrics arrive")
    func zeroCellHeightIgnoresUpdateUntilValidMetricsArrive() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 0
        )

        #expect(scrollView.documentHeightForTesting == 600)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )

        #expect(scrollView.documentHeightForTesting == 3800)
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

    @Test("history viewport stays anchored to the same top row when total rows grow")
    func historyViewportStaysAnchoredWhenTotalRowsGrow() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )
        #expect(scrollView.documentOffsetYForTesting == 1600)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 210),
            cellHeight: 20
        )

        #expect(scrollView.documentOffsetYForTesting == 1800)
    }
}
