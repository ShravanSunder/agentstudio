import Testing

@testable import AgentStudio

@MainActor
@Suite
struct CommandBarShortcutRouterTests {
    @Test
    func escapeRoutesToDismiss() {
        let route = CommandBarShortcutRouter.route(
            trigger: ShortcutTrigger(key: .escape, modifiers: []),
            selectedItem: nil,
            displayedItems: []
        )

        guard case .dismiss = route else {
            Issue.record("Expected dismiss route")
            return
        }
    }

    @Test
    func reservedPaletteShortcutRoutesToScopeSwitch() {
        let route = CommandBarShortcutRouter.route(
            trigger: AppShortcut.showCommandBarCommands.trigger,
            selectedItem: nil,
            displayedItems: []
        )

        guard case .showPrefix(let prefix) = route else {
            Issue.record("Expected showPrefix route")
            return
        }
        #expect(prefix == ">")
    }

    @Test
    func rowShortcutBeatsSelectedItemFallback() throws {
        let actionsLevel = CommandBarDataSource.buildWorktreeActionsLevel(
            presence: makeWorktreePresence(paneCount: 1),
            canOpenInCurrentTab: true
        )
        let selectedItem = try #require(actionsLevel.items.last)

        let route = CommandBarShortcutRouter.route(
            trigger: ShortcutTrigger(key: .enter, modifiers: [.command]),
            selectedItem: selectedItem,
            displayedItems: actionsLevel.items
        )

        guard case .executeRow(let item) = route else {
            Issue.record("Expected row shortcut routing to execute the matching row")
            return
        }
        #expect(item.title == "New pane in new tab")
    }

    @Test
    func enterModifierFallsBackToSelectedItemWhenNoShortcutMatches() throws {
        let selectedItem = makeCommandBarItem(id: "selected")

        let route = CommandBarShortcutRouter.route(
            trigger: ShortcutTrigger(key: .enter, modifiers: [.command]),
            selectedItem: selectedItem,
            displayedItems: [selectedItem]
        )

        guard case .executeSelected(let modifier) = route else {
            Issue.record("Expected executeSelected route")
            return
        }
        #expect(modifier == .command)
    }

    @Test
    func nonEnterNonRowShortcutFallsThrough() {
        let route = CommandBarShortcutRouter.route(
            trigger: ShortcutTrigger(key: .character(.a), modifiers: [.command]),
            selectedItem: nil,
            displayedItems: []
        )

        guard case .unhandled = route else {
            Issue.record("Expected unhandled route")
            return
        }
    }

    @Test
    func plainEnterFallsThroughToTextSystemPath() {
        let route = CommandBarShortcutRouter.route(
            trigger: ShortcutTrigger(key: .enter, modifiers: []),
            selectedItem: makeCommandBarItem(id: "selected"),
            displayedItems: []
        )

        guard case .unhandled = route else {
            Issue.record("Expected unhandled route")
            return
        }
    }

    @Test
    func rowShortcutMatchesScrollToBottomShortcut() {
        let item = CommandBarItem(
            id: "cmd-scrollToBottom",
            title: "Scroll to Bottom",
            icon: .system(.arrowDownToLine),
            shortcutTrigger: AppShortcut.scrollToBottom.trigger,
            group: "Pane",
            groupPriority: 0,
            action: .dispatch(.scrollToBottom),
            command: .scrollToBottom
        )

        let route = CommandBarShortcutRouter.route(
            trigger: AppShortcut.scrollToBottom.trigger,
            selectedItem: nil,
            displayedItems: [item]
        )

        guard case .executeRow(let matchedItem) = route else {
            Issue.record("Expected executeRow route for scroll-to-bottom shortcut")
            return
        }
        #expect(matchedItem.id == item.id)
    }
}
