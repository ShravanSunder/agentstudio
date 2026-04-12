import Foundation

enum CommandBarWorktreeActionResolution: Equatable, Sendable {
    case dispatch(command: AppCommand, target: UUID, targetType: SearchItemType)
    case showActionsMenu
}

enum CommandBarWorktreeActionResolver {
    static func resolve(
        presence: WorktreePresence,
        modifier: EnterModifier,
        canOpenInCurrentTab: Bool
    ) -> CommandBarWorktreeActionResolution {
        switch modifier {
        case .command:
            return .dispatch(command: .openNewTerminalInTab, target: presence.worktreeId, targetType: .worktree)
        case .option:
            if canOpenInCurrentTab {
                return .dispatch(command: .openWorktreeInPane, target: presence.worktreeId, targetType: .worktree)
            }
            return .showActionsMenu
        case .plain:
            return .showActionsMenu
        }
    }
}
