import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneModeFocusDeciderTests {
    @Test("management layer entry for active webview blocks content")
    func managementLayerEntry_webviewBlocksContent() {
        let paneId = UUID()
        let trigger = PaneModeFocusTrigger(
            transition: .enteredManagementLayer,
            source: .keyboardShortcut
        )

        let context = makeWebviewContext(paneId: paneId)

        let decision = PaneModeFocusDecider.decide(trigger: trigger, context: context)

        #expect(decision.content == .block)
    }

    @Test("management layer entry for active terminal clears responder ownership")
    func managementLayerEntry_terminalClearsResponder() {
        let paneId = UUID()
        let trigger = PaneModeFocusTrigger(
            transition: .enteredManagementLayer,
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
                managementLayer: .active(scope: .mainRow),
                windowState: .key
            )
        )

        #expect(decision.responder == .clearToWindowContent)
        #expect(decision.keyboard == .consume)
        #expect(decision.content == .block)
    }

    @Test("management layer exit releases content without moving responder directly")
    func managementLayerExit_releasesContent() {
        let paneId = UUID()
        let trigger = PaneModeFocusTrigger(
            transition: .exitedManagementLayer,
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
            managementLayer: .active(scope: .mainRow),
            windowState: .key
        )
    }
}
