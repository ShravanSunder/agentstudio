import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Testing

@testable import AgentStudio

@MainActor
@Suite("AgentStudio IPC sidebar adapter")
struct AgentStudioIPCSidebarAdapterTests {
    @Test("maps public read contracts from app atoms")
    func mapsPublicReadContractsFromAppAtoms() throws {
        let repoPrefs = RepoExplorerSidebarPrefsAtom()
        let inboxPrefs = InboxNotificationPrefsAtom()
        let sidebarState = WorkspaceSidebarState()
        let adapter = AgentStudioIPCSidebarAdapter(
            repoPrefs: repoPrefs,
            inboxPrefs: inboxPrefs,
            sidebarState: sidebarState
        )

        repoPrefs.setGroupingMode(.pane)
        inboxPrefs.setGrouping(.none)
        sidebarState.setSidebarSurface(.inbox)

        #expect(try adapter.getGrouping(.init(surface: .repo)).mode == .pane)
        #expect(try adapter.getGrouping(.init(surface: .inbox)).mode == .noGrouping)
        #expect(try adapter.getSurface(.init()).surface == .inbox)
    }
}
