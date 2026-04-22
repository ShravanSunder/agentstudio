@MainActor
final class AtomRegistry {
    let workspaceMetadata: WorkspaceMetadataAtom
    let workspaceRepositoryTopology: WorkspaceRepositoryTopologyAtom
    let workspacePane: WorkspacePaneAtom
    let workspaceTabShell: WorkspaceTabShellAtom
    let workspaceTabArrangement: WorkspaceTabArrangementAtom
    let workspaceTabLayout: WorkspaceTabLayoutAtom
    let workspaceMutationCoordinator: WorkspaceMutationCoordinator
    let windowLifecycle: WindowLifecycleAtom
    let repoCache: RepoCacheAtom
    let uiState: UIStateAtom
    let managementLayer: ManagementLayerAtom
    let sessionRuntime: SessionRuntimeAtom
    let welcome: WelcomeAtom

    init(
        workspaceMetadata: WorkspaceMetadataAtom = .init(),
        workspaceRepositoryTopology: WorkspaceRepositoryTopologyAtom = .init(),
        workspacePane: WorkspacePaneAtom = .init(),
        workspaceTabShell: WorkspaceTabShellAtom = .init(),
        workspaceTabArrangement: WorkspaceTabArrangementAtom = .init(),
        workspaceMutationCoordinator: WorkspaceMutationCoordinator? = nil,
        windowLifecycle: WindowLifecycleAtom = .init(),
        repoCache: RepoCacheAtom = .init(),
        uiState: UIStateAtom = .init(),
        managementLayer: ManagementLayerAtom = .init(),
        sessionRuntime: SessionRuntimeAtom = .init(),
        welcome: WelcomeAtom = .init()
    ) {
        self.workspaceMetadata = workspaceMetadata
        self.workspaceRepositoryTopology = workspaceRepositoryTopology
        self.workspacePane = workspacePane
        self.workspaceTabShell = workspaceTabShell
        self.workspaceTabArrangement = workspaceTabArrangement
        self.workspaceTabLayout = WorkspaceTabLayoutAtom(
            shellAtom: workspaceTabShell,
            arrangementAtom: workspaceTabArrangement
        )
        self.workspaceMutationCoordinator =
            workspaceMutationCoordinator
            ?? WorkspaceMutationCoordinator(
                repositoryTopologyAtom: workspaceRepositoryTopology,
                workspacePaneAtom: workspacePane,
                workspaceTabShellAtom: workspaceTabShell,
                workspaceTabArrangementAtom: workspaceTabArrangement
            )
        self.windowLifecycle = windowLifecycle
        self.repoCache = repoCache
        self.uiState = uiState
        self.managementLayer = managementLayer
        self.sessionRuntime = sessionRuntime
        self.welcome = welcome
    }

    var paneDisplay: PaneDisplayDerived {
        PaneDisplayDerived()
    }

    var workspaceLookup: WorkspaceLookupDerived {
        WorkspaceLookupDerived()
    }

    var commandContext: CommandContextDerived {
        CommandContextDerived()
    }

    lazy var attendedPane = AttendedPaneAtom(
        tabLayout: workspaceTabLayout,
        windowLifecycle: windowLifecycle,
        managementLayer: managementLayer
    )

    var tabDisplay: TabDisplayDerived {
        TabDisplayDerived()
    }

    var arrangement: ArrangementDerived {
        ArrangementDerived()
    }

    var workspaceTab: WorkspaceTabDerived {
        WorkspaceTabDerived(
            shellAtom: workspaceTabShell,
            arrangementAtom: workspaceTabArrangement
        )
    }

    var dynamicView: DynamicViewDerived {
        DynamicViewDerived()
    }
}
