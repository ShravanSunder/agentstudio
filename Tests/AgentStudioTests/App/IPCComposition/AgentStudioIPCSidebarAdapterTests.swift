import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioRepoExplorer

@MainActor
@Suite("AgentStudio IPC sidebar adapter")
struct AgentStudioIPCSidebarAdapterTests {
    @Test("maps public read contracts from app atoms")
    func mapsPublicReadContractsFromAppAtoms() throws {
        let sidebarState = WorkspaceSidebarState()
        let repoPrefs = RepoExplorerSidebarPrefsAtom(sidebarState: sidebarState)
        let adapter = AgentStudioIPCSidebarAdapter(
            repoPrefs: repoPrefs,
            sidebarState: sidebarState
        )

        repoPrefs.setGroupingMode(.activity, for: .panes)
        sidebarState.setSidebarSurface(.panes)

        #expect(
            try adapter.getGrouping(IPCSidebarGroupingGetParams(surface: .repo)).mode
                == IPCSidebarGroupingMode.repo
        )
        #expect(
            try adapter.getGrouping(IPCSidebarGroupingGetParams(surface: .panes)).mode
                == IPCSidebarGroupingMode.activity
        )
        #expect(throws: AppIPCQueryError(reason: .targetNotFound)) {
            try adapter.getGrouping(IPCSidebarGroupingGetParams(surface: .inbox))
        }
        #expect(
            try adapter.getSurface(IPCSidebarSurfaceGetParams()).surface
                == IPCSidebarSurface.panes
        )
    }
}
