@MainActor
final class AtomStore {
    let workspaceMetadata: WorkspaceMetadataAtom
    let workspaceRepositoryTopology: WorkspaceRepositoryTopologyAtom
    let workspacePane: WorkspacePaneAtom
    let workspaceTabLayout: WorkspaceTabLayoutAtom
    let workspaceMutationCoordinator: WorkspaceMutationCoordinator
    let repoCache: RepoCacheAtom
    let uiState: UIStateAtom
    let managementMode: ManagementModeAtom
    let sessionRuntime: SessionRuntimeAtom

    init(
        workspaceMetadata: WorkspaceMetadataAtom = .init(),
        workspaceRepositoryTopology: WorkspaceRepositoryTopologyAtom = .init(),
        workspacePane: WorkspacePaneAtom = .init(),
        workspaceTabLayout: WorkspaceTabLayoutAtom = .init(),
        workspaceMutationCoordinator: WorkspaceMutationCoordinator? = nil,
        repoCache: RepoCacheAtom = .init(),
        uiState: UIStateAtom = .init(),
        managementMode: ManagementModeAtom = .init(),
        sessionRuntime: SessionRuntimeAtom = .init()
    ) {
        self.workspaceMetadata = workspaceMetadata
        self.workspaceRepositoryTopology = workspaceRepositoryTopology
        self.workspacePane = workspacePane
        self.workspaceTabLayout = workspaceTabLayout
        self.workspaceMutationCoordinator =
            workspaceMutationCoordinator
            ?? WorkspaceMutationCoordinator(
                repositoryTopologyAtom: workspaceRepositoryTopology,
                workspacePaneAtom: workspacePane,
                workspaceTabLayoutAtom: workspaceTabLayout
            )
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
