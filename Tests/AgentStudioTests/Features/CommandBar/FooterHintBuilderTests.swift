import Foundation
import Testing

@testable import AgentStudio

@Suite
struct FooterHintBuilderTests {
    @Test
    func test_nested_showsSelectBackClose() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: true, hasTabsOpen: true)
        let keys = hints.map(\.key)

        #expect(keys.contains("↵"))
        #expect(keys.contains("⌫"))
        #expect(keys.contains("esc"))
        #expect(!keys.contains("↑↓"))
    }

    @Test
    func test_noSelection_showsNavigateAndClose() {
        let hints = FooterHintBuilder.hints(for: nil, isNested: false, hasTabsOpen: true)
        let labels = hints.map(\.label)

        #expect(labels == ["Navigate", "Close"])
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
        let labels = hints.map(\.label)

        #expect(labels.contains("Go to"))
        #expect(!labels.contains("Open"))
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
        let labels = hints.map(\.label)

        #expect(labels.contains("Go to"))
        #expect(!labels.contains("Open"))
    }

    @Test
    func test_commandItem_showsOpen() {
        let item = makeCommandBarItem(id: "cmd-1", title: "Cmd")
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)
        let labels = hints.map(\.label)

        #expect(labels.contains("Open"))
        #expect(!labels.contains("Go to"))
    }

    @Test
    func test_commandItemWithChildren_showsOpenAndDrillIn() {
        let item = makeCommandBarItem(id: "cmd-1", title: "Cmd", hasChildren: true)
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)
        let labels = hints.map(\.label)

        #expect(labels.contains("Open"))
        #expect(labels.contains("Drill in"))
    }

    @Test
    func test_worktreeNotOpen_noTabs_showsBareEnterNewTab() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 0)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: false)
        let labels = hints.map(\.label)

        #expect(labels == ["New tab", "Navigate", "Close"])
    }

    @Test
    func test_worktreeNotOpen_tabsExist_showsChooseAndModifiers() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 0)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)
        let keys = hints.map(\.key)

        #expect(keys == ["↵", "⌘↵", "⌥↵", "↑↓", "esc"])
    }

    @Test
    func test_worktreeSinglePane_showsGoToAndModifiers() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 1)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)
        let labels = hints.map(\.label)

        #expect(labels == ["Go to", "New tab", "Open in tab", "Navigate", "Close"])
    }

    @Test
    func test_worktreeMultiplePanes_showsChoosePaneAndModifiers() {
        let item = makeCommandBarItem(
            id: "wt-1",
            title: "main",
            worktreePresence: makeWorktreePresence(paneCount: 2)
        )
        let hints = FooterHintBuilder.hints(for: item, isNested: false, hasTabsOpen: true)
        let labels = hints.map(\.label)

        #expect(labels == ["Choose pane", "New tab", "Open in tab", "Navigate", "Close"])
    }
}
