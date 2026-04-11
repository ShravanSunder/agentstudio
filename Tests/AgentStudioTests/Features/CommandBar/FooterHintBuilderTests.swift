import Foundation
import Testing

@testable import AgentStudio

@Suite
struct FooterHintBuilderTests {
    private func labels(_ hints: [FooterHint]) -> [String] {
        hints.filter { !$0.isDivider }.map(\.label)
    }

    private func hasDivider(_ hints: [FooterHint]) -> Bool {
        hints.contains { $0.isDivider }
    }

    @Test
    func test_nested_showsSelectBackAndClose() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: true, hasTabsOpen: true)

        #expect(labels(hints) == ["Select", "Back", "Close"])
        #expect(hasDivider(hints))
    }

    @Test
    func test_noSelection_everythingScope_showsScopeHintsAndClose() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: false, hasTabsOpen: true)

        #expect(labels(hints) == ["Commands", "Panes", "Repos", "Close"])
    }

    @Test
    func test_noSelection_nonEverythingScope_showsOnlyClose() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: false, hasTabsOpen: true, scope: .commands)

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
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)

        #expect(labels(hints).first == "Go to")
        #expect(labels(hints).contains("Commands"))
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
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)

        #expect(labels(hints).first == "Go to")
        #expect(!labels(hints).contains("Open"))
    }

    @Test
    func test_commandItem_showsOpen() {
        let item = makeCommandBarItem(id: "cmd-1", title: "Cmd")
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)

        #expect(labels(hints).first == "Open")
        #expect(!labels(hints).contains("Go to"))
    }

    @Test
    func test_commandItemWithChildren_showsOpenAndDrillIn() {
        let item = makeCommandBarItem(id: "cmd-1", title: "Cmd", hasChildren: true)
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)

        #expect(labels(hints).contains("Open"))
        #expect(labels(hints).contains("Drill in"))
    }

    @Test
    func test_worktreeNotOpen_noTabs_showsNewTab() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 0)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: false)

        #expect(labels(hints) == ["New tab", "Commands", "Panes", "Repos", "Close"])
    }

    @Test
    func test_worktreeNotOpen_tabsExist_showsChooseAndModifiers() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 0)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)

        #expect(labels(hints) == ["Choose", "New tab", "Open in tab", "Commands", "Panes", "Repos", "Close"])
    }

    @Test
    func test_worktreeSinglePane_showsChooseAndModifiers() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 1)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)

        #expect(labels(hints) == ["Choose", "New tab", "Open in tab", "Commands", "Panes", "Repos", "Close"])
    }

    @Test
    func test_worktreeMultiplePanes_showsChooseAndModifiers() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 2)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)

        #expect(labels(hints) == ["Choose", "New tab", "Open in tab", "Commands", "Panes", "Repos", "Close"])
    }

    @Test
    func test_scopedView_omitsScopeHints() {
        let item = makeCommandBarItem(id: "cmd-1", title: "Cmd")
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true, scope: .panes)

        #expect(labels(hints) == ["Open", "Close"])
        #expect(!labels(hints).contains("Commands"))
    }

    @Test
    func test_dividersSeparateGroups() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 1)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)
        let dividerCount = hints.filter(\.isDivider).count

        #expect(dividerCount == 2)
    }
}
