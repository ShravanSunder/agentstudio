import AgentStudioAppIPC
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

/// Authorization admits an agent's request while its target is inside the
/// agent's own pane; these cases move the target out before the effect runs
/// and prove the effect owner refuses it.
@MainActor
@Suite("App IPC own-pane re-check at effect time", .serialized)
struct AgentStudioIPCOwnPaneEffectRecheckTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("an agent's close queued behind a detach of its drawer child is refused with nothing applied")
    func queuedDetachThenCloseIsRefused() async throws {
        let scenario = try OwnPaneEffectScenario()
        defer { try? FileManager.default.removeItem(at: scenario.harness.tempDir) }
        let executor = scenario.harness.executor
        let store = scenario.harness.store
        let undoDepthBefore = executor.undoStack.count

        // Causal barrier: hold the gesture queue so both later gestures are
        // queued before either runs, in submission order.
        let gate = GestureGate()
        let barrier = executor.submitGesture { _ in
            await gate.wait()
            return true
        }
        let detach = executor.submit(
            .detachDrawerPane(parentPaneId: scenario.parentPaneId, drawerPaneId: scenario.childPaneId))
        let agentClose = executor.submit(
            .removeDrawerPane(parentPaneId: scenario.parentPaneId, drawerPaneId: scenario.childPaneId),
            ownPaneAssertion: WorkspaceOwnPaneAssertion(boundPaneId: scenario.parentPaneId)
        )
        // Authorization ran while the child was still the agent's own; the
        // assertion is only evaluated when the gesture runs.
        #expect(store.paneAtom.pane(scenario.childPaneId)?.parentPaneId == scenario.parentPaneId)
        gate.open()

        #expect(await barrier.value)
        #expect(await detach.value)
        #expect(await agentClose.value == .outsideOwnPane)
        let detachedChild = try #require(store.paneAtom.pane(scenario.childPaneId))
        #expect(detachedChild.parentPaneId == nil)
        #expect(store.tabLayoutAtom.tab(scenario.tabId)?.allPaneIds.contains(scenario.childPaneId) == true)
        #expect(executor.undoStack.count == undoDepthBefore)
    }

    @Test("terminal input to a drawer child detached before handoff reaches no runtime")
    func runtimeInputAfterDetachIsRefused() async throws {
        let scenario = try OwnPaneEffectScenario()
        defer { try? FileManager.default.removeItem(at: scenario.harness.tempDir) }
        let adapter = AgentStudioIPCRuntimeAdapter(
            workspaceStore: scenario.harness.store,
            runtimeRegistry: scenario.harness.runtimeRegistry,
            commandDispatcher: scenario.harness.coordinator
        )
        let agent = AppIPCOwnPaneAssertion(boundPaneId: scenario.parentPaneId)
        let childHandle = IPCHandle(kind: .pane, reference: .canonicalUUID(scenario.childPaneId))

        _ = try await adapter.sendTerminalInput(
            to: childHandle, input: "before\n", correlationId: nil, ownPaneAssertion: agent)
        #expect(
            await scenario.harness.executor.execute(
                .detachDrawerPane(parentPaneId: scenario.parentPaneId, drawerPaneId: scenario.childPaneId)))
        await #expect(throws: AuthorizationError.notYetAllowed("terminal.send")) {
            _ = try await adapter.sendTerminalInput(
                to: childHandle, input: "after\n", correlationId: nil, ownPaneAssertion: agent)
        }

        #expect(terminalCommandNames(scenario.childRuntime.receivedCommands) == ["sendInput(before\n)"])
    }

    @Test("a headless scroll for a drawer child detached before handoff reaches no runtime")
    func headlessScrollAfterDetachIsRefused() async throws {
        let scenario = try OwnPaneEffectScenario()
        defer { try? FileManager.default.removeItem(at: scenario.harness.tempDir) }
        #expect(
            await scenario.harness.executor.execute(
                .detachDrawerPane(parentPaneId: scenario.parentPaneId, drawerPaneId: scenario.childPaneId)))

        let outcome = await scenario.harness.controller.executeHeadlessIPC(
            AppCommandExecutionRequest(
                command: .scrollToBottom,
                arguments: .typedIPC(
                    .pane(
                        .init(
                            workspaceWindowId: UUIDv7.generate(),
                            paneSelector: try IPCPaneSelector(rawValue: scenario.childPaneId.uuidString)
                        ))),
                executionContext: .headlessIPC(admitsDebugTestingCommands: false),
                ownPaneAssertion: WorkspaceOwnPaneAssertion(boundPaneId: scenario.parentPaneId)
            ))

        #expect(outcome == .outsideOwnPane)
        #expect(scenario.childRuntime.receivedCommands.isEmpty)
    }
}

/// One main terminal with one drawer terminal in the active tab, each with a
/// recording runtime.
@MainActor
private struct OwnPaneEffectScenario {
    let harness: PaneTabViewControllerCommandHarness
    let tabId: UUID
    let parentPaneId: UUID
    let childPaneId: UUID
    let childRuntime: RecordingCommandPaneRuntime

    init() throws {
        harness = makeHarness()
        let parent = harness.store.createPane(title: "Agent terminal")
        let tab = Tab(paneId: parent.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(parent.id, inTab: tab.id)
        let child = try #require(harness.store.addDrawerPane(to: parent.id))
        childRuntime = RecordingCommandPaneRuntime(paneId: PaneId(existingUUID: child.id))
        harness.runtimeRegistry.register(childRuntime)
        tabId = tab.id
        parentPaneId = parent.id
        childPaneId = child.id
    }
}

/// Holds the executor's gesture queue until the test opens it.
@MainActor
private final class GestureGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}
