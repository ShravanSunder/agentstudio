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
    func inboxScopeExposesCallbacks() async throws {
        var didMarkAllRead = false
        var didClearReadHistory = false
        var didClearAll = false
        var didToggleSort = false
        var didToggleBell = false
        var didReturnToWorktrees = false
        let commands = InboxNotificationCommands(
            actions: .init(
                markAllAsRead: { didMarkAllRead = true },
                clearReadHistory: { didClearReadHistory = true },
                clearAll: { didClearAll = true },
                setGrouping: { _ in },
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
        let clearReadHistoryItem = try #require(items.first { $0.id == "inbox.clearReadHistory" })
        #expect(clearReadHistoryItem.command == .clearReadInboxNotifications)
        #expect(clearReadHistoryItem.icon == .system(.deleteLeft))
        if case .dispatch(.clearReadInboxNotifications) = clearReadHistoryItem.action {
            didClearReadHistory = true
        } else {
            Issue.record("Expected inbox.clearReadHistory to dispatch clearReadInboxNotifications")
        }
        let clearAllItem = try #require(items.first { $0.id == "inbox.clearAll" })
        #expect(clearAllItem.command == .clearAllInboxNotifications)
        #expect(clearAllItem.icon == .system(.deleteLeft))
        if case .dispatch(.clearAllInboxNotifications) = clearAllItem.action {
            didClearAll = true
        } else {
            Issue.record("Expected inbox.clearAll to dispatch clearAllInboxNotifications")
        }
        let toggleSortItem = try #require(items.first { $0.id == "inbox.toggleSort" })
        #expect(toggleSortItem.command == .toggleInboxNotificationSort)
        #expect(toggleSortItem.icon == .system(.arrowUpArrowDown))
        if case .dispatch(.toggleInboxNotificationSort) = toggleSortItem.action {
            didToggleSort = true
        } else {
            Issue.record("Expected inbox.toggleSort to dispatch toggleInboxNotificationSort")
        }
        let groupingCommandsById: [String: AppCommand] = [
            "inbox.grouping.none": .setInboxGroupingNone,
            "inbox.grouping.byRepo": .setInboxGroupingRepo,
            "inbox.grouping.byPane": .setInboxGroupingPane,
            "inbox.grouping.byTab": .setInboxGroupingTab,
        ]
        try assertGroupingCommands(groupingCommandsById, in: items)

        for item in items {
            guard item.id != "inbox.clearReadHistory",
                item.id != "inbox.clearAll",
                item.id != "inbox.toggleSort",
                !groupingCommandsById.keys.contains(item.id)
            else { continue }
            runCustomAction(item)
        }

        await eventually("all inbox command callbacks should run") {
            didMarkAllRead
                && didClearReadHistory
                && didClearAll
                && didToggleSort
                && didToggleBell
                && didReturnToWorktrees
        }
    }

    private func runCustomAction(_ item: CommandBarItem) {
        if case .custom(let action) = item.action {
            action()
        } else {
            Issue.record("Expected \(item.id) to be a custom command")
        }
    }

    private func assertGroupingCommands(
        _ groupingCommandsById: [String: AppCommand],
        in items: [CommandBarItem]
    ) throws {
        for (id, command) in groupingCommandsById {
            let item = try #require(items.first { $0.id == id })
            #expect(item.command == command)
            #expect(item.title == command.definition.label)
            guard case .dispatch(let dispatchedCommand) = item.action, dispatchedCommand == command else {
                Issue.record("Expected \(id) to dispatch \(command.rawValue)")
                continue
            }
        }
    }
}
