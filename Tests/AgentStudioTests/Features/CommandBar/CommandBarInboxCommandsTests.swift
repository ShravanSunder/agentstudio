import Testing

@testable import AgentStudio

@MainActor
@Suite("CommandBar inbox commands")
struct CommandBarInboxCommandsTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("inbox scope is empty when commands are unavailable")
    func inboxScopeEmptyWithoutCommands() {
        let items = CommandBarDataSource.items(
            scope: .inbox,
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            notificationInboxCommands: nil
        )

        #expect(items.isEmpty)
    }

    @Test("inbox scope exposes notification command callbacks")
    func inboxScopeExposesCallbacks() async {
        var didMarkAllRead = false
        let commands = InboxNotificationCommands(
            markAllAsRead: { didMarkAllRead = true },
            clearReadHistory: {},
            clearAll: {},
            setGrouping: { _ in },
            toggleSort: {},
            toggleBellEnabled: {},
            returnToWorktreeSidebar: {},
            bellEnabled: { false },
            currentGrouping: { .none },
            currentSort: { .newestFirst }
        )

        let items = CommandBarDataSource.items(
            scope: .inbox,
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            notificationInboxCommands: commands
        )

        #expect(items.map(\.id).contains("inbox.markAllAsRead"))
        #expect(items.map(\.id).contains("inbox.toggleBell"))
        #expect(items.contains { $0.title == "Enable bell notifications" })

        let markAllRead = items.first { $0.id == "inbox.markAllAsRead" }
        if case .custom(let action) = markAllRead?.action {
            action()
        } else {
            Issue.record("Expected mark all as read to be a custom command")
        }
        await eventually("mark all as read callback should run") {
            didMarkAllRead
        }
    }
}
