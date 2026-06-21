import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Testing

@testable import AgentStudio

@MainActor
@Suite("AgentStudio IPC sidebar adapter")
struct AgentStudioIPCSidebarAdapterTests {
    @Test("maps public grouping and surface contracts to app atoms")
    func mapsPublicGroupingAndSurfaceContractsToAppAtoms() throws {
        let repoPrefs = RepoExplorerSidebarPrefsAtom()
        let inboxPrefs = InboxNotificationPrefsAtom()
        let sidebarState = WorkspaceSidebarState()
        let adapter = AgentStudioIPCSidebarAdapter(
            repoPrefs: repoPrefs,
            inboxPrefs: inboxPrefs,
            sidebarState: sidebarState
        )

        let inboxNone = try adapter.setGrouping(.init(surface: .inbox, mode: .noGrouping))
        #expect(inboxNone.mode == .noGrouping)
        #expect(inboxPrefs.grouping == .none)
        #expect(try adapter.getGrouping(.init(surface: .inbox)).mode == .noGrouping)

        let repoPane = try adapter.setGrouping(.init(surface: .repo, mode: .pane))
        #expect(repoPane.mode == .pane)
        #expect(repoPrefs.groupingMode == .pane)
        #expect(try adapter.getGrouping(.init(surface: .repo)).mode == .pane)

        let repoSurface = try adapter.setSurface(.init(surface: .repo))
        #expect(repoSurface.surface == .repo)
        #expect(sidebarState.sidebarSurface == .repos)
        #expect(try adapter.getSurface(.init()).surface == .repo)
    }

    @Test("rejects repo no-grouping without mutating repo grouping")
    func rejectsRepoNoGroupingWithoutMutatingRepoGrouping() throws {
        let repoPrefs = RepoExplorerSidebarPrefsAtom()
        let adapter = AgentStudioIPCSidebarAdapter(
            repoPrefs: repoPrefs,
            inboxPrefs: InboxNotificationPrefsAtom(),
            sidebarState: WorkspaceSidebarState()
        )

        #expect(throws: AppIPCCommandError.self) {
            try adapter.setGrouping(.init(surface: .repo, mode: .noGrouping))
        }
        #expect(repoPrefs.groupingMode == .repo)
    }
}
