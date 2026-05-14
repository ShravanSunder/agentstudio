import AppKit
import Testing

@testable import AgentStudio

@MainActor
private final class PaneSearchActionPerformer: TerminalSurfaceActionPerforming {
    private(set) var actions: [TerminalSurfaceAction] = []

    @discardableResult
    func performBindingAction(_ action: TerminalSurfaceAction) -> Bool {
        actions.append(action)
        return true
    }
}

@MainActor
private final class PaneScrollActionPerformer: TerminalSurfaceActionPerforming {
    @discardableResult
    func performBindingAction(_ action: TerminalSurfaceAction) -> Bool {
        _ = action
        return true
    }
}

@Suite("TerminalPaneMountView search responders")
@MainActor
struct TerminalPaneMountViewSearchTests {
    @Test("mount view search responders send exact ghostty binding actions")
    func mountViewSearchRespondersSendExactGhosttyBindingActions() {
        let mountView = TerminalPaneMountView(paneId: UUID(), title: "Terminal")
        let performer = PaneSearchActionPerformer()
        mountView.installActionPerformerForTesting(performer)

        mountView.startSearch(nil)
        mountView.findNext(nil)
        mountView.findPrevious(nil)
        mountView.cancelOperation(nil)

        #expect(
            performer.actions == [
                .startSearch,
                .navigateSearch(.next),
                .navigateSearch(.previous),
                .endSearch,
            ])
    }

    @Test("hitTest prioritizes search overlay over terminal content")
    func hitTestPrioritizesSearchOverlayOverTerminalContent() {
        let mountView = TerminalPaneMountView(paneId: UUID(), title: "Terminal")
        mountView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        mountView.ensureSearchOverlayForTesting()
        guard let point = mountView.searchOverlayInteractivePointForTesting else {
            Issue.record("Expected search overlay interactive point for hit-test verification")
            return
        }
        let hitView = mountView.hitTest(point)

        #expect(hitView != nil)
        #expect(hitView !== mountView)
    }

    @Test("hitTest prioritizes scroll-to-bottom indicator over terminal content")
    func hitTestPrioritizesScrollToBottomIndicatorOverTerminalContent() {
        let mountView = TerminalPaneMountView(paneId: UUID(), title: "Terminal")
        mountView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        mountView.ensureScrollToBottomIndicatorForTesting()
        guard let indicatorFrame = mountView.scrollToBottomIndicatorFrameForTesting else {
            Issue.record("Expected scroll-to-bottom indicator frame for hit-test verification")
            return
        }

        let point = NSPoint(x: indicatorFrame.midX, y: indicatorFrame.midY)
        let hitView = mountView.hitTest(point)

        #expect(hitView != nil)
        #expect(hitView !== mountView)
    }

    @Test("scroll-to-bottom indicator sits 12 points from trailing and bottom edges")
    func scrollToBottomIndicatorSitsTwelvePointsFromTrailingAndBottomEdges() {
        let mountView = TerminalPaneMountView(paneId: UUID(), title: "Terminal")
        mountView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        mountView.ensureScrollToBottomIndicatorForTesting()
        guard let indicatorFrame = mountView.scrollToBottomIndicatorFrameForTesting else {
            Issue.record("Expected scroll-to-bottom indicator frame for spacing verification")
            return
        }

        #expect(abs((800 - indicatorFrame.maxX) - 12) <= 1)
        #expect(abs(indicatorFrame.minY - 12) <= 3)
    }

    @Test("cancelOperation without search overlay falls through without emitting actions")
    func cancelOperationWithoutSearchOverlayDoesNotEmitActions() {
        let mountView = TerminalPaneMountView(paneId: UUID(), title: "Terminal")
        let performer = PaneSearchActionPerformer()
        mountView.installActionPerformerForTesting(performer)

        mountView.cancelOperation(nil)

        #expect(performer.actions.isEmpty)
    }

    @Test("bind does not drive the native scroll wrapper directly from runtime replay")
    func bindDoesNotDriveTheNativeScrollWrapperDirectlyFromRuntimeReplay() {
        let mountView = TerminalPaneMountView(paneId: UUID(), title: "Terminal")
        let scrollView = TerminalSurfaceScrollView(actionPerformer: PaneScrollActionPerformer())
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scrollView.layoutSubtreeIfNeeded()
        mountView.installSurfaceScrollViewForTesting(scrollView)

        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Terminal"), title: "Terminal")
        )
        #expect(runtime.transitionToReady())
        runtime.handleGhosttyEvent(.cellSizeChanged(NSSize(width: 8, height: 20)))
        runtime.handleGhosttyEvent(.scrollbarChanged(ScrollbarState(top: 80, bottom: 120, total: 200)))

        mountView.bind(runtime: runtime)

        #expect(scrollView.scrollView.contentView.bounds.origin.y == 0)
    }
}
