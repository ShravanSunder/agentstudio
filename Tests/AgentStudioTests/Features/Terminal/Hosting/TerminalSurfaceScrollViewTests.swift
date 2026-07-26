import AppKit
import Testing

@testable import AgentStudio

@MainActor
private final class FakeSurfaceActionPerformer: TerminalSurfaceActionPerforming {
    private(set) var actions: [TerminalSurfaceAction] = []
    var shouldPerformAction = true

    @discardableResult
    func performBindingAction(_ action: TerminalSurfaceAction) -> Bool {
        guard shouldPerformAction else { return false }
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
    private func startLiveScroll(_ scrollWrapper: TerminalSurfaceScrollView) {
        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification, object: scrollWrapper.scrollView)
    }

    private func updateLiveScroll(_ scrollWrapper: TerminalSurfaceScrollView, documentOffsetY: CGFloat) {
        scrollWrapper.scrollView.contentView.scroll(to: CGPoint(x: 0, y: documentOffsetY))
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scrollWrapper.scrollView)
    }

    private func endLiveScroll(_ scrollWrapper: TerminalSurfaceScrollView) {
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveScrollNotification, object: scrollWrapper.scrollView)
    }

    private func simulateLiveScroll(_ scrollWrapper: TerminalSurfaceScrollView, documentOffsetY: CGFloat) {
        startLiveScroll(scrollWrapper)
        updateLiveScroll(scrollWrapper, documentOffsetY: documentOffsetY)
        endLiveScroll(scrollWrapper)
    }

    private func simulateVisibleRectChange(_ scrollWrapper: TerminalSurfaceScrollView, documentOffsetY: CGFloat) {
        simulateLiveScroll(scrollWrapper, documentOffsetY: documentOffsetY)
    }

    private func documentOffsetY(of scrollWrapper: TerminalSurfaceScrollView) -> CGFloat {
        scrollWrapper.scrollView.contentView.bounds.origin.y
    }

    private func maximumDocumentOffsetY(of scrollWrapper: TerminalSurfaceScrollView) -> CGFloat {
        max(
            0, scrollWrapper.documentView.frame.height - scrollWrapper.scrollView.contentView.documentVisibleRect.height
        )
    }

    private func configuredHostStateView() -> FakeTerminalSurfaceHostStateView {
        let hostStateView = FakeTerminalSurfaceHostStateView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        hostStateView.reportedCellSize = NSSize(width: 8, height: 20)
        hostStateView.hostConfigSnapshot = GhosttyHostConfigSnapshot(
            scrollbarPolicy: .system,
            backgroundColor: .black
        )
        return hostStateView
    }

    private func prepare(
        _ scrollView: TerminalSurfaceScrollView,
        with hostStateView: FakeTerminalSurfaceHostStateView
    ) {
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.bindHostStateSource(hostStateView)
        scrollView.layoutSubtreeIfNeeded()
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

    @Test("scroll wrapper sends authoritative bottom intent at the maximum row")
    func scrollWrapperSendsAuthoritativeBottomIntentAtMaximumRow() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )

        simulateLiveScroll(scrollView, documentOffsetY: 0)

        #expect(performer.actions == [.scrollToBottom])
        #expect(!performer.actions.contains(.scrollToRow(160)))
    }

    @Test("scroll wrapper deduplicates repeated bottom intent across gestures")
    func scrollWrapperDeduplicatesRepeatedBottomIntentAcrossGestures() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )

        simulateLiveScroll(scrollView, documentOffsetY: 0)
        simulateLiveScroll(scrollView, documentOffsetY: 0)

        #expect(performer.actions == [.scrollToBottom])
    }

    @Test("programmatic pinned state deduplicates a zero movement bottom gesture")
    func programmaticPinnedStateDeduplicatesZeroMovementBottomGesture() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.applyScrollbarState(
            ScrollbarState(top: 160, bottom: 200, total: 200),
            cellHeight: 20
        )

        simulateLiveScroll(scrollView, documentOffsetY: 0)

        #expect(performer.actions.isEmpty)
    }

    @Test("matching row state received during gesture reconciles at drag end")
    func matchingRowStateReceivedDuringGestureReconcilesAtDragEnd() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        let hostStateView = configuredHostStateView()
        prepare(scrollView, with: hostStateView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        startLiveScroll(scrollView)
        updateLiveScroll(scrollView, documentOffsetY: 1200)
        hostStateView.emitScrollbarState(ScrollbarState(top: 100, bottom: 140, total: 200))
        scrollView.scrollView.contentView.scroll(to: CGPoint(x: 0, y: 800))
        let actionCountBeforeEnd = performer.actions.count
        endLiveScroll(scrollView)

        #expect(documentOffsetY(of: scrollView) == 1200)
        #expect(performer.actions.count == actionCountBeforeEnd)
    }

    @Test("pinned state received during bottom gesture reconciles at drag end")
    func pinnedStateReceivedDuringBottomGestureReconcilesAtDragEnd() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        let hostStateView = configuredHostStateView()
        prepare(scrollView, with: hostStateView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        startLiveScroll(scrollView)
        updateLiveScroll(scrollView, documentOffsetY: 0)
        hostStateView.emitScrollbarState(ScrollbarState(top: 160, bottom: 200, total: 200))
        scrollView.scrollView.contentView.scroll(to: CGPoint(x: 0, y: 800))
        let actionCountBeforeEnd = performer.actions.count
        endLiveScroll(scrollView)

        #expect(documentOffsetY(of: scrollView) == 0)
        #expect(performer.actions.count == actionCountBeforeEnd)
    }

    @Test("no-command gesture applies state received during gesture")
    func noCommandGestureAppliesStateReceivedDuringGesture() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        let hostStateView = configuredHostStateView()
        prepare(scrollView, with: hostStateView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        startLiveScroll(scrollView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 90, bottom: 130, total: 200))
        endLiveScroll(scrollView)

        #expect(documentOffsetY(of: scrollView) == 1400)
        #expect(performer.actions.isEmpty)

        simulateLiveScroll(scrollView, documentOffsetY: 1400)

        #expect(performer.actions.isEmpty)
    }

    @Test("no-command pinned reconciliation refreshes bottom dedup")
    func noCommandPinnedReconciliationRefreshesBottomDedup() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        let hostStateView = configuredHostStateView()
        prepare(scrollView, with: hostStateView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        startLiveScroll(scrollView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 160, bottom: 200, total: 200))
        endLiveScroll(scrollView)

        #expect(documentOffsetY(of: scrollView) == 0)
        #expect(performer.actions.isEmpty)

        simulateLiveScroll(scrollView, documentOffsetY: 0)

        #expect(performer.actions.isEmpty)
    }

    @Test("unrelated pinned growth does not acknowledge an interior row")
    func unrelatedPinnedGrowthDoesNotAcknowledgeInteriorRow() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        let hostStateView = configuredHostStateView()
        prepare(scrollView, with: hostStateView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        startLiveScroll(scrollView)
        updateLiveScroll(scrollView, documentOffsetY: 1200)
        hostStateView.emitScrollbarState(ScrollbarState(top: 170, bottom: 210, total: 210))
        let offsetBeforeEnd = documentOffsetY(of: scrollView)
        let actionCountBeforeEnd = performer.actions.count
        endLiveScroll(scrollView)

        scrollView.needsLayout = true
        scrollView.layoutSubtreeIfNeeded()

        #expect(documentOffsetY(of: scrollView) == offsetBeforeEnd)
        #expect(documentOffsetY(of: scrollView) != 0)
        #expect(performer.actions.count == actionCountBeforeEnd)
    }

    @Test("fresh scrollbar state resumes synchronization after rejected gesture")
    func freshScrollbarStateResumesSynchronizationAfterRejectedGesture() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        let hostStateView = configuredHostStateView()
        prepare(scrollView, with: hostStateView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        startLiveScroll(scrollView)
        updateLiveScroll(scrollView, documentOffsetY: 1200)
        hostStateView.emitScrollbarState(ScrollbarState(top: 170, bottom: 210, total: 210))
        let offsetBeforeEnd = documentOffsetY(of: scrollView)
        endLiveScroll(scrollView)

        scrollView.needsLayout = true
        scrollView.layoutSubtreeIfNeeded()
        #expect(documentOffsetY(of: scrollView) == offsetBeforeEnd)

        hostStateView.emitScrollbarState(ScrollbarState(top: 90, bottom: 130, total: 210))

        #expect(documentOffsetY(of: scrollView) == 1600)
    }

    @Test("drag end without received state does not write clip position")
    func dragEndWithoutReceivedStateDoesNotWriteClipPosition() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.applyScrollbarState(
            ScrollbarState(top: 80, bottom: 120, total: 200),
            cellHeight: 20
        )

        startLiveScroll(scrollView)
        updateLiveScroll(scrollView, documentOffsetY: 1200)
        scrollView.scrollView.contentView.scroll(to: CGPoint(x: 0, y: 800))
        let actionCountBeforeEnd = performer.actions.count
        endLiveScroll(scrollView)

        scrollView.needsLayout = true
        scrollView.layoutSubtreeIfNeeded()

        #expect(documentOffsetY(of: scrollView) == 800)
        #expect(performer.actions.count == actionCountBeforeEnd)
    }

    @Test("later accepted gesture clears pending layout suppression")
    func laterAcceptedGestureClearsPendingLayoutSuppression() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        let hostStateView = configuredHostStateView()
        prepare(scrollView, with: hostStateView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        startLiveScroll(scrollView)
        updateLiveScroll(scrollView, documentOffsetY: 1200)
        scrollView.scrollView.contentView.scroll(to: CGPoint(x: 0, y: 800))
        endLiveScroll(scrollView)

        startLiveScroll(scrollView)
        updateLiveScroll(scrollView, documentOffsetY: 1200)
        endLiveScroll(scrollView)
        scrollView.needsLayout = true
        scrollView.layoutSubtreeIfNeeded()
        #expect(documentOffsetY(of: scrollView) == 1200)

        scrollView.scrollView.contentView.scroll(to: CGPoint(x: 0, y: 800))
        startLiveScroll(scrollView)
        updateLiveScroll(scrollView, documentOffsetY: 1400)
        hostStateView.emitScrollbarState(ScrollbarState(top: 90, bottom: 130, total: 200))
        endLiveScroll(scrollView)

        #expect(documentOffsetY(of: scrollView) == 1400)

        scrollView.scrollView.contentView.scroll(to: CGPoint(x: 0, y: 800))
        scrollView.needsLayout = true
        scrollView.layoutSubtreeIfNeeded()

        #expect(documentOffsetY(of: scrollView) == 1400)
        #expect(performer.actions == [.scrollToRow(100), .scrollToRow(90)])
    }

    @Test("rejected action remains retryable without a scrollbar callback")
    func rejectedActionRemainsRetryableWithoutScrollbarCallback() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        let hostStateView = configuredHostStateView()
        prepare(scrollView, with: hostStateView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))
        performer.shouldPerformAction = false

        startLiveScroll(scrollView)
        updateLiveScroll(scrollView, documentOffsetY: 1200)
        endLiveScroll(scrollView)

        performer.shouldPerformAction = true
        startLiveScroll(scrollView)
        updateLiveScroll(scrollView, documentOffsetY: 1200)
        endLiveScroll(scrollView)

        #expect(documentOffsetY(of: scrollView) == 1200)
        #expect(performer.actions == [.scrollToRow(100)])
    }

    @Test("pending reconciliation preserves clip position while updating layout geometry")
    func pendingReconciliationPreservesClipPositionWhileUpdatingLayoutGeometry() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        let hostStateView = configuredHostStateView()
        prepare(scrollView, with: hostStateView)
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        startLiveScroll(scrollView)
        updateLiveScroll(scrollView, documentOffsetY: 1200)
        scrollView.scrollView.contentView.scroll(to: CGPoint(x: 0, y: 800))
        endLiveScroll(scrollView)

        scrollView.frame.size.height = 500
        scrollView.needsLayout = true
        scrollView.layoutSubtreeIfNeeded()

        guard let verticalScroller = scrollView.scrollView.verticalScroller else {
            Issue.record("Expected pending layout to preserve the native vertical scroller")
            return
        }

        #expect(documentOffsetY(of: scrollView) == 800)
        #expect(scrollView.scrollView.frame.height == 500)
        #expect(scrollView.scrollView.contentView.documentVisibleRect.height == 500)
        #expect(scrollView.documentView.frame.height == 3700)
        #expect(verticalScroller.frame.height > 0)
        #expect(verticalScroller.frame.maxY <= scrollView.scrollView.bounds.maxY)
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

    @Test("output growth within sticky buffer requests scroll-to-bottom")
    func outputGrowthWithinStickyBufferRequestsScrollToBottom() {
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
        scrollView.layoutSubtreeIfNeeded()
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        scrollView.scrollView.contentView.scroll(
            to: CGPoint(x: 0, y: AppPolicies.WorkspaceFocus.Terminal.stickyBottomBufferPx - 1)
        )
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 210))

        #expect(performer.actions.last == .scrollToBottom)
    }

    @Test("output growth outside sticky buffer does not request scroll-to-bottom")
    func outputGrowthOutsideStickyBufferDoesNotRequestScrollToBottom() {
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
        scrollView.layoutSubtreeIfNeeded()
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))

        scrollView.scrollView.contentView.scroll(
            to: CGPoint(x: 0, y: AppPolicies.WorkspaceFocus.Terminal.stickyBottomBufferPx + 1)
        )
        hostStateView.emitScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 210))

        #expect(performer.actions.isEmpty)
    }
}
