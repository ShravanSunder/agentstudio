import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneContentClickFocusDeciderTests {
    @Test("active webview content click is a host no-op")
    func activeWebviewContentClick_isNoOp() {
        let paneId = UUID()
        let tabId = UUID()
        let trigger = PaneContentClickFocusTrigger(
            targetPaneId: paneId,
            location: .content,
            clickPhase: .completed
        )

        let context = PaneFocusContext(
            activeTabId: tabId,
            activePaneId: paneId,
            activeDrawerParentPaneId: nil,
            activeDrawerPaneId: nil,
            targetPaneId: paneId,
            targetTabId: tabId,
            targetPaneKind: .webview,
            targetPaneIsAlreadyActive: true,
            targetMountedContent: .nonTerminal(acceptsFirstResponder: true),
            managementMode: .inactive,
            windowState: .key,
            triggerSource: .contentClick
        )

        let decision = PaneContentClickFocusDecider.decide(
            trigger: trigger,
            context: context
        )

        #expect(decision.selection == .keep)
        #expect(decision.responder == .preserveCurrentResponder)
        #expect(decision.runtime == .preserveRuntimeFocus)
        #expect(decision.content == .preserve)
    }
}
