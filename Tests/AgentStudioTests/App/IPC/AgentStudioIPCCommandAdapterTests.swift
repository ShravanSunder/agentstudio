import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("AgentStudio IPC command adapter")
struct AgentStudioIPCCommandAdapterTests {
    @Test("lists only headless command specs")
    func listsOnlyHeadlessCommandSpecs() throws {
        let harness = CommandAdapterHarness()

        let result = try harness.adapter.listCommands()

        #expect(result.commands.isEmpty)
    }

    @Test("rejects presentation-only commands before workspace window checks")
    func rejectsPresentationOnlyCommandsBeforeWorkspaceWindowChecks() throws {
        let harness = CommandAdapterHarness(windowSnapshot: .empty)

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(commandId: .commandPalette, targetHandle: nil)
            )
            Issue.record("command palette unexpectedly executed through command.execute")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .requiresPresentation)
        }
    }

    @Test("rejects command palette because it requires explicit UI presentation")
    func rejectsCommandPaletteBecauseItRequiresExplicitUIPresentation() throws {
        let windowId = UUID()
        let harness = CommandAdapterHarness(
            windowSnapshot: .singleActiveWindow(windowId)
        )

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(commandId: .commandPalette, targetHandle: nil)
            )
            Issue.record("command palette unexpectedly executed through command.execute")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .requiresPresentation)
        }
    }

    @Test("unknown command ids return unsupported command after decoding")
    func unknownCommandIdsReturnUnsupportedCommandAfterDecoding() throws {
        let harness = CommandAdapterHarness(
            windowSnapshot: .singleActiveWindow(UUID())
        )

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(commandId: IPCCommandIdentifier(rawValue: "futureCommand"), targetHandle: nil)
            )
            Issue.record("unknown command unexpectedly executed through command.execute")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .unsupportedCommand)
        }
    }
}

@MainActor
private struct CommandAdapterHarness {
    let adapter: AgentStudioIPCCommandAdapter

    init(
        windowSnapshot: WorkspaceWindowLifecycleSnapshot = .singleActiveWindow(UUID())
    ) {
        adapter = AgentStudioIPCCommandAdapter(
            windowLifecycleReader: FakeCommandWorkspaceWindowLifecycleReader(snapshot: windowSnapshot)
        )
    }
}

private struct FakeCommandWorkspaceWindowLifecycleReader: WorkspaceWindowLifecycleReading {
    let snapshotValue: WorkspaceWindowLifecycleSnapshot

    init(snapshot: WorkspaceWindowLifecycleSnapshot) {
        snapshotValue = snapshot
    }

    func snapshot() -> WorkspaceWindowLifecycleSnapshot {
        snapshotValue
    }
}

extension WorkspaceWindowLifecycleSnapshot {
    fileprivate static var empty: Self {
        Self(
            registeredWindowIds: [],
            keyWindowId: nil,
            focusedWindowId: nil,
            preferredWorkspaceWindowId: nil
        )
    }

    fileprivate static func singleActiveWindow(_ windowId: UUID) -> Self {
        Self(
            registeredWindowIds: [windowId],
            keyWindowId: windowId,
            focusedWindowId: windowId,
            preferredWorkspaceWindowId: windowId
        )
    }
}
