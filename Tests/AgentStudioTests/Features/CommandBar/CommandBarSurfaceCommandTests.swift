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
        let drawerInbox = items.first { $0.command == .showDrawerInboxNotifications }
        let worktreeSidebar = items.first { $0.command == .showWorktreeSidebar }

        #expect(sidebarInbox?.title == "Toggle Inbox")
        #expect(sidebarInbox?.group == "Window")
        #expect(sidebarInbox?.shortcutTrigger == AppShortcut.showInboxNotifications.trigger)
        #expect(sidebarInbox?.shortcutKeys?.map(\.symbol).joined() == "⌘I")

        #expect(drawerInbox?.title == "Show Drawer Inbox")
        #expect(drawerInbox?.group == "Window")
        #expect(drawerInbox?.shortcutTrigger == AppShortcut.showDrawerInboxNotifications.trigger)
        #expect(drawerInbox?.shortcutKeys?.map(\.symbol).joined() == "⌘⇧I")

        #expect(worktreeSidebar?.title == "Toggle Worktrees")
        #expect(worktreeSidebar?.group == "Window")
        #expect(worktreeSidebar?.shortcutTrigger == AppShortcut.showWorktreeSidebar.trigger)
        #expect(worktreeSidebar?.shortcutKeys?.map(\.symbol).joined() == "⌘S")
    }
}
