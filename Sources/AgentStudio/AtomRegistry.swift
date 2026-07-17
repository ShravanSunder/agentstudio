@MainActor
final class AtomRegistry {
    let activeWorkspaceSelection: ActiveWorkspaceSelectionAtom
    let workspaceIdentity: WorkspaceIdentityAtom
    let workspaceWindowMemory: WorkspaceWindowMemoryAtom
    let workspaceRepositoryTopology: RepositoryTopologyAtom
    let workspacePaneGraph: WorkspacePaneGraphAtom
    let workspaceDrawerCursor: WorkspaceDrawerCursorAtom
    let workspacePane: WorkspacePaneAtom
    let workspaceTabCursor: WorkspaceTabCursorAtom
    let workspaceTabShell: WorkspaceTabShellAtom
    let workspaceTabGraph: WorkspaceTabGraphAtom
    let workspaceArrangementCursor: WorkspaceArrangementCursorAtom
    let workspacePanePresentation: WorkspacePanePresentationAtom
    let workspaceTabArrangement: WorkspaceTabArrangementAtom
    let workspaceTabLayout: WorkspaceTabLayoutAtom
    let workspaceMutationCoordinator: WorkspaceMutationCoordinator
    let windowLifecycle: WindowLifecycleAtom
    let repoEnrichmentCache: RepoEnrichmentCacheAtom
    let recentWorkspaceTarget: RecentWorkspaceTargetAtom
    let repoCache: RepoCacheAtom
    let sidebarExpandedGroup: SidebarExpandedGroupAtom
    let sidebarCache: SidebarCacheState
    let terminalActivity: TerminalActivityAtom
    let editorPreference: EditorPreferenceAtom
    let editorChooserRuntime: EditorChooserRuntimeAtom
    let editorChooser: EditorChooserState
    let inboxNotification: InboxNotificationAtom
    let inboxNotificationPrefs: InboxNotificationPrefsAtom
    let inboxSidebarMemory: InboxSidebarMemoryAtom
    let inboxSidebarRuntime: InboxSidebarRuntimeAtom
    let inboxSidebarState: InboxSidebarState
    let paneInboxPresentationState: PaneInboxPresentationAtom
    let arrangementPanelPresentation: ArrangementPanelPresentationAtom
    let workspaceSidebarMemory: WorkspaceSidebarMemoryAtom
    let sidebarFocusRuntime: SidebarFocusRuntimeAtom
    let workspaceSidebarState: WorkspaceSidebarState
    let managementLayer: ManagementLayerAtom
    let commandBarSurface: CommandBarSurfaceAtom
    let transientKeyboardSurface: TransientKeyboardSurfaceAtom
    let workspaceFocusOwner: WorkspaceFocusOwnerAtom
    let sessionRuntime: SessionRuntimeAtom
    let welcome: WelcomeAtom

