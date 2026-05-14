import Foundation
import Testing

@testable import AgentStudio

@Suite
struct FooterHintBuilderTests {
    private func labels(_ hints: [FooterHint]) -> [String] {
        hints.filter { !$0.isDivider }.map(\.label)
    }

    private func layoutLabels(
        _ hints: [FooterHint]
    ) -> (primary: [String], secondaryLeading: [String], secondaryTrailing: [String]) {
        let layout = FooterHintBuilder.layout(for: hints)
        return (
            layout.primaryRow.map(\.label),
            layout.secondaryLeadingRow.map(\.label),
            layout.secondaryTrailingRow.map(\.label)
        )
    }

    private func displayRows(
        _ hints: [FooterHint]
    ) -> (topLeading: [String], topTrailing: [String], bottom: [String]) {
        let rows = CommandBarFooter.displayRows(for: FooterHintBuilder.layout(for: hints))
        return (
            rows.topLeading.map(\.label),
            rows.topTrailing.map(\.label),
            rows.bottom.map(\.label)
        )
    }

    private func keysById(_ hints: [FooterHint]) -> [String: [String]] {
        hints.reduce(into: [:]) { result, hint in
            if !hint.isDivider {
                result[hint.id] = hint.shortcutKeys.map(\.symbol)
            }
        }
    }

    private func hasDivider(_ hints: [FooterHint]) -> Bool {
        hints.contains { $0.isDivider }
    }

