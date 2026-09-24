import AgentStudioAppIPC
import AgentStudioCore
import Foundation

/// Reads an agent's own pane from the current pane graph: the bound pane and,
/// when it is a main-layout pane, its drawer children. A drawer terminal owns
/// only itself. One pane lookup per request; no I/O.
@MainActor
final class WorkspaceOwnPaneScopePort: AppIPCOwnPaneScopePort, @unchecked Sendable {
    private let workspaceStore: WorkspaceStore

    init(workspaceStore: WorkspaceStore) {
        self.workspaceStore = workspaceStore
    }

    func ownPaneScope(boundPaneId: UUID) -> AppIPCOwnPaneScope? {
        guard let pane = workspaceStore.paneAtom.pane(boundPaneId) else { return nil }
        return AppIPCOwnPaneScope(
            boundPaneId: boundPaneId,
            isDrawerTerminal: pane.isDrawerChild,
            drawerChildPaneIds: Set(pane.drawer?.paneIds ?? [])
        )
    }
}