    init(
        activeWorkspaceSelection: ActiveWorkspaceSelectionAtom = .init(),
        workspaceIdentity: WorkspaceIdentityAtom = .init(installationState: .awaitingCanonicalComposition),
        workspaceWindowMemory: WorkspaceWindowMemoryAtom = .init(),
        workspaceRepositoryTopology: RepositoryTopologyAtom = .init(),
        workspacePaneGraph: WorkspacePaneGraphAtom? = nil,
        workspaceDrawerCursor: WorkspaceDrawerCursorAtom? = nil,
        workspacePane: WorkspacePaneAtom? = nil,
        workspaceTabCursor: WorkspaceTabCursorAtom? = nil,
        workspaceTabShell: WorkspaceTabShellAtom? = nil,
        workspaceTabGraph: WorkspaceTabGraphAtom? = nil,
        workspaceArrangementCursor: WorkspaceArrangementCursorAtom? = nil,
        workspacePanePresentation: WorkspacePanePresentationAtom? = nil,
        workspaceTabArrangement: WorkspaceTabArrangementAtom? = nil,
        workspaceMutationCoordinator: WorkspaceMutationCoordinator? = nil,
        windowLifecycle: WindowLifecycleAtom = .init(),
        repoEnrichmentCache: RepoEnrichmentCacheAtom = .init(),
        recentWorkspaceTarget: RecentWorkspaceTargetAtom = .init(),
        sidebarExpandedGroup: SidebarExpandedGroupAtom = .init(),
        terminalActivity: TerminalActivityAtom = .init(),
        editorPreference: EditorPreferenceAtom = .init(),
        editorChooserRuntime: EditorChooserRuntimeAtom = .init(),
        inboxNotification: InboxNotificationAtom = .init(),
        inboxNotificationPrefs: InboxNotificationPrefsAtom = .init(),
        inboxSidebarMemory: InboxSidebarMemoryAtom = .init(),
        inboxSidebarRuntime: InboxSidebarRuntimeAtom = .init(),
        paneInboxPresentationState: PaneInboxPresentationAtom = .init(),
        arrangementPanelPresentation: ArrangementPanelPresentationAtom = .init(),
        workspaceSidebarMemory: WorkspaceSidebarMemoryAtom = .init(),
        sidebarFocusRuntime: SidebarFocusRuntimeAtom = .init(),
        managementLayer: ManagementLayerAtom = .init(),
        commandBarSurface: CommandBarSurfaceAtom = .init(),
        transientKeyboardSurface: TransientKeyboardSurfaceAtom = .init(),
        workspaceFocusOwner: WorkspaceFocusOwnerAtom = .init(),
        sessionRuntime: SessionRuntimeAtom = .init(),
        welcome: WelcomeAtom = .init()
    ) {
        self.activeWorkspaceSelection = activeWorkspaceSelection
        self.workspaceIdentity = workspaceIdentity
        self.workspaceWindowMemory = workspaceWindowMemory
        self.workspaceRepositoryTopology = workspaceRepositoryTopology
        let resolvedWorkspacePane = Self.resolveWorkspacePane(
            workspacePane: workspacePane,
            graphAtom: workspacePaneGraph,
            drawerCursorAtom: workspaceDrawerCursor,
            repositoryTopologyAtom: workspaceRepositoryTopology,
            repoEnrichmentCacheAtom: repoEnrichmentCache
        )
        self.workspacePane = resolvedWorkspacePane
        self.workspacePaneGraph = resolvedWorkspacePane.graphAtom
        self.workspaceDrawerCursor = resolvedWorkspacePane.drawerCursorAtom

        let resolvedWorkspaceTabShell = Self.resolveWorkspaceTabShell(
            workspaceTabShell: workspaceTabShell,
            cursorAtom: workspaceTabCursor
        )
        self.workspaceTabShell = resolvedWorkspaceTabShell
        self.workspaceTabCursor = resolvedWorkspaceTabShell.cursorAtom

        let resolvedWorkspaceTabArrangement = Self.resolveWorkspaceTabArrangement(
            workspaceTabArrangement: workspaceTabArrangement,
            graphAtom: workspaceTabGraph,
            cursorAtom: workspaceArrangementCursor,
            presentationAtom: workspacePanePresentation
        )
        self.workspaceTabArrangement = resolvedWorkspaceTabArrangement
        self.workspaceTabGraph = resolvedWorkspaceTabArrangement.graphAtom
        self.workspaceArrangementCursor = resolvedWorkspaceTabArrangement.cursorAtom
        self.workspacePanePresentation = resolvedWorkspaceTabArrangement.presentationAtom
        self.workspaceTabLayout = WorkspaceTabLayoutAtom(
            shellAtom: self.workspaceTabShell,
            arrangementAtom: self.workspaceTabArrangement
        )
        self.workspaceMutationCoordinator =
            workspaceMutationCoordinator
            ?? WorkspaceMutationCoordinator(
                repositoryTopologyAtom: workspaceRepositoryTopology,
                workspacePaneAtom: self.workspacePane,
                workspaceTabShellAtom: self.workspaceTabShell,
                workspaceTabArrangementAtom: self.workspaceTabArrangement
            )
        self.windowLifecycle = windowLifecycle
        self.repoEnrichmentCache = repoEnrichmentCache
        self.recentWorkspaceTarget = recentWorkspaceTarget
        self.repoCache = RepoCacheAtom(
            enrichmentCacheAtom: repoEnrichmentCache,
            recentTargetAtom: recentWorkspaceTarget
        )
        self.sidebarExpandedGroup = sidebarExpandedGroup
        self.sidebarCache = SidebarCacheState(
            expandedGroupAtom: sidebarExpandedGroup
        )
        self.terminalActivity = terminalActivity
        self.editorPreference = editorPreference
        self.editorChooserRuntime = editorChooserRuntime
        self.editorChooser = EditorChooserState(
            preferenceAtom: editorPreference,
            runtimeAtom: editorChooserRuntime
        )
        self.inboxNotification = inboxNotification
        self.inboxNotificationPrefs = inboxNotificationPrefs
        self.inboxSidebarMemory = inboxSidebarMemory
        self.inboxSidebarRuntime = inboxSidebarRuntime
        self.inboxSidebarState = InboxSidebarState(
            memoryAtom: inboxSidebarMemory,
            runtimeAtom: inboxSidebarRuntime
        )
        self.paneInboxPresentationState = paneInboxPresentationState
        self.arrangementPanelPresentation = arrangementPanelPresentation
        self.workspaceSidebarMemory = workspaceSidebarMemory
        self.sidebarFocusRuntime = sidebarFocusRuntime
        self.workspaceSidebarState = WorkspaceSidebarState(
            memoryAtom: workspaceSidebarMemory,
            focusAtom: sidebarFocusRuntime
        )
        self.managementLayer = managementLayer
        self.commandBarSurface = commandBarSurface
        self.transientKeyboardSurface = transientKeyboardSurface
        self.workspaceFocusOwner = workspaceFocusOwner
        self.sessionRuntime = sessionRuntime
        self.welcome = welcome
    }