    @Test
    func test_nested_showsBackAndClose() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: true, canOpenInCurrentTab: true)

        #expect(labels(hints) == ["Back", "Close"])
        #expect(hasDivider(hints))
    }

    @Test
    func test_noSelection_everythingScope_showsScopeHintsAndClose() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: false, canOpenInCurrentTab: true)

        #expect(labels(hints) == ["cmd", "pane", "repo", "Close"])
    }

    @Test
    func test_noSelection_nonEverythingScope_showsOnlyClose() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: false, canOpenInCurrentTab: true, scope: .commands)

        #expect(labels(hints) == ["Close"])
    }

    @Test
    func test_tabItem_showsGoTo() {
        let tabId = UUID()
        let item = makeCommandBarItem(
            id: "tab-1",
            title: "Tab",
            action: .dispatchTargeted(.selectTab, target: tabId, targetType: .tab)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)

        #expect(labels(hints).first == "Go to")
        #expect(labels(hints).contains("cmd"))
        #expect(labels(hints).last == "Close")
    }

    @Test
    func test_paneItem_showsGoTo() {
        let paneId = UUID()
        let item = makeCommandBarItem(
            id: "pane-1",
            title: "Pane",
            action: .dispatchTargeted(.focusPane, target: paneId, targetType: .pane)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)

        #expect(labels(hints).first == "Go to")
        #expect(!labels(hints).contains("Open"))
    }

    @Test
    func test_commandItem_showsOpen() {
        let item = makeCommandBarItem(id: "cmd-1", title: "Cmd")
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)

        #expect(labels(hints).first == "Open")
        #expect(!labels(hints).contains("Go to"))
    }

    @Test
    func test_commandItemWithShortcut_showsShortcutHint() {
        let item = makeCommandBarItem(
            id: "cmd-drawer",
            title: "Add Drawer Pane",
            shortcutTrigger: ShortcutTrigger(key: .character(.d), modifiers: [])
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)
        let keys = keysById(hints)

        #expect(labels(hints).contains("Shortcut"))
        #expect(keys["item-shortcut"] == ["D"])
    }

    @Test
    func test_commandItemWithChildren_showsOpenAndDrillIn() {
        let item = makeCommandBarItem(id: "cmd-1", title: "Cmd", hasChildren: true)
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)

        #expect(labels(hints).contains("Open"))
        #expect(labels(hints).contains("Drill in"))
    }

    @Test
    func test_worktreeWithoutCurrentTab_showsNewTab() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 0)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: false)

        #expect(labels(hints) == ["New tab", "cmd", "pane", "repo", "Close"])
    }

    @Test
    func test_worktreeNotOpen_withCurrentTab_showsModifiers() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 0)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)

        #expect(labels(hints) == ["New tab", "Open in tab", "cmd", "pane", "repo", "Close"])
        let keys = keysById(hints)
        #expect(keys["cmd-enter"] == ["⌘", "↵"])
        #expect(keys["opt-enter"] == ["⌥", "↵"])
    }

    @Test
    func test_worktreeSinglePane_showsSameMenuAndModifiers() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 1)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)

        #expect(labels(hints) == ["New tab", "Open in tab", "cmd", "pane", "repo", "Close"])
    }

    @Test
    func test_worktreeMultiplePanes_showsSameMenuAndModifiers() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 2)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)

        #expect(labels(hints) == ["New tab", "Open in tab", "cmd", "pane", "repo", "Close"])
    }

    @Test
    func test_scopedView_omitsScopeHints() {
        let item = makeCommandBarItem(id: "cmd-1", title: "Cmd")
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true, scope: .panes)

        #expect(labels(hints) == ["Open", "Close"])
        #expect(!labels(hints).contains("cmd"))
    }

    @Test
    func test_worktreeInReposScope_omitsGlobalScopeHints() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 1)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true, scope: .repos)

        #expect(labels(hints) == ["New tab", "Open in tab", "Close"])
    }

    @Test
    func test_dividersSeparateGroups() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 1)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)
        let dividerCount = hints.filter(\.isDivider).count

        #expect(dividerCount == 2)
    }

    @Test
    func test_closeHint_keepsEscAsSingleToken() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: false, canOpenInCurrentTab: true)
        let keys = keysById(hints)

        #expect(keys["dismiss"] == ["esc"])
    }

    @Test
    func test_everythingScope_layoutMovesScopeHintsToSecondaryLeadingAndDismissToTrailing() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: false, canOpenInCurrentTab: true)
        let layout = layoutLabels(hints)

        #expect(layout.primary.isEmpty)
        #expect(layout.secondaryLeading == ["cmd", "pane", "repo"])
        #expect(layout.secondaryTrailing == ["Close"])
    }

    @Test
    func test_itemLayoutKeepsContextualActionsOnPrimaryRow() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 1)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)
        let layout = layoutLabels(hints)

        #expect(layout.primary == ["New tab", "Open in tab"])
        #expect(layout.secondaryLeading == ["cmd", "pane", "repo"])
        #expect(layout.secondaryTrailing == ["Close"])
    }

    @Test
    func test_nestedLayoutPutsDismissOnSecondaryTrailingOnly() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: true, canOpenInCurrentTab: true)
        let layout = layoutLabels(hints)

        #expect(layout.primary.isEmpty)
        #expect(layout.secondaryLeading == ["Back"])
        #expect(layout.secondaryTrailing == ["Close"])
    }

    @Test
    func test_scopeHints_usePlainStyle() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: false, canOpenInCurrentTab: true)
        let scopeHints = hints.filter { ["scope-commands", "scope-panes", "scope-repos"].contains($0.id) }

        for hint in scopeHints {
            #expect(hint.style == .plain)
        }
    }

    @Test
    func test_actionHints_useBadgeStyle() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 0)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)
        let actionHints = hints.filter { ["cmd-enter", "opt-enter"].contains($0.id) }

        for hint in actionHints {
            #expect(hint.style == .badge)
        }
    }

    @Test
    func test_dismissHint_usesPlainStyle() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: false, canOpenInCurrentTab: true)
        let dismiss = hints.first { $0.id == "dismiss" }

        #expect(dismiss?.style == .plain)
    }

    @Test
    func test_displayRows_placesGlobalHintsAboveActionHints() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 1)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)
        let rows = displayRows(hints)

        #expect(rows.topLeading == ["cmd", "pane", "repo"])
        #expect(rows.topTrailing == ["Close"])
        #expect(rows.bottom == ["New tab", "Open in tab"])
    }
}
