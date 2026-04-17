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
    private func simulateLiveScroll(_ scrollWrapper: TerminalSurfaceScrollView, documentOffsetY: CGFloat) {
        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification, object: scrollWrapper.scrollView)
        scrollWrapper.scrollView.contentView.scroll(to: CGPoint(x: 0, y: documentOffsetY))
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scrollWrapper.scrollView)
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveScrollNotification, object: scrollWrapper.scrollView)
    }

    private func simulateVisibleRectChange(_ scrollWrapper: TerminalSurfaceScrollView, documentOffsetY: CGFloat) {
        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification, object: scrollWrapper.scrollView)
        scrollWrapper.scrollView.contentView.scroll(to: CGPoint(x: 0, y: documentOffsetY))
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scrollWrapper.scrollView)
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveScrollNotification, object: scrollWrapper.scrollView)
    }

    private func documentOffsetY(of scrollWrapper: TerminalSurfaceScrollView) -> CGFloat {
        scrollWrapper.scrollView.contentView.bounds.origin.y
    }

    private func maximumDocumentOffsetY(of scrollWrapper: TerminalSurfaceScrollView) -> CGFloat {
        max(
            0, scrollWrapper.documentView.frame.height - scrollWrapper.scrollView.contentView.documentVisibleRect.height
        )
    }

    @Test("scroll wrapper converts live drag into scroll_to_row")
    func scrollWrapperConvertsLiveDragIntoScrollToRow() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )
        simulateLiveScroll(scrollView, documentOffsetY: 1200)

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

        simulateLiveScroll(scrollView, documentOffsetY: 1200)
        simulateLiveScroll(scrollView, documentOffsetY: 1200)

        #expect(performer.actions == [.scrollToRow(100)])
    }

    @Test("scroll wrapper converts live-scroll visible rect changes into row updates")
    func scrollWrapperConvertsLiveScrollVisibleRectChangesIntoRowUpdates() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )

        simulateVisibleRectChange(scrollView, documentOffsetY: 40)

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

        simulateLiveScroll(scrollView, documentOffsetY: 50_000)

        #expect(documentOffsetY(of: scrollView) == maximumDocumentOffsetY(of: scrollView))
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

        #expect(scrollView.documentView.frame.height == 3800)
        #expect(maximumDocumentOffsetY(of: scrollView) == 3200)
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

        #expect(scrollView.documentView.frame.height == 600)
        #expect(maximumDocumentOffsetY(of: scrollView) == 0)
    }

    @Test("scroll wrapper uses native overlay scroller configuration")
    func scrollWrapperUsesNativeOverlayScrollerConfiguration() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        #expect(scrollView.scrollView.autohidesScrollers == false)
        #expect(scrollView.scrollView.scrollerStyle == .overlay)
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
        scrollView.bindHostStateSource(hostStateView)
        scrollView.layoutSubtreeIfNeeded()

        #expect(scrollView.scrollView.hasVerticalScroller == false)
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
        scrollView.bindHostStateSource(hostStateView)
        scrollView.layoutSubtreeIfNeeded()

        guard let verticalScroller = scrollView.scrollView.verticalScroller else {
            Issue.record("Expected a native vertical scroller frame")
            return
        }
        let scrollerFrame = scrollView.convert(verticalScroller.bounds, from: verticalScroller)

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
        scrollView.bindHostStateSource(hostStateView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        #expect(documentOffsetY(of: scrollView) == 1600)
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
        scrollView.bindHostStateSource(hostStateView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        simulateLiveScroll(scrollView, documentOffsetY: 1200)

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

        #expect(scrollView.documentView.frame.height == 600)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )

        #expect(scrollView.documentView.frame.height == 3800)
    }

    @Test("follow-bottom keeps viewport pinned when already at bottom")
    func followBottomKeepsViewportPinnedWhenAlreadyAtBottom() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 160, bottom: 200, total: 200),
            cellHeight: 20
        )
        #expect(documentOffsetY(of: scrollView) == 0)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 170, bottom: 210, total: 210),
            cellHeight: 20
        )

        #expect(documentOffsetY(of: scrollView) == 0)
    }

    @Test("history viewport stays anchored to the same top row when total rows grow")
    func historyViewportStaysAnchoredWhenTotalRowsGrow() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )
        #expect(documentOffsetY(of: scrollView) == 1600)

        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 210),
            cellHeight: 20
        )

        #expect(documentOffsetY(of: scrollView) == 1800)
    }
}
