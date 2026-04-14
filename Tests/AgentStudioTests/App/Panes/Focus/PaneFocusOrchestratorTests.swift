import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneFocusOrchestratorTests {
    @Test("orchestrator dispatches content-click triggers through the content family")
    func orchestratorDispatchesContentClick() {
        let paneId = UUID()
        let tabId = UUID()

        let trigger = PaneFocusTrigger.contentClick(
            PaneContentClickFocusTrigger(
                targetPaneId: paneId,
                location: .content,
                clickPhase: .completed
            )
        )

        let decision: PaneFocusDecision = PaneFocusOrchestrator.decide(
            trigger: trigger,
            context: PaneFocusContext(
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
        )

        guard case .contentClick(let contentDecision) = decision else {
            Issue.record("Expected contentClick decision, got \(decision)")
            return
        }

        #expect(contentDecision.selection == .keep)
        #expect(contentDecision.responder == .preserveCurrentResponder)
        #expect(contentDecision.runtime == .preserveRuntimeFocus)
        #expect(contentDecision.content == .preserve)
    }
}
