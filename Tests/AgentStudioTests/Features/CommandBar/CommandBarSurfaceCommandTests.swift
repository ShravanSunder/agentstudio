import Testing

@testable import AgentStudio

@MainActor
@Suite("Command bar surface commands")
struct CommandBarSurfaceCommandTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("commands scope includes sidebar and drawer commands with shortcut labels")
    func commandsScopeIncludesSidebarAndDrawerCommandsWithShortcutLabels() {
        let store = WorkspaceStore()

        let items = CommandBarDataSource.items(
            scope: .commands,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: CommandDispatcher.shared
        )

        let sidebarInbox = items.first { $0.command == .showInboxNotifications }
        let paneInbox = items.first { $0.command == .showPaneInboxNotifications }
        let worktreeSidebar = items.first { $0.command == .showWorktreeSidebar }

        #expect(sidebarInbox?.title == "Toggle Inbox")
        #expect(sidebarInbox?.group == "Window")
        #expect(sidebarInbox?.shortcutTrigger == AppShortcut.showInboxNotifications.trigger)
        #expect(sidebarInbox?.shortcutKeys?.map(\.symbol).joined() == "⌘I")

        #expect(paneInbox?.title == "Show Pane Inbox")
        #expect(paneInbox?.group == "Window")
        #expect(paneInbox?.shortcutTrigger == AppShortcut.showPaneInboxNotifications.trigger)
        #expect(paneInbox?.shortcutKeys?.map(\.symbol).joined() == "⌘⇧I")

        #expect(worktreeSidebar?.title == "Toggle Worktrees")
        #expect(worktreeSidebar?.group == "Window")
        #expect(worktreeSidebar?.shortcutTrigger == AppShortcut.showWorktreeSidebar.trigger)
        #expect(worktreeSidebar?.shortcutKeys?.map(\.symbol).joined() == "⌘S")
    }
}
