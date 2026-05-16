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
    let sidebarCache: SidebarCacheAtom
    let terminalActivity: TerminalActivityAtom
    let editorChooser: EditorChooserAtom
    let paneInboxPresentationState: PaneInboxPresentationAtom
    let uiState: UIStateAtom
    let managementLayer: ManagementLayerAtom
    let workspaceFocusOwner: WorkspaceFocusOwnerAtom
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
        sidebarCache: SidebarCacheAtom = .init(),
        terminalActivity: TerminalActivityAtom = .init(),
        editorChooser: EditorChooserAtom = .init(),
        paneInboxPresentationState: PaneInboxPresentationAtom = .init(),
        uiState: UIStateAtom = .init(),
        managementLayer: ManagementLayerAtom = .init(),
        workspaceFocusOwner: WorkspaceFocusOwnerAtom = .init(),
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
        self.sidebarCache = sidebarCache
        self.terminalActivity = terminalActivity
        self.editorChooser = editorChooser
        self.paneInboxPresentationState = paneInboxPresentationState
        self.uiState = uiState
        self.managementLayer = managementLayer
        self.workspaceFocusOwner = workspaceFocusOwner
        self.sessionRuntime = sessionRuntime
        self.welcome = welcome
    }

    var paneDisplay: PaneDisplayDerived {
        PaneDisplayDerived()
    }

    var workspaceLookup: WorkspaceLookupDerived {
        WorkspaceLookupDerived()
    }

    var workspacePaneFocus: WorkspacePaneFocusDerived {
        WorkspacePaneFocusDerived()
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
