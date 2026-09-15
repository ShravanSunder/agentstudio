import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioRepoExplorer

@MainActor
@Suite("AppDelegate sidebar commands", .serialized)
struct AppDelegateRepoSidebarCommandsTests {
    @Test("Panes use fixed recent activity organization despite stored or requested alternatives")
    func panesUseFixedRecentActivityOrganization() {
        let delegate = AppDelegate()
        let atoms = AtomRegistry()
        delegate.atomStore = atoms
        atoms.core.workspaceSidebarState.setSidebarSurface(.panes)
        atoms.core.workspaceSidebarState.setPaneGroupingMode(.tab)
        atoms.core.workspaceSidebarState.setPaneSubgroupMode(.activity)
        let prefs = atoms.repoExplorerSidebarPrefs
        prefs.setSortField(.name, for: .panes)
        prefs.setSortDirection(.ascending, for: .panes)

        #expect(prefs.groupingMode == .activity)
        #expect(prefs.subgroupMode == .ungrouped)
        #expect(prefs.sortField == .activity)
        #expect(prefs.sortDirection == .descending)
        for command in [
            AppCommand.setPanesGroupingRepo, .setPanesGroupingTab, .setPanesGroupingActivity,
            .setPanesSubgroupNone, .setPanesSubgroupActivity,
            .setPanesSortFieldName, .setPanesSortFieldActivity, .togglePanesSortDirection,
        ] {
            #expect(!delegate.canExecute(command))
            #expect(!delegate.execute(command))
            #expect(command.definition.surfacePolicy == .notPresented)
        }
        #expect(delegate.execute(.togglePanesShowsPinned))
        #expect(!prefs.showsPinned)
    }

    @Test("screen and setting commands mutate only their declared sidebar surface")
    func screenAndSettingCommandsMutateOnlyTheirDeclaredSidebarSurface() {
        let delegate = AppDelegate()
        let atoms = AtomRegistry()
        delegate.atomStore = atoms

        #expect(delegate.execute(.showPanesSidebar))
        #expect(atoms.core.workspaceSidebarState.sidebarSurface == .panes)
        #expect(delegate.execute(.togglePanesShowsPinned))

        #expect(atoms.repoExplorerSidebarPrefs.groupingMode(for: .panes) == .activity)
        #expect(atoms.repoExplorerSidebarPrefs.subgroupMode(for: .panes) == .ungrouped)
        #expect(atoms.repoExplorerSidebarPrefs.sortField(for: .panes) == .activity)
        #expect(atoms.repoExplorerSidebarPrefs.sortDirection(for: .panes) == .descending)
        #expect(!atoms.repoExplorerSidebarPrefs.showsPinned(for: .panes))

        #expect(!delegate.canExecute(.setReposGroupingActivity))
        #expect(!delegate.execute(.setReposGroupingActivity))
        #expect(atoms.repoExplorerSidebarPrefs.subgroupMode(for: .repos) == .ungrouped)

        #expect(delegate.execute(.showReposSidebar))
        #expect(delegate.execute(.setReposGroupingActivity))
        #expect(delegate.execute(.setReposSortFieldActivity))
        #expect(atoms.repoExplorerSidebarPrefs.groupingMode(for: .repos) == .activity)
        #expect(atoms.repoExplorerSidebarPrefs.subgroupMode(for: .repos) == .ungrouped)
        #expect(atoms.repoExplorerSidebarPrefs.sortField(for: .repos) == .activity)
        #expect(atoms.repoExplorerSidebarPrefs.groupingMode(for: .panes) == .activity)
    }

    @Test("Repos preferences expose only Repo or Activity grouping and no subgroup")
    func reposPreferencesConstrainGroupingAndSubgroup() {
        let atoms = AtomRegistry()
        let prefs = atoms.repoExplorerSidebarPrefs

        prefs.setGroupingMode(.activity, for: .repos)
        prefs.setSubgroupMode(.activity, for: .repos)
        #expect(prefs.groupingMode(for: .repos) == .activity)
        #expect(prefs.subgroupMode(for: .repos) == .ungrouped)

        prefs.setGroupingMode(.tab, for: .repos)
        #expect(prefs.groupingMode(for: .repos) == .repo)
        #expect(atoms.core.workspaceSidebarState.repoGroupingMode == .repo)
    }

    @Test("reset preserves fixed Panes organization while resetting Repos preferences")
    func resetPreservesFixedPanesOrganization() {
        let atoms = AtomRegistry()
        let prefs = atoms.repoExplorerSidebarPrefs
        prefs.setSortField(.activity, for: .repos)
        prefs.setSortDirection(.descending, for: .repos)
        prefs.reset()
        #expect(prefs.sortField(for: .repos) == .name)
        #expect(prefs.sortDirection(for: .repos) == .ascending)
        #expect(prefs.groupingMode(for: .panes) == .activity)
        #expect(prefs.subgroupMode(for: .panes) == .ungrouped)
        #expect(prefs.sortField(for: .panes) == .activity)
        #expect(prefs.sortDirection(for: .panes) == .descending)
    }

    @Test("screen commands report state unavailable when atoms are missing")
    func screenCommandsReportStateUnavailableWhenAtomsAreMissing() {
        let delegate = AppDelegate()

        #expect(!delegate.canExecute(.showReposSidebar))
        #expect(!delegate.execute(.showReposSidebar))
        #expect(!delegate.canExecute(.setReposSortFieldName))
        #expect(!delegate.execute(.setReposSortFieldName))
    }

    @Test("focus sidebar capability and execution reject Management mode")
    func focusSidebarRejectsManagementMode() {
        let delegate = AppDelegate()
        let atoms = AtomRegistry()
        delegate.atomStore = atoms

        #expect(delegate.canExecute(.focusSidebar))
        #expect(delegate.execute(.focusSidebar))

        atoms.core.managementLayer.toggle()

        #expect(!delegate.canExecute(.focusSidebar))
        #expect(!delegate.execute(.focusSidebar))
    }
}
