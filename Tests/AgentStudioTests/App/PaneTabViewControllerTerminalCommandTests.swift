import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerTerminalCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("seven terminal navigation commands target the focused main pane")
    func terminalNavigationCommandsTargetFocusedMainPane() async throws {
        #expect(AppPolicies.TerminalNavigation.pageFraction == 0.9)
        #expect(AppPolicies.TerminalNavigation.smallStepFraction == 0.33)

        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane()
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(pane.id, inTab: tab.id)
        atom(\.workspaceFocusOwner).focusMainPane(pane.id)

        let runtime = RecordingCommandPaneRuntime(paneId: PaneId(existingUUID: pane.id))
        harness.runtimeRegistry.register(runtime)
        let commands: [AppCommand] = [
            .scrollPageUp, .scrollPageDown, .scrollSmallStepUp, .scrollSmallStepDown,
            .jumpToPreviousPrompt, .jumpToNextPrompt, .scrollToBottom,
        ]

        for (index, command) in commands.enumerated() {
            harness.controller.execute(command)
            await waitForRecordedCommands(on: runtime, count: index + 1)
        }

        #expect(runtime.receivedCommands.count == 7)
        for command in runtime.receivedCommands {
            #expect(command.targetPaneId == PaneId(existingUUID: pane.id))
        }
        expectSettledTerminalNavigationCommands(runtime.receivedCommands)
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

    private func expectSettledTerminalNavigationCommands(_ envelopes: [RuntimeCommandEnvelope]) {
        guard envelopes.count == 7 else { return }
        expectFractionalScroll(envelopes[0], fraction: -AppPolicies.TerminalNavigation.pageFraction)
        expectFractionalScroll(envelopes[1], fraction: AppPolicies.TerminalNavigation.pageFraction)
        expectFractionalScroll(envelopes[2], fraction: -AppPolicies.TerminalNavigation.smallStepFraction)
        expectFractionalScroll(envelopes[3], fraction: AppPolicies.TerminalNavigation.smallStepFraction)
        guard case .terminal(.jumpToPrompt(delta: -1)) = envelopes[4].command else {
            Issue.record("Expected previous-prompt command")
            return
        }
        guard case .terminal(.jumpToPrompt(delta: 1)) = envelopes[5].command else {
            Issue.record("Expected next-prompt command")
            return
        }
        guard case .terminal(.scrollToBottom) = envelopes[6].command else {
            Issue.record("Expected scroll-to-bottom command")
            return
        }
    }

    private func expectFractionalScroll(_ envelope: RuntimeCommandEnvelope, fraction: Double) {
        guard case .terminal(.scrollPageFractional(let actualFraction)) = envelope.command else {
            Issue.record("Expected fractional scroll command")
            return
        }
        #expect(actualFraction == fraction)
    }
}
