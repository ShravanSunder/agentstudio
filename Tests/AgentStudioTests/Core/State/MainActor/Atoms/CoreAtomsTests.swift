import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("CoreAtoms")
struct CoreAtomsTests {
    @Test("typed initializer retains every directly injected Core owner")
    func typedInitializerRetainsDirectCoreOwners() {
        let activeWorkspaceSelection = ActiveWorkspaceSelectionAtom()
        let workspaceIdentity = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
        let workspaceWindowMemory = WorkspaceWindowMemoryAtom()
        let workspaceRepositoryTopology = RepositoryTopologyAtom()
        let workspacePaneGraph = WorkspacePaneGraphAtom()
        let workspaceDrawerCursor = WorkspaceDrawerCursorAtom()
        let workspaceTabCursor = WorkspaceTabCursorAtom()
        let workspaceTabGraph = WorkspaceTabGraphAtom()
        let workspaceArrangementCursor = WorkspaceArrangementCursorAtom()
        let workspacePanePresentation = WorkspacePanePresentationAtom()
        let windowLifecycle = WindowLifecycleAtom()
        let repoEnrichmentCache = RepoEnrichmentCacheAtom()
        let applicationEntityRecency = ApplicationEntityRecencyAtom()
        let workspaceEntityRecency = WorkspaceEntityRecencyAtom()
        let sidebarExpandedGroup = SidebarExpandedGroupAtom()
        let arrangementPanelPresentation = ArrangementPanelPresentationAtom()
        let workspaceSidebarMemory = WorkspaceSidebarMemoryAtom()
        let sidebarFocusRuntime = SidebarFocusRuntimeAtom()
        let sidebarVisibleWorktreesRuntime = SidebarVisibleWorktreesRuntimeAtom()
        let managementLayer = ManagementLayerAtom()
        let commandBarSurface = CommandBarSurfaceAtom()
        let transientKeyboardSurface = TransientKeyboardSurfaceAtom()
        let workspaceFocusOwner = WorkspaceFocusOwnerAtom()
        let sessionRuntime = SessionRuntimeAtom()
        let welcome = WelcomeAtom()

        let coreAtoms = CoreAtoms(
            activeWorkspaceSelection: activeWorkspaceSelection,
            workspaceIdentity: workspaceIdentity,
            workspaceWindowMemory: workspaceWindowMemory,
            workspaceRepositoryTopology: workspaceRepositoryTopology,
            workspacePaneGraph: workspacePaneGraph,
            workspaceDrawerCursor: workspaceDrawerCursor,
            workspaceTabCursor: workspaceTabCursor,
            workspaceTabGraph: workspaceTabGraph,
            workspaceArrangementCursor: workspaceArrangementCursor,
            workspacePanePresentation: workspacePanePresentation,
            windowLifecycle: windowLifecycle,
            repoEnrichmentCache: repoEnrichmentCache,
            applicationEntityRecency: applicationEntityRecency,
            workspaceEntityRecency: workspaceEntityRecency,
            sidebarExpandedGroup: sidebarExpandedGroup,
            arrangementPanelPresentation: arrangementPanelPresentation,
            workspaceSidebarMemory: workspaceSidebarMemory,
            sidebarFocusRuntime: sidebarFocusRuntime,
            sidebarVisibleWorktreesRuntime: sidebarVisibleWorktreesRuntime,
            managementLayer: managementLayer,
            commandBarSurface: commandBarSurface,
            transientKeyboardSurface: transientKeyboardSurface,
            workspaceFocusOwner: workspaceFocusOwner,
            sessionRuntime: sessionRuntime,
            welcome: welcome
        )

        #expect(coreAtoms.activeWorkspaceSelection === activeWorkspaceSelection)
        #expect(coreAtoms.workspaceIdentity === workspaceIdentity)
        #expect(coreAtoms.workspaceWindowMemory === workspaceWindowMemory)
        #expect(coreAtoms.workspaceRepositoryTopology === workspaceRepositoryTopology)
        #expect(coreAtoms.workspacePaneGraph === workspacePaneGraph)
        #expect(coreAtoms.workspaceDrawerCursor === workspaceDrawerCursor)
        #expect(coreAtoms.workspaceTabCursor === workspaceTabCursor)
        #expect(coreAtoms.workspaceTabGraph === workspaceTabGraph)
        #expect(coreAtoms.workspaceArrangementCursor === workspaceArrangementCursor)
        #expect(coreAtoms.workspacePanePresentation === workspacePanePresentation)
        #expect(coreAtoms.windowLifecycle === windowLifecycle)
        #expect(coreAtoms.repoEnrichmentCache === repoEnrichmentCache)
        #expect(coreAtoms.applicationEntityRecency === applicationEntityRecency)
        #expect(coreAtoms.workspaceEntityRecency === workspaceEntityRecency)
        #expect(coreAtoms.sidebarExpandedGroup === sidebarExpandedGroup)
        #expect(coreAtoms.arrangementPanelPresentation === arrangementPanelPresentation)
        #expect(coreAtoms.workspaceSidebarMemory === workspaceSidebarMemory)
        #expect(coreAtoms.sidebarFocusRuntime === sidebarFocusRuntime)
        #expect(coreAtoms.sidebarVisibleWorktreesRuntime === sidebarVisibleWorktreesRuntime)
        #expect(coreAtoms.managementLayer === managementLayer)
        #expect(coreAtoms.commandBarSurface === commandBarSurface)
        #expect(coreAtoms.transientKeyboardSurface === transientKeyboardSurface)
        #expect(coreAtoms.workspaceFocusOwner === workspaceFocusOwner)
        #expect(coreAtoms.sessionRuntime === sessionRuntime)
        #expect(coreAtoms.welcome === welcome)
    }

