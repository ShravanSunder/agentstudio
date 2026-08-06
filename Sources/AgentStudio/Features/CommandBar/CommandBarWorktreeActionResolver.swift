import AgentStudioCore
import Foundation

enum CommandBarWorktreeActionResolution: Equatable, Sendable {
    case dispatch(command: AppCommand, target: UUID, targetType: SearchItemType)
    case showActionsMenu
}

enum CommandBarWorktreeActionResolver {
    static func resolve(
        presence: WorktreePresence,
        modifier: EnterModifier,
        canOpenInCurrentTab: Bool,
        targetedSpecResolver: CommandBarTargetedSpecResolver =
            CommandBarCommandPresentation.catalogTargetedSpecResolver
    ) -> CommandBarWorktreeActionResolution {
        let placement: CommandBarWorktreeTerminalPlacement
        switch modifier {
        case .command:
            placement = .newTab
        case .option:
            guard canOpenInCurrentTab else { return .showActionsMenu }
            placement = .currentTabPane
        case .plain:
            return .showActionsMenu
        }
        guard
            let commandSpec = CommandBarCommandPresentation.targetedWorktreeTerminalSpec(
                for: placement,
                targetedSpecResolver: targetedSpecResolver
            )
        else {
            return .showActionsMenu
        }
        return .dispatch(
            command: commandSpec.command,
            target: presence.worktreeId,
            targetType: .worktree
        )
    }
}
