import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("AgentStudio IPC command adapter")
struct AgentStudioIPCCommandAdapterTests {
    @Test("lists only the public command allowlist")
    func listsOnlyThePublicCommandAllowlist() throws {
        let harness = CommandAdapterHarness()

        let result = try harness.adapter.listCommands()

        #expect(result.commands.map(\.id) == [.quickFind, .commandPalette, .panePicker, .repoWorktreePicker])
        #expect(result.commands.map(\.title) == ["Quick Find", "Command Palette", "Go to Pane", "New Tab or Worktree"])
    }

    @Test("rejects command execution without a workspace window")
    func rejectsCommandExecutionWithoutWorkspaceWindow() throws {
        let harness = CommandAdapterHarness(windowSnapshot: .empty)

        do {
            _ = try harness.adapter.executeCommand(
                IPCCommandExecuteParams(commandId: .commandPalette, targetHandle: nil)
            )
            Issue.record("command execution unexpectedly succeeded without a window")
        } catch let error as AppIPCCommandError {
            #expect(error.reason == .noActiveWindow)
        }
    }

    @Test("executes command palette and returns command bar postcondition")
    func executesCommandPaletteAndReturnsCommandBarPostcondition() throws {
        let windowId = UUID()
        let commandBarSurface = CommandBarSurfaceAtom()
        let dispatcher = RecordingIPCCommandDispatcher { command in
            #expect(command == .showCommandBarCommands)
            commandBarSurface.present(scope: .commands, workspaceWindowId: windowId)
        }
        let harness = CommandAdapterHarness(
            dispatcher: dispatcher,
            windowSnapshot: .singleActiveWindow(windowId),
            commandBarSurface: commandBarSurface
        )

        let result = try harness.adapter.executeCommand(
            IPCCommandExecuteParams(commandId: .commandPalette, targetHandle: nil)
        )

        #expect(dispatcher.dispatchedCommands == [.showCommandBarCommands])
        #expect(result.commandId == .commandPalette)
        #expect(result.applied)
        #expect(result.workspaceWindowId == windowId)
        #expect(result.commandBar == IPCCommandBarPostcondition(workspaceWindowId: windowId, scope: .commands))
    }
}

@MainActor
private struct CommandAdapterHarness {
    let adapter: AgentStudioIPCCommandAdapter

    init(
        dispatcher: any AgentStudioIPCCommandDispatching = RecordingIPCCommandDispatcher(),
        windowSnapshot: WorkspaceWindowLifecycleSnapshot = .singleActiveWindow(UUID()),
        commandBarSurface: CommandBarSurfaceAtom = CommandBarSurfaceAtom()
    ) {
        adapter = AgentStudioIPCCommandAdapter(
            dispatcher: dispatcher,
            windowLifecycleReader: FakeCommandWorkspaceWindowLifecycleReader(snapshot: windowSnapshot),
            commandBarSurface: commandBarSurface
        )
    }
}

@MainActor
private final class RecordingIPCCommandDispatcher: AgentStudioIPCCommandDispatching {
    private let onDispatch: (AppCommand) -> Void
    private(set) var dispatchedCommands: [AppCommand] = []

    init(onDispatch: @escaping (AppCommand) -> Void = { _ in }) {
        self.onDispatch = onDispatch
    }

    func definition(for command: AppCommand) -> CommandSpec {
        command.definition
    }

    func canDispatch(_ command: AppCommand) -> Bool {
        true
    }

    func dispatch(_ command: AppCommand) {
        dispatchedCommands.append(command)
        onDispatch(command)
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
