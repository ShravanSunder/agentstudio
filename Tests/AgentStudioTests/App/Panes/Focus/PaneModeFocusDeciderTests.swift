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

    @Test("management mode entry for active terminal clears responder ownership")
    func managementModeEntry_terminalClearsResponder() {
        let paneId = UUID()
        let trigger = PaneModeFocusTrigger(
            transition: .enteredManagementMode,
            source: .keyboardShortcut
        )

        let decision = PaneModeFocusDecider.decide(
            trigger: trigger,
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: paneId,
                activeDrawer: nil,
                targetPaneId: paneId,
                targetTabId: UUID(),
                targetPaneKind: .terminal,
                targetPaneIsAlreadyActive: true,
                targetMountedContent: .terminal(surfaceId: UUID()),
                managementMode: .active(scope: .mainRow),
                windowState: .key
            )
        )

        #expect(decision.responder == .clearToWindowContent)
        #expect(decision.keyboard == .consume)
        #expect(decision.content == .block)
    }

    @Test("management mode exit releases content without moving responder directly")
    func managementModeExit_releasesContent() {
        let paneId = UUID()
        let trigger = PaneModeFocusTrigger(
            transition: .exitedManagementMode,
            source: .command
        )

        let decision = PaneModeFocusDecider.decide(
            trigger: trigger,
            context: makeWebviewContext(paneId: paneId)
        )

        #expect(decision.responder == .preserveCurrentResponder)
        #expect(decision.keyboard == .passThrough)
        #expect(decision.content == .release)
    }

    private func makeWebviewContext(paneId: UUID) -> PaneFocusContext {
        PaneFocusContext(
            activeTabId: UUID(),
            activePaneId: paneId,
            activeDrawer: nil,
            targetPaneId: paneId,
            targetTabId: UUID(),
            targetPaneKind: .webview,
            targetPaneIsAlreadyActive: true,
            targetMountedContent: .nonTerminal(acceptsFirstResponder: true),
            managementMode: .active(scope: .mainRow),
            windowState: .key
        )
    }
}
