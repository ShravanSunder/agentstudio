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
        var didClearReadHistory = false
        var didClearAll = false
        var didToggleSort = false
        var didToggleBell = false
        var didReturnToWorktrees = false
        var selectedGroupings: [InboxNotificationGrouping] = []
        let commands = InboxNotificationCommands(
            actions: .init(
                markAllAsRead: { didMarkAllRead = true },
                clearReadHistory: { didClearReadHistory = true },
                clearAll: { didClearAll = true },
                setGrouping: { selectedGroupings.append($0) },
                toggleSort: { didToggleSort = true },
                toggleBellEnabled: { didToggleBell = true },
                returnToWorktreeSidebar: { didReturnToWorktrees = true }
            ),
            snapshot: {
                .init(
                    bellEnabled: false,
                    currentGrouping: .none,
                    currentSort: .newestFirst
                )
            }
        )

        let items = CommandBarDataSource.items(
            scope: .inbox,
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            notificationInboxCommands: commands
        )

        let ids = Set(items.map(\.id))
        #expect(
            ids
                == Set([
                    "inbox.markAllAsRead",
                    "inbox.clearReadHistory",
                    "inbox.clearAll",
                    "inbox.grouping.none",
                    "inbox.grouping.byRepo",
                    "inbox.grouping.byPane",
                    "inbox.grouping.byTab",
                    "inbox.toggleSort",
                    "inbox.toggleBell",
                    "inbox.returnToWorktrees",
                ]))
        #expect(items.contains { $0.title == "Enable bell notifications" })

        for item in items {
            runCustomAction(item)
        }

        await eventually("all inbox command callbacks should run") {
            didMarkAllRead
                && didClearReadHistory
                && didClearAll
                && didToggleSort
                && didToggleBell
                && didReturnToWorktrees
                && Set(selectedGroupings) == Set(InboxNotificationGrouping.allCases)
        }
    }

    private func runCustomAction(_ item: CommandBarItem) {
        if case .custom(let action) = item.action {
            action()
        } else {
            Issue.record("Expected \(item.id) to be a custom command")
        }
    }
}
