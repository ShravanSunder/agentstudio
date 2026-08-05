import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerTerminalCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("scrollToBottom targets the focused drawer pane")
    func executeScrollToBottom_targetsFocusedDrawerPane() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let parentPane = harness.store.createPane()
        let tab = Tab(paneId: parentPane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(parentPane.id, inTab: tab.id)

        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let drawerId = try #require(harness.store.pane(parentPane.id)?.drawer?.drawerId)
        harness.store.tabArrangementAtom.addDrawerPaneView(
            drawerId: drawerId,
            parentPaneId: parentPane.id,
            drawerPaneId: drawerPane.id,
            inTab: tab.id
        )
        harness.store.setActiveDrawerPane(drawerPane.id, in: parentPane.id)
        atom(\.workspaceFocusOwner).focusDrawerPane(parentPaneId: parentPane.id, paneId: drawerPane.id)

        let parentRuntime = RecordingCommandPaneRuntime(paneId: PaneId(existingUUID: parentPane.id))
        let drawerRuntime = RecordingCommandPaneRuntime(paneId: PaneId(existingUUID: drawerPane.id))
        harness.runtimeRegistry.register(parentRuntime)
        harness.runtimeRegistry.register(drawerRuntime)

        harness.controller.execute(.scrollToBottom)

        await waitForRecordedCommands(on: drawerRuntime, count: 1)
        #expect(parentRuntime.receivedCommands.isEmpty)
        let command = try #require(drawerRuntime.receivedCommands.first)
        #expect(command.targetPaneId == PaneId(existingUUID: drawerPane.id))
        guard case .terminal(.scrollToBottom) = command.command else {
            Issue.record("Expected focused drawer pane to receive scrollToBottom")
            return
        }
    }
}
