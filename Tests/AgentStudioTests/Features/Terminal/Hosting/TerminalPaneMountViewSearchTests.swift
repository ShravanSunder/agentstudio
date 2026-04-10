import AppKit
import Testing

@testable import AgentStudio

@MainActor
private final class PaneSearchActionPerformer: TerminalSurfaceActionPerforming {
    private(set) var actions: [String] = []

    @discardableResult
    func performBindingAction(_ action: String) -> Bool {
        actions.append(action)
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
                "start_search",
                "navigate_search:next",
                "navigate_search:previous",
                "end_search",
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
}
