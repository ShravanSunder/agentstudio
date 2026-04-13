import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite
struct CommandBarRowShortcutResolverTests {
    @Test
    func plainEnterDoesNotUseRowShortcutResolution() {
        let selectedItem = makeCommandBarItem(id: "selected")
        let otherItem = makeCommandBarItem(id: "other")

        let resolvedItem = CommandBarRowShortcutResolver.selectedItem(
            for: ShortcutTrigger(key: .enter, modifiers: []),
            selectedItem: selectedItem,
            displayedItems: [selectedItem, otherItem]
        )

        #expect(resolvedItem == nil)
    }

    @Test
    func commandEnterPrefersMatchingShortcutItemOverSelection() throws {
        let actionsLevel = CommandBarDataSource.buildWorktreeActionsLevel(
            presence: makeWorktreePresence(paneCount: 1),
            canOpenInCurrentTab: true
        )
        let selectedItem = try #require(actionsLevel.items.last)

        let resolvedItem = CommandBarRowShortcutResolver.selectedItem(
            for: ShortcutTrigger(key: .enter, modifiers: [.command]),
            selectedItem: selectedItem,
            displayedItems: actionsLevel.items
        )

        #expect(resolvedItem?.title == "New pane in new tab")
    }

    @Test
    func optionEnterPrefersMatchingShortcutItemOverSelection() throws {
        let actionsLevel = CommandBarDataSource.buildWorktreeActionsLevel(
            presence: makeWorktreePresence(paneCount: 1),
            canOpenInCurrentTab: true
        )
        let selectedItem = try #require(actionsLevel.items.first)

        let resolvedItem = CommandBarRowShortcutResolver.selectedItem(
            for: ShortcutTrigger(key: .enter, modifiers: [.option]),
            selectedItem: selectedItem,
            displayedItems: actionsLevel.items
        )

        #expect(resolvedItem?.title == "New pane in current tab")
    }

    @Test
    func optionEnterFallsBackToSelectedItemWhenNoShortcutMatches() {
        let selectedItem = makeCommandBarItem(id: "selected")
        let otherItem = makeCommandBarItem(id: "other")

        let resolvedItem = CommandBarRowShortcutResolver.selectedItem(
            for: ShortcutTrigger(key: .enter, modifiers: [.option]),
            selectedItem: selectedItem,
            displayedItems: [selectedItem, otherItem]
        )

        #expect(resolvedItem == nil)
    }

    @Test
    func commandShortcutMatchesRootCommandRows() {
        let closeTabItem = makeCommandBarItem(
            id: "close-tab",
            shortcutTrigger: ShortcutTrigger(key: .character(.w), modifiers: [.command])
        )
        let selectedItem = makeCommandBarItem(id: "selected")

        let resolvedItem = CommandBarRowShortcutResolver.selectedItem(
            for: ShortcutTrigger(key: .character(.w), modifiers: [.command]),
            selectedItem: selectedItem,
            displayedItems: [selectedItem, closeTabItem]
        )

        #expect(resolvedItem?.id == closeTabItem.id)
    }

    @Test
    func duplicateMatchesPreferSelectedItem() {
        let selectedItem = makeCommandBarItem(
            id: "selected",
            shortcutTrigger: ShortcutTrigger(key: .character(.w), modifiers: [.command])
        )
        let otherItem = makeCommandBarItem(
            id: "other",
            shortcutTrigger: ShortcutTrigger(key: .character(.w), modifiers: [.command])
        )

        let resolvedItem = CommandBarRowShortcutResolver.selectedItem(
            for: ShortcutTrigger(key: .character(.w), modifiers: [.command]),
            selectedItem: selectedItem,
            displayedItems: [selectedItem, otherItem]
        )

        #expect(resolvedItem?.id == selectedItem.id)
    }

    @Test
    func duplicateMatchesFallBackToFirstVisibleItem() {
        let firstItem = makeCommandBarItem(
            id: "first",
            shortcutTrigger: ShortcutTrigger(key: .character(.w), modifiers: [.command])
        )
        let secondItem = makeCommandBarItem(
            id: "second",
            shortcutTrigger: ShortcutTrigger(key: .character(.w), modifiers: [.command])
        )
        let selectedItem = makeCommandBarItem(id: "selected")

        let resolvedItem = CommandBarRowShortcutResolver.selectedItem(
            for: ShortcutTrigger(key: .character(.w), modifiers: [.command]),
            selectedItem: selectedItem,
            displayedItems: [firstItem, secondItem]
        )

        #expect(resolvedItem?.id == firstItem.id)
    }
}
