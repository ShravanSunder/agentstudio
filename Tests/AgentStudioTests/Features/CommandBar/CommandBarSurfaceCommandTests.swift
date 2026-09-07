import AgentStudioCore
import AgentStudioTestSupport
import Testing

@testable import AgentStudioCommandBar

@MainActor
@Suite("Command bar surface commands")
struct CommandBarSurfaceCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("commands scope omits retired Inbox commands and retains Repo sidebar")
    func commandsScopeOmitsRetiredInboxCommandsAndRetainsRepoSidebar() {
        let store = WorkspaceStore()
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let items = CommandBarDataSource.items(
            scope: .commands,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher()
        )

        let sidebarInbox = items.first { $0.command == .showInboxNotifications }
        let paneInbox = items.first { $0.command == .showPaneInboxNotifications }
        let reposSidebar = items.first { $0.command == .showReposSidebar }

        #expect(sidebarInbox == nil)
        #expect(paneInbox == nil)

        #expect(reposSidebar?.title == "Repos")
        #expect(reposSidebar?.group == "Sidebar")
        #expect(reposSidebar?.shortcutTrigger == AppShortcut.showReposSidebar.trigger)
        #expect(reposSidebar?.shortcutKeys?.map(\.symbol).joined() == "⌘S")
    }
}
