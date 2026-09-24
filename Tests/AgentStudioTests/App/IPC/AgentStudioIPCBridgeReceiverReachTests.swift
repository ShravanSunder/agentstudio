import AgentStudioAppIPC
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

/// A pane agent reaches its receiving Bridge through its own terminal's
/// handle: the real Bridge adapter resolves terminal → receiver → current
/// controller over the real executor and store, re-checks the agent's own
/// pane at the handoff, and reports a receiver with no mounted page as
/// unavailable rather than guessing.
@MainActor
@Suite("App IPC Bridge receiver reach", .serialized)
struct AgentStudioIPCBridgeReceiverReachTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("a terminal's handle reaches its receiver, which answers not mounted until a Bridge page exists")
    func terminalHandleReachesUnmountedReceiver() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            // Arrange
            let fixture = makeReachFixture(windowLifecycleStore: atoms.windowLifecycle)
            defer { try? FileManager.default.removeItem(at: fixture.harness.tempDir) }
            let terminal = fixture.terminal
            let handle = IPCHandle(kind: .pane, reference: .canonicalUUID(terminal.id))
            let agent = AppIPCOwnPaneAssertion(boundPaneId: terminal.id)

            let searchParams = IPCBridgeFilesSearchParams(
                handle: "pane:\(terminal.id.uuidString)", searchText: "plan")

            // Act
            let renderState = await captureBridgeError {
                _ = try await fixture.adapter.renderState(handle, ownPaneAssertion: agent)
            }
            let beforeAnyBridge = try await fixture.adapter.searchFiles(searchParams, ownPaneAssertion: agent)
            // Any navigation of the terminal's receiver seeds its record, as
            // presenting its companion would.
            _ = await fixture.harness.executor.performBridgeNavigation(.showFiles, forPaneId: terminal.id)
            let seededButUnmounted = try await fixture.adapter.searchFiles(searchParams, ownPaneAssertion: agent)

            // Assert
            #expect(renderState == AppIPCBridgeError(reason: .notMounted))
            #expect(
                beforeAnyBridge
                    == IPCBridgeFilesSearchResult(
                        paneId: terminal.id, status: .unavailable, reason: .receiverUnavailable))
            #expect(
                seededButUnmounted
                    == IPCBridgeFilesSearchResult(paneId: terminal.id, status: .unavailable, reason: .notMounted))
        }
    }

    @Test("a drawer terminal's handle is admitted for its own agent and reaches the same unmounted receiver")
    func drawerTerminalHandleReachesOwnerReceiver() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            // Arrange
            let fixture = makeReachFixture(windowLifecycleStore: atoms.windowLifecycle)
            defer { try? FileManager.default.removeItem(at: fixture.harness.tempDir) }
            let drawerTerminal = try #require(fixture.harness.store.addDrawerPane(to: fixture.terminal.id))
            let handle = IPCHandle(kind: .pane, reference: .canonicalUUID(drawerTerminal.id))

            // Act
            let fromDrawerAgent = await captureBridgeError {
                _ = try await fixture.adapter.renderState(
                    handle, ownPaneAssertion: AppIPCOwnPaneAssertion(boundPaneId: drawerTerminal.id))
            }

            // Assert
            #expect(fromDrawerAgent == AppIPCBridgeError(reason: .notMounted))
        }
    }

    @Test("another terminal's handle is refused at the handoff even after authorization")
    func anotherTerminalIsRefusedAtTheHandoff() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            // Arrange
            let fixture = makeReachFixture(windowLifecycleStore: atoms.windowLifecycle)
            defer { try? FileManager.default.removeItem(at: fixture.harness.tempDir) }
            let other = fixture.harness.store.createPane(title: "Other terminal")
            fixture.harness.store.appendTab(Tab(paneId: other.id))
            let agent = AppIPCOwnPaneAssertion(boundPaneId: fixture.terminal.id)

            // Act
            var refusal: AuthorizationError?
            do {
                _ = try await fixture.adapter.searchFiles(
                    IPCBridgeFilesSearchParams(handle: "pane:\(other.id.uuidString)", searchText: "plan"),
                    ownPaneAssertion: agent
                )
            } catch let error as AuthorizationError {
                refusal = error
            }

            // Assert
            #expect(refusal == .notYetAllowed("bridge.files.search"))
        }
    }

    @Test("adding a worktree through another pane is refused at the navigation owner")
    func addWorktreeOutsideOwnPaneIsRefused() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            // Arrange
            let fixture = makeReachFixture(windowLifecycleStore: atoms.windowLifecycle)
            defer { try? FileManager.default.removeItem(at: fixture.harness.tempDir) }
            let other = fixture.harness.store.createPane(title: "Other terminal")
            fixture.harness.store.appendTab(Tab(paneId: other.id))
            let request = AppCommandExecutionRequest(
                command: .addBridgeWorktree,
                arguments: .typedIPC(
                    .worktreeInPane(
                        .init(
                            workspaceWindowId: UUIDv7.generate(),
                            worktreeId: UUIDv7.generate(),
                            targetPaneSelector: try IPCPaneSelector(rawValue: other.id.uuidString)
                        ))),
                executionContext: .headlessIPC(admitsDebugTestingCommands: false),
                ownPaneAssertion: WorkspaceOwnPaneAssertion(boundPaneId: fixture.terminal.id)
            )

            // Act
            let outcome = await fixture.harness.controller.executeHeadlessIPC(request)

            // Assert
            #expect(outcome == .outsideOwnPane)
            #expect(
                fixture.harness.executor.bridgeReceiver(forCommandPaneId: other.id).flatMap {
                    fixture.harness.executor.bridgeNavigationRecord(for: $0)
                } == nil)
        }
    }

    // MARK: - Fixture

    private struct ReachFixture {
        let harness: Harness
        let terminal: Pane
        let adapter: AgentStudioIPCBridgeAdapter
    }

    private func makeReachFixture(windowLifecycleStore: WindowLifecycleAtom) -> ReachFixture {
        let harness = makeHarness(windowLifecycleStore: windowLifecycleStore)
        let terminal = harness.store.createPane(title: "Agent terminal")
        let tab = Tab(paneId: terminal.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(terminal.id, inTab: tab.id)
        return ReachFixture(
            harness: harness,
            terminal: terminal,
            adapter: AgentStudioIPCBridgeAdapter(
                workspaceStore: harness.store,
                viewRegistry: harness.viewRegistry,
                actionExecutor: harness.executor
            )
        )
    }

    private func captureBridgeError(_ operation: () async throws -> Void) async -> AppIPCBridgeError? {
        do {
            try await operation()
            return nil
        } catch let error as AppIPCBridgeError {
            return error
        } catch {
            return nil
        }
    }
}
