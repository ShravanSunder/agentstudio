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
        let repoPrefs = RepoExplorerSidebarPrefsAtom()
        let sidebarState = WorkspaceSidebarState()
        let adapter = AgentStudioIPCSidebarAdapter(
            repoPrefs: repoPrefs,
            sidebarState: sidebarState
        )

        repoPrefs.setGroupingMode(.pane)
        sidebarState.setSidebarSurface(.inbox)

        #expect(
            try adapter.getGrouping(IPCSidebarGroupingGetParams(surface: .repo)).mode
                == IPCSidebarGroupingMode.pane
        )
        #expect(throws: AppIPCQueryError(reason: .targetNotFound)) {
            try adapter.getGrouping(IPCSidebarGroupingGetParams(surface: .inbox))
        }
        #expect(
            try adapter.getSurface(IPCSidebarSurfaceGetParams()).surface
                == IPCSidebarSurface.repo
        )
    }
}
