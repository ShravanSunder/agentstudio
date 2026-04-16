import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneKeyboardFocusDeciderTests {
    @Test("keyboard move to terminal pane keeps pass-through and syncs runtime")
    func keyboardMoveToTerminalPane_syncsRuntime() {
        let paneId = UUID()

        let decision = PaneKeyboardFocusDecider.decide(
            trigger: .moveToPane(tabId: UUID(), paneId: paneId, paneKind: .terminal),
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: paneId,
                activeDrawer: nil,
                targetPaneId: paneId,
                targetTabId: UUID(),
                targetPaneKind: .terminal,
                targetPaneIsAlreadyActive: false,
                targetMountedContent: .terminal(surfaceId: UUID()),
                managementLayer: .inactive,
                windowState: .key
            )
        )

        #expect(decision.keyboard == .passThrough)
        #expect(decision.responder == .focusPaneHost(paneId: paneId))
        #expect(decision.runtime == .syncTerminalSurface(paneId: paneId))
    }

    @Test("keyboard move to webview pane preserves responder ownership")
    func keyboardMoveToWebviewPane_preservesResponder() {
        let paneId = UUID()

        let decision = PaneKeyboardFocusDecider.decide(
            trigger: .moveToPane(tabId: UUID(), paneId: paneId, paneKind: .webview),
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: paneId,
                activeDrawer: nil,
                targetPaneId: paneId,
                targetTabId: UUID(),
                targetPaneKind: .webview,
                targetPaneIsAlreadyActive: false,
                targetMountedContent: .nonTerminal(acceptsFirstResponder: true),
                managementLayer: .inactive,
                windowState: .key
            )
        )

        #expect(decision.keyboard == .passThrough)
        #expect(decision.responder == .preserveCurrentResponder)
        #expect(decision.runtime == .preserveRuntimeFocus)
    }
}
