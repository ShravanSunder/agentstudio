import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("App delegate IPC debug token escrow composition")
struct AppDelegateIPCDebugTokenEscrowCompositionTests {
    @Test("composes exactly the accepted existing privilege scopes")
    func composesExactlyTheAcceptedExistingPrivilegeScopes() {
        let workspaceId = UUID()

        let scopes = AppDelegate.debugAutomationIPCPermissionScopes(workspaceId: workspaceId)

        #expect(
            Set(scopes) == [
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
                    privilege: .layoutMutate,
                    target: .app,
                    dataScope: .paneContext
                ),
                IPCPermissionScope(
                    privilege: .uiPresent,
                    target: .app,
                    dataScope: .uiSurface
                ),
                IPCPermissionScope(
                    privilege: .sidebarStateMutate,
                    target: .workspace(workspaceId),
                    dataScope: .sidebarState
                ),
            ])
    }
}
