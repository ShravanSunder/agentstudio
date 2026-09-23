import AgentStudioCore
import Foundation

/// The Create row's typed input: a source worktree plus the branch text as validated
/// so far. An invalid name keeps the row visible but not actionable.
package struct CommandBarWorktreeCreationDraft: Equatable, Sendable {
    package let sourceWorktreeId: UUID
    package let branchName: Result<WorktreeBranchName, WorktreeBranchNameRejection>

    package init(sourceWorktreeId: UUID, branchName: Result<WorktreeBranchName, WorktreeBranchNameRejection>) {
        self.sourceWorktreeId = sourceWorktreeId
        self.branchName = branchName
    }
}

enum CommandBarWorktreeCreationResolution: Equatable, Sendable {
    case dispatch(WorktreeCreationRequest)
    case notActionable
}

/// Resolves the one Create row to one of two command identities at selection time:
/// Return and Command-Return fork, Option-Return creates a clean checkout.
enum CommandBarWorktreeCreationResolver {
    static func resolve(
        draft: CommandBarWorktreeCreationDraft,
        modifier: EnterModifier,
        targetedSpecResolver: CommandBarTargetedSpecResolver = { command, targetType in
            CommandBarCommandPresentation.targetedSpec(for: command, targetType: targetType)
        }
    ) -> CommandBarWorktreeCreationResolution {
        guard case .success(let branchName) = draft.branchName,
            let commandSpec = targetedSpecResolver(command(for: modifier), .worktree),
            let kind = WorktreeCreationKind(command: commandSpec.command)
        else {
            return .notActionable
        }
        return .dispatch(
            WorktreeCreationRequest(
                kind: kind,
                sourceWorktreeId: draft.sourceWorktreeId,
                branchName: branchName
            )
        )
    }

    /// Whether any modifier can act on the row right now; drives row dimming.
    @MainActor
    static func isActionable(
        _ draft: CommandBarWorktreeCreationDraft,
        dispatcher: any AppCommandDispatching
    ) -> Bool {
        guard case .success = draft.branchName else { return false }
        return [EnterModifier.plain, .option].contains { modifier in
            dispatcher.canDispatch(command(for: modifier), target: draft.sourceWorktreeId, targetType: .worktree)
        }
    }

    static var footerHints: [FooterHint] {
        [
            FooterHint(id: "create-fork", key: "↵", label: hintLabel(for: .forkWorktree)),
            FooterHint(
                id: "create-clean",
                keys: [ShortcutKey(symbol: "⌥"), ShortcutKey(symbol: "↵")],
                label: hintLabel(for: .newWorktree)
            ),
        ]
    }

    private static func command(for modifier: EnterModifier) -> AppCommand {
        switch modifier {
        case .plain, .command:
            WorktreeCreationKind.fork.command
        case .option:
            WorktreeCreationKind.cleanCheckout.command
        }
    }

    private static func hintLabel(for command: AppCommand) -> String {
        let label = command.definition.label
        return label.hasSuffix("...") ? String(label.dropLast(3)) : label
    }
}
