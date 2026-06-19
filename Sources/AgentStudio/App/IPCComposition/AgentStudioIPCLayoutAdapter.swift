import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

@MainActor
protocol AgentStudioIPCLayoutActionExecuting: AnyObject {
    func execute(_ action: WorkspaceActionCommand) -> Bool
}

extension WorkspaceActionExecutor: AgentStudioIPCLayoutActionExecuting {}

@MainActor
struct AgentStudioIPCLayoutAdapter: AppIPCLayoutPort, @unchecked Sendable {
    private let workspaceStore: WorkspaceStore
    private let windowLifecycleReader: any WorkspaceWindowLifecycleReading
    private let paneFocusControl: any PaneFocusAppControlling
    private let workspaceActionExecutor: any AgentStudioIPCLayoutActionExecuting

    init(
        workspaceStore: WorkspaceStore,
        windowLifecycleReader: any WorkspaceWindowLifecycleReading,
        paneFocusControl: any PaneFocusAppControlling,
        workspaceActionExecutor: any AgentStudioIPCLayoutActionExecuting
    ) {
        self.workspaceStore = workspaceStore
        self.windowLifecycleReader = windowLifecycleReader
        self.paneFocusControl = paneFocusControl
        self.workspaceActionExecutor = workspaceActionExecutor
    }

    func focusPane(_ handle: IPCHandle) throws -> IPCPaneFocusResult {
        guard hasActiveWindow() else {
            throw AppIPCLayoutError(reason: .noActiveWindow)
        }
        guard handle.kind == .pane else {
            throw AppIPCLayoutError(reason: .validationRejected)
        }

        let snapshot = workspaceStore.programmaticControlSnapshot()
        let paneId = try resolvePaneId(handle, in: snapshot)

        do {
            try paneFocusControl.focusPane(paneId)
        } catch PaneFocusAppControlError.targetNotFound {
            throw AppIPCLayoutError(reason: .targetNotFound)
        } catch PaneFocusAppControlError.validationRejected {
            throw AppIPCLayoutError(reason: .validationRejected)
        }

        return IPCPaneFocusResult(paneId: paneId, focused: true)
    }

    func splitPane(_ params: IPCPaneSplitParams) throws -> IPCPaneSplitResult {
        guard hasActiveWindow() else {
            throw AppIPCLayoutError(reason: .noActiveWindow)
        }
        let snapshot = workspaceStore.programmaticControlSnapshot()
        let paneId = try resolvePaneId(try IPCHandle.parse(params.handle), in: snapshot)
        let tabId = try resolveTabId(forPaneId: paneId, in: snapshot)
        try executeLayoutAction(
            .insertPane(
                source: .newTerminal,
                targetTabId: tabId,
                targetPaneId: paneId,
                direction: SplitNewDirection(params.direction),
                sizingMode: .halveTarget
            )
        )
        return IPCPaneSplitResult(
            targetPaneId: paneId, direction: params.direction, correlationId: params.correlationId)
    }

    func closePane(_ params: IPCPaneCloseParams) throws -> IPCPaneCloseResult {
        guard hasActiveWindow() else {
            throw AppIPCLayoutError(reason: .noActiveWindow)
        }
        let snapshot = workspaceStore.programmaticControlSnapshot()
        let paneId = try resolvePaneId(try IPCHandle.parse(params.handle), in: snapshot)
        let tabId = try resolveTabId(forPaneId: paneId, in: snapshot)
        try executeLayoutAction(.closePane(tabId: tabId, paneId: paneId))
        return IPCPaneCloseResult(paneId: paneId, correlationId: params.correlationId)
    }

    func addDrawerPane(_ params: IPCDrawerAddPaneParams) throws -> IPCDrawerAddPaneResult {
        guard hasActiveWindow() else {
            throw AppIPCLayoutError(reason: .noActiveWindow)
        }
        let snapshot = workspaceStore.programmaticControlSnapshot()
        let paneId = try resolvePaneId(try IPCHandle.parse(params.parentPaneHandle), in: snapshot)
        try validateDrawerParent(paneId, in: snapshot)
        try executeLayoutAction(.addDrawerPane(parentPaneId: paneId))
        return IPCDrawerAddPaneResult(parentPaneId: paneId, correlationId: params.correlationId)
    }

    func toggleDrawer(_ params: IPCDrawerToggleParams) throws -> IPCDrawerToggleResult {
        guard hasActiveWindow() else {
            throw AppIPCLayoutError(reason: .noActiveWindow)
        }
        let snapshot = workspaceStore.programmaticControlSnapshot()
        let paneId = try resolvePaneId(try IPCHandle.parse(params.parentPaneHandle), in: snapshot)
        try validateDrawerParent(paneId, in: snapshot)
        try executeLayoutAction(.toggleDrawer(paneId: paneId))
        return IPCDrawerToggleResult(parentPaneId: paneId, correlationId: params.correlationId)
    }

    private func hasActiveWindow() -> Bool {
        let lifecycle = windowLifecycleReader.snapshot()
        guard let currentWindowId = lifecycle.preferredWorkspaceWindowId else {
            return false
        }
        return lifecycle.registeredWindowIds.contains(currentWindowId)
    }

    private func resolvePaneId(
        _ handle: IPCHandle,
        in snapshot: ProgrammaticControlWorkspaceSnapshot
    ) throws -> UUID {
        guard handle.kind == .pane else {
            throw AppIPCLayoutError(reason: .validationRejected)
        }
        switch handle.reference {
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

    private func resolveTabId(
        forPaneId paneId: UUID,
        in snapshot: ProgrammaticControlWorkspaceSnapshot
    ) throws -> UUID {
        guard let pane = snapshot.panes.first(where: { $0.id == paneId }),
            let tabId = pane.tabId
        else {
            throw AppIPCLayoutError(reason: .targetNotFound)
        }
        return tabId
    }

    private func validateDrawerParent(
        _ paneId: UUID,
        in snapshot: ProgrammaticControlWorkspaceSnapshot
    ) throws {
        guard let pane = snapshot.panes.first(where: { $0.id == paneId }) else {
            throw AppIPCLayoutError(reason: .targetNotFound)
        }
        guard !pane.isDrawerChild else {
            throw AppIPCLayoutError(reason: .validationRejected)
        }
    }

    private func executeLayoutAction(_ action: WorkspaceActionCommand) throws {
        guard workspaceActionExecutor.execute(action) else {
            throw AppIPCLayoutError(reason: .validationRejected)
        }
    }
}

extension SplitNewDirection {
    fileprivate init(_ direction: IPCPaneSplitDirection) {
        switch direction {
        case .left:
            self = .left
        case .right:
            self = .right
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
