import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneCommandFocusDeciderTests {
    @Test("command focusPane for terminal selects pane and syncs runtime")
    func commandFocusPane_terminalSelectsAndSyncsRuntime() {
        let paneId = UUID()
        let tabId = UUID()

        let decision = PaneCommandFocusDecider.decide(
            trigger: .focusPane(tabId: tabId, paneId: paneId),
            context: PaneFocusContext(
                activeTabId: tabId,
                activePaneId: UUID(),
                activeDrawerParentPaneId: nil,
                activeDrawerPaneId: nil,
                targetPaneId: paneId,
                targetTabId: tabId,
                targetPaneKind: .terminal,
                targetPaneIsAlreadyActive: false,
                targetMountedContent: .terminal(surfaceId: UUID()),
                managementMode: .inactive,
                windowState: .key,
                triggerSource: .command
            )
        )

        #expect(decision.selection == .selectPane(tabId: tabId, paneId: paneId))
        #expect(decision.responder == .focusPaneHost(paneId: paneId))
        #expect(decision.runtime == .syncTerminalSurface(paneId: paneId))
    }
}