    private static func resolveWorkspacePane(
        workspacePane: WorkspacePaneAtom?,
        graphAtom: WorkspacePaneGraphAtom?,
        drawerCursorAtom: WorkspaceDrawerCursorAtom?,
        repositoryTopologyAtom: RepositoryTopologyAtom,
        repoEnrichmentCacheAtom: RepoEnrichmentCacheAtom
    ) -> WorkspacePaneAtom {
        let resolved =
            workspacePane
            ?? WorkspacePaneAtom(
                graphAtom: graphAtom ?? WorkspacePaneGraphAtom(),
                drawerCursorAtom: drawerCursorAtom ?? WorkspaceDrawerCursorAtom(),
                repositoryTopologyAtom: repositoryTopologyAtom,
                repoEnrichmentCacheAtom: repoEnrichmentCacheAtom
            )
        if let graphAtom {
            precondition(
                resolved.graphAtom === graphAtom,
                "workspacePane and workspacePaneGraph must reference the same backing owner"
            )
        }
        if let drawerCursorAtom {
            precondition(
                resolved.drawerCursorAtom === drawerCursorAtom,
                "workspacePane and workspaceDrawerCursor must reference the same backing owner"
            )
        }
        return resolved
    }

    private static func resolveWorkspaceTabShell(
        workspaceTabShell: WorkspaceTabShellAtom?,
        cursorAtom: WorkspaceTabCursorAtom?
    ) -> WorkspaceTabShellAtom {
        let resolved = workspaceTabShell ?? WorkspaceTabShellAtom(cursorAtom: cursorAtom ?? WorkspaceTabCursorAtom())
        if let cursorAtom {
            precondition(
                resolved.cursorAtom === cursorAtom,
                "workspaceTabShell and workspaceTabCursor must reference the same backing owner"
            )
        }
        return resolved
    }

    private static func resolveWorkspaceTabArrangement(
        workspaceTabArrangement: WorkspaceTabArrangementAtom?,
        graphAtom: WorkspaceTabGraphAtom?,
        cursorAtom: WorkspaceArrangementCursorAtom?,
        presentationAtom: WorkspacePanePresentationAtom?
    ) -> WorkspaceTabArrangementAtom {
        let resolved =
            workspaceTabArrangement
            ?? WorkspaceTabArrangementAtom(
                graphAtom: graphAtom ?? WorkspaceTabGraphAtom(),
                cursorAtom: cursorAtom ?? WorkspaceArrangementCursorAtom(),
                presentationAtom: presentationAtom ?? WorkspacePanePresentationAtom()
            )
        if let graphAtom {
            precondition(
                resolved.graphAtom === graphAtom,
                "workspaceTabArrangement and workspaceTabGraph must reference the same backing owner"
            )
        }
        if let cursorAtom {
            precondition(
                resolved.cursorAtom === cursorAtom,
                "workspaceTabArrangement and workspaceArrangementCursor must reference the same backing owner"
            )
        }
        if let presentationAtom {
            precondition(
                resolved.presentationAtom === presentationAtom,
                "workspaceTabArrangement and workspacePanePresentation must reference the same backing owner"
            )
        }
        return resolved
    }

    var paneDisplay: PaneDisplayDerived {
        PaneDisplayDerived()
    }

    var workspacePaneDerived: WorkspacePaneDerived {
        WorkspacePaneDerived(
            graphAtom: workspacePaneGraph,
            drawerCursorAtom: workspaceDrawerCursor,
            repositoryTopologyAtom: workspaceRepositoryTopology,
            repoEnrichmentCacheAtom: repoEnrichmentCache
        )
    }

    var workspaceLookup: WorkspaceLookupDerived {
        WorkspaceLookupDerived()
    }

    var workspacePaneFocus: WorkspacePaneFocusDerived {
        WorkspacePaneFocusDerived()
    }

    lazy var attendedPane = AttendedPaneDerived(
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

    var arrangementView: WorkspaceArrangementViewDerived {
        WorkspaceArrangementViewDerived(
            tabLayoutAtom: workspaceTabLayout,
            paneAtom: workspacePane,
            managementLayerAtom: managementLayer
        )
    }

    var workspaceTab: WorkspaceTabLayoutDerived {
        WorkspaceTabLayoutDerived(
            shellAtom: workspaceTabShell,
            arrangementAtom: workspaceTabArrangement
        )
    }

    var dynamicView: DynamicViewDerived {
        DynamicViewDerived()
    }
}
