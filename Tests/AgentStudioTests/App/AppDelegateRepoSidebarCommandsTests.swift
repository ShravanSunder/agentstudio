import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioRepoExplorer

@MainActor
@Suite("AppDelegate sidebar commands")
struct AppDelegateRepoSidebarCommandsTests {
    @Test("screen and setting commands mutate only their declared sidebar surface")
    func screenAndSettingCommandsMutateOnlyTheirDeclaredSidebarSurface() {
        let delegate = AppDelegate()
        let atoms = AtomRegistry()
        delegate.atomStore = atoms

        #expect(delegate.execute(.showPanesSidebar))
        #expect(atoms.core.workspaceSidebarState.sidebarSurface == .panes)
        #expect(delegate.execute(.setPanesGroupingTab))
        #expect(delegate.execute(.setPanesSubgroupNone))
        #expect(delegate.execute(.setPanesSortFieldName))
        #expect(delegate.execute(.togglePanesSortDirection))
        #expect(delegate.execute(.togglePanesShowsPinned))

        #expect(atoms.repoExplorerSidebarPrefs.groupingMode(for: .panes) == .tab)
        #expect(atoms.repoExplorerSidebarPrefs.subgroupMode(for: .panes) == .ungrouped)
        #expect(atoms.repoExplorerSidebarPrefs.sortField(for: .panes) == .name)
        #expect(atoms.repoExplorerSidebarPrefs.sortDirection(for: .panes) == .descending)
        #expect(!atoms.repoExplorerSidebarPrefs.showsPinned(for: .panes))

        #expect(!delegate.canExecute(.setReposSubgroupActivity))
        #expect(!delegate.execute(.setReposSubgroupActivity))
        #expect(atoms.repoExplorerSidebarPrefs.subgroupMode(for: .repos) == .ungrouped)

        #expect(delegate.execute(.showReposSidebar))
        #expect(delegate.execute(.setReposSubgroupActivity))
        #expect(delegate.execute(.setReposSortFieldActivity))
        #expect(atoms.repoExplorerSidebarPrefs.subgroupMode(for: .repos) == .activity)
        #expect(atoms.repoExplorerSidebarPrefs.sortField(for: .repos) == .activity)
        #expect(atoms.repoExplorerSidebarPrefs.groupingMode(for: .panes) == .tab)
    }

    @Test("activity grouping rejects subgroup mutations without overwriting saved choice")
    func activityGroupingRejectsSubgroupMutationsWithoutOverwritingSavedChoice() {
        let delegate = AppDelegate()
        let atoms = AtomRegistry()
        delegate.atomStore = atoms
        atoms.core.workspaceSidebarState.setSidebarSurface(.panes)
        atoms.repoExplorerSidebarPrefs.setSubgroupMode(.activity, for: .panes)

        #expect(delegate.execute(.setPanesGroupingActivity))
        #expect(atoms.repoExplorerSidebarPrefs.subgroupMode(for: .panes) == .ungrouped)
        #expect(!delegate.canExecute(.setPanesSubgroupNone))
        #expect(!delegate.execute(.setPanesSubgroupNone))

        #expect(delegate.execute(.setPanesGroupingRepo))
        #expect(atoms.repoExplorerSidebarPrefs.subgroupMode(for: .panes) == .activity)
    }

    @Test("screen commands report state unavailable when atoms are missing")
    func screenCommandsReportStateUnavailableWhenAtomsAreMissing() {
        let delegate = AppDelegate()

        #expect(!delegate.canExecute(.showReposSidebar))
        #expect(!delegate.execute(.showReposSidebar))
        #expect(!delegate.canExecute(.setReposSortFieldName))
        #expect(!delegate.execute(.setReposSortFieldName))
    }
}
