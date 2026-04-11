import Foundation
import Testing

@testable import AgentStudio

@Suite
struct CommandBarWorktreeActionResolverTests {
    @Test
    func test_plain_notOpen_noTabs_dispatchesNewTab() {
        let presence = makeWorktreePresence(paneCount: 0)

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .plain,
            hasTabsOpen: false
        )

        #expect(
            resolution == .dispatch(command: .openNewTerminalInTab, target: presence.worktreeId, targetType: .worktree))
    }

    @Test
    func test_plain_notOpen_withTabs_showsOpenChoice() {
        let presence = makeWorktreePresence(paneCount: 0)

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .plain,
            hasTabsOpen: true
        )

        #expect(resolution == .showOpenChoice)
    }

    @Test
    func test_plain_singlePane_dispatchesFocusPane() {
        let presence = makeWorktreePresence(paneCount: 1)
        let expectedPaneId = presence.openPanes.first!.paneId

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .plain,
            hasTabsOpen: true
        )

        #expect(resolution == .dispatch(command: .focusPane, target: expectedPaneId, targetType: .floatingTerminal))
    }

    @Test
    func test_plain_multiplePanes_showsPaneChoice() {
        let presence = makeWorktreePresence(paneCount: 2)

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .plain,
            hasTabsOpen: true
        )

        #expect(resolution == .showPaneChoice)
    }

    @Test
    func test_command_dispatchesNewTab() {
        let presence = makeWorktreePresence(paneCount: 1)

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .command,
            hasTabsOpen: true
        )

        #expect(
            resolution == .dispatch(command: .openNewTerminalInTab, target: presence.worktreeId, targetType: .worktree))
    }

    @Test
    func test_option_dispatchesOpenInPane() {
        let presence = makeWorktreePresence(paneCount: 1)

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .option,
            hasTabsOpen: true
        )

        #expect(
            resolution == .dispatch(command: .openWorktreeInPane, target: presence.worktreeId, targetType: .worktree))
    }
}
