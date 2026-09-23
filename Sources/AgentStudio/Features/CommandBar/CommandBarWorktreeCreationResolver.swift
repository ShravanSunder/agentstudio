import AgentStudioCore
import Foundation

/// The Create row's typed input: a source worktree, the branch text as validated so far,
/// and the fork-eligibility answer for that source (`nil` while the query is pending).
/// An invalid name keeps the row visible but not actionable.
package struct CommandBarWorktreeCreationDraft: Equatable, Sendable {
    package let sourceWorktreeId: UUID
    package let branchName: Result<WorktreeBranchName, WorktreeBranchNameRejection>
    package let forkEligibility: WorktreeForkEligibility?

    package init(
        sourceWorktreeId: UUID,
        branchName: Result<WorktreeBranchName, WorktreeBranchNameRejection>,
        forkEligibility: WorktreeForkEligibility? = nil
    ) {
        self.sourceWorktreeId = sourceWorktreeId
        self.branchName = branchName
        self.forkEligibility = forkEligibility
    }

    /// The row reads as Fork while eligibility is pending or available; only an
    /// `.unavailable` answer switches it to the clean fallback.
    var offersFork: Bool {
        guard case .unavailable = forkEligibility else { return true }
        return false
    }

    func answering(_ eligibility: WorktreeForkEligibility) -> Self {
        Self(sourceWorktreeId: sourceWorktreeId, branchName: branchName, forkEligibility: eligibility)
    }
}

enum CommandBarWorktreeCreationResolution: Equatable, Sendable {
    case dispatch(WorktreeCreationRequest)
    /// A Fork Return arrived before the eligibility answer; it resolves once the answer lands.
    case awaitingForkEligibility
    case notActionable
}

/// Resolves the one Create row to one of two command identities at selection time.
/// Return and Command-Return fork and Option-Return creates a clean checkout; where fork
/// is unavailable for the source, every Return creates a clean checkout, and the row says
/// so before the user presses it. A Fork Return never dispatches before the eligibility
/// answer, so an unsupported fork is never attempted.
enum CommandBarWorktreeCreationResolver {
    static func resolve(
        draft: CommandBarWorktreeCreationDraft,
        modifier: EnterModifier,
        targetedSpecResolver: CommandBarTargetedSpecResolver = { command, targetType in
            CommandBarCommandPresentation.targetedSpec(for: command, targetType: targetType)
        }
    ) -> CommandBarWorktreeCreationResolution {
        guard case .success(let branchName) = draft.branchName else { return .notActionable }
        if draft.forkEligibility == nil, modifier != .option {
            return .awaitingForkEligibility
        }
        guard let commandSpec = targetedSpecResolver(command(for: modifier, draft: draft), .worktree),
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

    /// The request a Return with `modifier` would dispatch, if the dispatcher can take it now.
    @MainActor
    static func dispatchableRequest(
        draft: CommandBarWorktreeCreationDraft,
        modifier: EnterModifier,
        dispatcher: any AppCommandDispatching
    ) -> WorktreeCreationRequest? {
        guard case .dispatch(let request) = resolve(draft: draft, modifier: modifier),
            dispatcher.canDispatch(request.kind.command, target: request.sourceWorktreeId, targetType: .worktree)
        else { return nil }
        return request
    }

    /// Whether any modifier can act on the row right now; drives row dimming.
    @MainActor
    static func isActionable(
        _ draft: CommandBarWorktreeCreationDraft,
        dispatcher: any AppCommandDispatching
    ) -> Bool {
        guard case .success = draft.branchName else { return false }
        return [EnterModifier.plain, .option].contains { modifier in
            dispatcher.canDispatch(
                command(for: modifier, draft: draft),
                target: draft.sourceWorktreeId,
                targetType: .worktree
            )
        }
    }

    static func footerHints(for draft: CommandBarWorktreeCreationDraft) -> [FooterHint] {
        guard draft.offersFork else {
            return [FooterHint(id: "create-clean", key: "↵", label: hintLabel(for: .newWorktree))]
        }
        return [
            FooterHint(id: "create-fork", key: "↵", label: hintLabel(for: .forkWorktree)),
            FooterHint(
                id: "create-clean",
                keys: [ShortcutKey(symbol: "⌥"), ShortcutKey(symbol: "↵")],
                label: hintLabel(for: .newWorktree)
            ),
        ]
    }

    private static func command(for modifier: EnterModifier, draft: CommandBarWorktreeCreationDraft) -> AppCommand {
        guard draft.offersFork else { return WorktreeCreationKind.cleanCheckout.command }
        switch modifier {
        case .plain, .command:
            return WorktreeCreationKind.fork.command
        case .option:
            return WorktreeCreationKind.cleanCheckout.command
        }
    }

    private static func hintLabel(for command: AppCommand) -> String {
        let label = command.definition.label
        return label.hasSuffix("...") ? String(label.dropLast(3)) : label
    }
}
