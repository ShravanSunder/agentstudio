import Foundation

enum CommandBarWorktreeActionResolution: Equatable, Sendable {
    case dispatch(command: AppCommand, target: UUID, targetType: SearchItemType)
    case showOpenChoice
    case showPaneChoice
}

enum CommandBarWorktreeActionResolver {
    static func resolve(
        presence: WorktreePresence,
        modifier: EnterModifier,
        hasTabsOpen: Bool
    ) -> CommandBarWorktreeActionResolution {
        switch modifier {
        case .command:
            return .dispatch(command: .openNewTerminalInTab, target: presence.worktreeId, targetType: .worktree)
        case .option:
            return .dispatch(command: .openWorktreeInPane, target: presence.worktreeId, targetType: .worktree)
        case .plain:
            switch presence.openState {
            case .notOpen where !hasTabsOpen:
                return .dispatch(command: .openNewTerminalInTab, target: presence.worktreeId, targetType: .worktree)
            case .notOpen:
                return .showOpenChoice
            case .singlePane, .multiplePanes:
                return .showPaneChoice
            }
        }
    }
}
