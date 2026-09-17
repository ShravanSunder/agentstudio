import AgentStudioAppIPC
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation

@testable import AgentStudio
@testable import AgentStudioCore

/// Shared harness for the typed `command.execute` adapter tests. It composes the
/// real adapter against a recording shell owner so every test drives the same
/// registration path the App server uses.
@MainActor
struct CommandAdapterHarness {
    let adapter: AgentStudioIPCCommandAdapter
    let workspaceStore: WorkspaceStore
    let windowId: UUID
    let channel: AgentStudioIPCChannel
    let shellCommandHandler: RecordingShellCommandHandler

    init(
        windowId: UUID = UUIDv7.generate(),
        channel: AgentStudioIPCChannel = .stable,
        shellCommandHandler: RecordingShellCommandHandler = RecordingShellCommandHandler()
    ) {
        workspaceStore = WorkspaceStore()
        self.windowId = windowId
        self.channel = channel
        self.shellCommandHandler = shellCommandHandler
        if shellCommandHandler.currentWindowId == nil {
            shellCommandHandler.currentWindowId = windowId
        }
        adapter = AgentStudioIPCCommandAdapter(
            workspaceId: workspaceStore.identityAtom.workspaceId,
            channel: channel,
            targetAuthorizer: WorkspaceDurableTargetAuthorizationPort(workspaceStore: workspaceStore),
            shellCommandHandler: shellCommandHandler
        )
    }
}

@MainActor
final class RecordingShellCommandHandler: ShellCommandHandling {
    var handledRequests: [AppCommandExecutionRequest] = []
    var currentWindowId: UUID?
    var outcome: AppCommandExecutionOutcome = .applied

    init(currentWindowId: UUID? = nil) {
        self.currentWindowId = currentWindowId
    }

    func ownsWorkspaceWindow(_ workspaceWindowId: UUID) -> Bool {
        currentWindowId == workspaceWindowId
    }

    func canExecute(_: AppCommand) -> Bool { true }
    func canExecute(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { true }
    func execute(_: AppCommand) -> Bool { false }
    func execute(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { false }

    func execute(_ request: AppCommandExecutionRequest) -> AppCommandExecutionOutcome {
        handledRequests.append(request)
        return outcome
    }

    func showRepoCommandBar() {}
    func refreshWorktrees() {}
    func refocusActivePane() {}
}

func commandAdapterTestPrincipal() -> IPCPrincipal {
    IPCPrincipal(
        principalId: UUIDv7.generate(),
        runtimeId: UUIDv7.generate(),
        accessMode: .unsafeDebug,
        kind: .unsafeDebugClient,
        approvalAuthority: .noApprovalAuthority
    )
}

let retiredPanesOrganizationCommands: [AppCommand] = [
    .setPanesGroupingRepo,
    .setPanesGroupingTab,
    .setPanesGroupingActivity,
    .setPanesSubgroupNone,
    .setPanesSubgroupActivity,
    .setPanesSortFieldName,
    .setPanesSortFieldActivity,
    .togglePanesSortDirection,
]
