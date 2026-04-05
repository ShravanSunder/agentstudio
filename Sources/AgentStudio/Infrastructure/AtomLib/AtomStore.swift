@MainActor
final class AtomStore {
    let workspace: WorkspaceAtom
    let repoCache: RepoCacheAtom
    let uiState: UIStateAtom
    let managementMode: ManagementModeAtom
    let sessionRuntime: SessionRuntimeAtom

    init(
        workspace: WorkspaceAtom = .init(),
        repoCache: RepoCacheAtom = .init(),
        uiState: UIStateAtom = .init(),
        managementMode: ManagementModeAtom = .init(),
        sessionRuntime: SessionRuntimeAtom = .init()
    ) {
        self.workspace = workspace
        self.repoCache = repoCache
        self.uiState = uiState
        self.managementMode = managementMode
        self.sessionRuntime = sessionRuntime
    }

    var paneDisplay: PaneDisplayDerived {
        PaneDisplayDerived()
    }

    var dynamicView: DynamicViewDerived {
        DynamicViewDerived()
    }
}
