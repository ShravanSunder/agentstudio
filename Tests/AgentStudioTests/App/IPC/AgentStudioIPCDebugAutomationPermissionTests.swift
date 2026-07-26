import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("App IPC debug automation permissions")
struct AgentStudioIPCDebugAutomationPermissionTests {
    @Test("debug automation can read workspace state, execute commands, and mutate only its workspace sidebar")
    func debugAutomationCanReadWorkspaceStateExecuteCommandsAndMutateOnlyItsWorkspaceSidebar() {
        let workspaceId = UUID()
        let anotherWorkspaceId = UUID()

        let permissionScopes = Set(
            AppDelegate.debugAutomationIPCPermissionScopes(workspaceId: workspaceId)
        )

        #expect(
            permissionScopes
                == [
                    IPCPermissionScope(
                        privilege: .workspaceRead,
                        target: .app,
                        dataScope: .unspecified
                    ),
                    IPCPermissionScope(
                        privilege: .appCommandExecute,
                        target: .app,
                        dataScope: .unspecified
                    ),
                    IPCPermissionScope(
                        privilege: .sidebarStateMutate,
                        target: .workspace(workspaceId),
                        dataScope: .sidebarState
                    ),
                ]
        )
        #expect(
            !permissionScopes.contains(
                IPCPermissionScope(
                    privilege: .sidebarStateMutate,
                    target: .workspace(anotherWorkspaceId),
                    dataScope: .sidebarState
                )
            )
        )
    }
}
