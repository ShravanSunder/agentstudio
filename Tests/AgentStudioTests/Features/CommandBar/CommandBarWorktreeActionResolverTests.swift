import Foundation
import Testing

@testable import AgentStudioCommandBar
@testable import AgentStudioCore

@Suite
struct CommandBarWorktreeActionResolverTests {
    @Test
    func test_plain_notOpen_withoutCurrentTab_showsActionsMenu() {
        let presence = makeWorktreePresence(paneCount: 0)

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .plain,
            canOpenInCurrentTab: false
        )

        #expect(resolution == .showActionsMenu)
    }

    @Test
    func test_plain_notOpen_withCurrentTab_showsActionsMenu() {
        let presence = makeWorktreePresence(paneCount: 0)

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .plain,
            canOpenInCurrentTab: true
        )

        #expect(resolution == .showActionsMenu)
    }

    @Test
    func test_plain_singlePane_showsActionsMenu() {
        let presence = makeWorktreePresence(paneCount: 1)

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .plain,
            canOpenInCurrentTab: true
        )

        #expect(resolution == .showActionsMenu)
    }

    @Test
    func test_plain_multiplePanes_showsActionsMenu() {
        let presence = makeWorktreePresence(paneCount: 2)

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .plain,
            canOpenInCurrentTab: true
        )

        #expect(resolution == .showActionsMenu)
    }

    @Test
    func test_command_dispatchesNewTab() {
        let presence = makeWorktreePresence(paneCount: 1)

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .command,
            canOpenInCurrentTab: true
        )

        #expect(
            resolution == .dispatch(command: .openNewTerminalInTab, target: presence.worktreeId, targetType: .worktree))
    }

    @Test("Command-Return falls back to the actions menu when the catalog rejects worktree targeting")
    func commandReturnRequiresCatalogWorktreeAdmission() {
        let presence = makeWorktreePresence(paneCount: 1)

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .command,
            canOpenInCurrentTab: true,
            targetedSpecResolver: commandBarSurfaceRejectedTargetedSpecResolver
        )

        #expect(resolution == .showActionsMenu)
    }

    @Test
    func test_option_withCurrentTab_dispatchesOpenInPane() {
        let presence = makeWorktreePresence(paneCount: 1)

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .option,
            canOpenInCurrentTab: true
        )

        #expect(
            resolution == .dispatch(command: .openWorktreeInPane, target: presence.worktreeId, targetType: .worktree))
    }

    @Test
    func test_option_withoutCurrentTab_showsActionsMenu() {
        let presence = makeWorktreePresence(paneCount: 1)

        let resolution = CommandBarWorktreeActionResolver.resolve(
            presence: presence,
            modifier: .option,
            canOpenInCurrentTab: false
        )

        #expect(resolution == .showActionsMenu)
    }
}
