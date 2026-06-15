import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

@MainActor
struct AgentStudioIPCLayoutAdapter: AppIPCLayoutPort, @unchecked Sendable {
    private let workspaceStore: WorkspaceStore
    private let windowLifecycleReader: any WorkspaceWindowLifecycleReading
    private let paneFocusControl: any PaneFocusAppControlling

    init(
        workspaceStore: WorkspaceStore,
        windowLifecycleReader: any WorkspaceWindowLifecycleReading,
        paneFocusControl: any PaneFocusAppControlling
    ) {
        self.workspaceStore = workspaceStore
        self.windowLifecycleReader = windowLifecycleReader
        self.paneFocusControl = paneFocusControl
    }

    func focusPane(_ handle: IPCHandle) throws -> IPCPaneFocusResult {
        guard hasActiveWindow() else {
            throw AppIPCLayoutError(reason: .noActiveWindow)
        }
        guard handle.kind == .pane else {
            throw AppIPCLayoutError(reason: .validationRejected)
        }

        let snapshot = workspaceStore.programmaticControlSnapshot()
        let paneId = try resolvePaneId(handle.reference, in: snapshot)

        do {
            try paneFocusControl.focusPane(paneId)
        } catch PaneFocusAppControlError.targetNotFound {
            throw AppIPCLayoutError(reason: .targetNotFound)
        } catch PaneFocusAppControlError.validationRejected {
            throw AppIPCLayoutError(reason: .validationRejected)
        }

        return IPCPaneFocusResult(paneId: paneId, focused: true)
    }

    private func hasActiveWindow() -> Bool {
        let lifecycle = windowLifecycleReader.snapshot()
        guard let currentWindowId = lifecycle.preferredWorkspaceWindowId else {
            return false
        }
        return lifecycle.registeredWindowIds.contains(currentWindowId)
    }

    private func resolvePaneId(
        _ reference: IPCHandleReference,
        in snapshot: ProgrammaticControlWorkspaceSnapshot
    ) throws -> UUID {
        switch reference {
        case .canonicalUUID(let paneId):
            guard snapshot.panes.contains(where: { $0.id == paneId }) else {
                throw AppIPCLayoutError(reason: .targetNotFound)
            }
            return paneId

        case .friendlyOrdinal(let ordinal):
            guard let pane = snapshot.panes[safe: ordinal - 1] else {
                throw AppIPCLayoutError(reason: .targetNotFound)
            }
            return pane.id
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
