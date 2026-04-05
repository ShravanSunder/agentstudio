@MainActor
final class AtomStore {
    let workspace: WorkspaceAtom
    let repoCache: RepoCacheAtom
    let uiState: UIStateAtom
    let managementMode: ManagementModeAtom

    init(
        workspace: WorkspaceAtom = .init(),
        repoCache: RepoCacheAtom = .init(),
        uiState: UIStateAtom = .init(),
        managementMode: ManagementModeAtom = .init()
    ) {
        self.workspace = workspace
        self.repoCache = repoCache
        self.uiState = uiState
        self.managementMode = managementMode
    }

    var paneDisplay: PaneDisplayDerived {
        PaneDisplayDerived()
    }
}