    @Test("Core facades share the canonical backing owners")
    func facadesShareCanonicalBackingOwners() {
        let coreAtoms = CoreAtoms()

        #expect(coreAtoms.workspacePane.graphAtom === coreAtoms.workspacePaneGraph)
        #expect(coreAtoms.workspacePane.drawerCursorAtom === coreAtoms.workspaceDrawerCursor)
        #expect(coreAtoms.workspaceTabShell.cursorAtom === coreAtoms.workspaceTabCursor)
        #expect(coreAtoms.workspaceTabArrangement.graphAtom === coreAtoms.workspaceTabGraph)
        #expect(coreAtoms.workspaceTabArrangement.cursorAtom === coreAtoms.workspaceArrangementCursor)
        #expect(coreAtoms.workspaceTabArrangement.presentationAtom === coreAtoms.workspacePanePresentation)
        #expect(coreAtoms.workspaceTabLayout.shellAtom === coreAtoms.workspaceTabShell)
        #expect(coreAtoms.workspaceTabLayout.arrangementAtom === coreAtoms.workspaceTabArrangement)
        #expect(coreAtoms.workspaceMutationCoordinator.repositoryTopologyAtom === coreAtoms.workspaceRepositoryTopology)
        #expect(coreAtoms.repoCache.enrichmentCacheAtom === coreAtoms.repoEnrichmentCache)

        let sidebarGroup = SidebarGroupKey("repo:core-atoms")
        coreAtoms.sidebarExpandedGroup.setGroupExpanded(sidebarGroup, isExpanded: true)
        #expect(coreAtoms.sidebarCache.expandedGroups.contains(sidebarGroup))

        coreAtoms.workspaceSidebarMemory.setSidebarSurface(.inbox)
        coreAtoms.sidebarFocusRuntime.setSidebarHasFocus(true)
        #expect(coreAtoms.workspaceSidebarState.sidebarSurface == .inbox)
        #expect(coreAtoms.workspaceSidebarState.sidebarHasFocus)
    }

    @Test("lazy attended-pane reader observes the exact canonical backing owners")
    func attendedPaneObservesCanonicalBackingOwners() {
        let coreAtoms = CoreAtoms()
        let paneId = UUID()
        let tab = Tab(paneId: paneId)
        coreAtoms.workspaceTabLayout.appendTab(tab)
        coreAtoms.workspaceTabLayout.setActiveTab(tab.id)

        let attendedPane = coreAtoms.attendedPane
        #expect(attendedPane.attendedPaneId == nil)

        let windowId = UUID()
        coreAtoms.windowLifecycle.recordWindowRegistered(windowId)
        coreAtoms.windowLifecycle.recordWindowBecameKey(windowId)
        #expect(attendedPane.attendedPaneId == paneId)

        coreAtoms.managementLayer.activate()
        #expect(attendedPane.attendedPaneId == nil)
    }
}
