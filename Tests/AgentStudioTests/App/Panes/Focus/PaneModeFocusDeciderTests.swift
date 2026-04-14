import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneModeFocusDeciderTests {
    @Test("management mode entry for active webview blocks content")
    func managementModeEntry_webviewBlocksContent() {
        let paneId = UUID()
        let trigger = PaneModeFocusTrigger(
            transition: .enteredManagementMode,
            source: .keyboardShortcut
        )

        let context = makeWebviewContext(paneId: paneId)

        let decision = PaneModeFocusDecider.decide(trigger: trigger, context: context)

        #expect(decision.content == .block)
    }

    private func makeWebviewContext(paneId: UUID) -> PaneFocusContext {
        PaneFocusContext(
            activeTabId: UUID(),
            activePaneId: paneId,
            activeDrawerParentPaneId: nil,
            activeDrawerPaneId: nil,
            targetPaneId: paneId,
            targetTabId: UUID(),
            targetPaneKind: .webview,
            targetPaneIsAlreadyActive: true,
            targetMountedContent: .nonTerminal(acceptsFirstResponder: true),
            managementMode: .active(scope: .mainRow),
            windowState: .key,
            triggerSource: .modeTransition
        )
    }
}
