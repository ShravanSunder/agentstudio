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
                activeDrawer: nil,
                targetPaneId: paneId,
                targetTabId: tabId,
                targetPaneKind: .terminal,
                targetPaneIsAlreadyActive: false,
                targetMountedContent: .terminal(surfaceId: UUID()),
                managementMode: .inactive,
                windowState: .key
            )
        )

        #expect(decision.selection == .selectPane(tabId: tabId, paneId: paneId))
        #expect(decision.responder == .focusPaneHost(paneId: paneId))
        #expect(decision.runtime == .syncTerminalSurface(paneId: paneId))
    }

    @Test("command selectTab preserves existing responder ownership")
    func commandSelectTab_preservesResponder() {
        let tabId = UUID()

        let decision = PaneCommandFocusDecider.decide(
            trigger: .selectTab(tabId),
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: UUID(),
                activeDrawer: nil,
                targetPaneId: nil,
                targetTabId: tabId,
                targetPaneKind: .unknown,
                targetPaneIsAlreadyActive: false,
                targetMountedContent: .unmounted,
                managementMode: .inactive,
                windowState: .key
            )
        )

        #expect(decision.selection == .selectTab(tabId))
        #expect(decision.responder == .preserveCurrentResponder)
        #expect(decision.runtime == .preserveRuntimeFocus)
    }

    @Test("command paneCreated for terminal focuses host and syncs runtime")
    func commandPaneCreated_terminalFocusesAndSyncs() {
        let paneId = UUID()

        let decision = PaneCommandFocusDecider.decide(
            trigger: .paneCreated(paneId: paneId, paneKind: .terminal),
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: UUID(),
                activeDrawer: nil,
                targetPaneId: paneId,
                targetTabId: UUID(),
                targetPaneKind: .terminal,
                targetPaneIsAlreadyActive: false,
                targetMountedContent: .terminal(surfaceId: UUID()),
                managementMode: .inactive,
                windowState: .key
            )
        )

        #expect(decision.selection == .keep)
        #expect(decision.responder == .focusPaneHost(paneId: paneId))
        #expect(decision.runtime == .syncTerminalSurface(paneId: paneId))
    }
}
