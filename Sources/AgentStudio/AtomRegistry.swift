@MainActor
final class AtomRegistry {
    let activeWorkspaceSelection: ActiveWorkspaceSelectionAtom
    let workspaceIdentity: WorkspaceIdentityAtom
    let workspaceWindowMemory: WorkspaceWindowMemoryAtom
    let workspaceRepositoryTopology: WorkspaceRepositoryTopologyAtom
    let workspacePane: WorkspacePaneAtom
    let workspaceTabShell: WorkspaceTabShellAtom
    let workspaceTabArrangement: WorkspaceTabArrangementAtom
    let workspaceTabLayout: WorkspaceTabLayoutAtom
    let workspaceMutationCoordinator: WorkspaceMutationCoordinator
    let windowLifecycle: WindowLifecycleAtom
    let repoEnrichmentCache: RepoEnrichmentCacheAtom
    let recentWorkspaceTarget: RecentWorkspaceTargetAtom
    let repoCache: RepoCacheAtom
    let sidebarExpandedGroup: SidebarExpandedGroupAtom
    let sidebarCheckoutColor: SidebarCheckoutColorAtom
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
        workspaceIdentity: WorkspaceIdentityAtom = .init(),
        workspaceWindowMemory: WorkspaceWindowMemoryAtom = .init(),
        workspaceRepositoryTopology: WorkspaceRepositoryTopologyAtom = .init(),
        workspacePane: WorkspacePaneAtom = .init(),
        workspaceTabShell: WorkspaceTabShellAtom = .init(),
        workspaceTabArrangement: WorkspaceTabArrangementAtom = .init(),
        workspaceMutationCoordinator: WorkspaceMutationCoordinator? = nil,
        windowLifecycle: WindowLifecycleAtom = .init(),
        repoEnrichmentCache: RepoEnrichmentCacheAtom = .init(),
        recentWorkspaceTarget: RecentWorkspaceTargetAtom = .init(),
        sidebarExpandedGroup: SidebarExpandedGroupAtom = .init(),
        sidebarCheckoutColor: SidebarCheckoutColorAtom = .init(),
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
        self.repoEnrichmentCache = repoEnrichmentCache
        self.recentWorkspaceTarget = recentWorkspaceTarget
        self.repoCache = RepoCacheAtom(
            enrichmentCacheAtom: repoEnrichmentCache,
            recentTargetAtom: recentWorkspaceTarget
        )
        self.sidebarExpandedGroup = sidebarExpandedGroup
        self.sidebarCheckoutColor = sidebarCheckoutColor
        self.sidebarCache = SidebarCacheState(
            expandedGroupAtom: sidebarExpandedGroup,
            checkoutColorAtom: sidebarCheckoutColor
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

    var arrangementView: WorkspaceArrangementViewDerived {
        WorkspaceArrangementViewDerived(
            tabLayoutAtom: workspaceTabLayout,
            paneAtom: workspacePane,
            managementLayerAtom: managementLayer
        )
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
