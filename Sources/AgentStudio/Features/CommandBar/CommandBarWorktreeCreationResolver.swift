import AgentStudioCore
import Foundation

/// One branch-name entry has already selected its creation operation and target.
package struct CommandBarWorktreeCreationDraft: Equatable, Sendable {
    package let kind: WorktreeCreationKind
    package let targetId: UUID
    package let branchName: Result<WorktreeBranchName, WorktreeBranchNameRejection>

    package init(
        kind: WorktreeCreationKind,
        targetId: UUID,
        branchName: Result<WorktreeBranchName, WorktreeBranchNameRejection>
    ) {
        self.kind = kind
        self.targetId = targetId
        self.branchName = branchName
    }
}

enum CommandBarWorktreeCreationResolution: Equatable, Sendable {
    case dispatch(WorktreeCreationRequest)
    case notActionable
}

enum CommandBarWorktreeCreationResolver {
    static func resolve(
        draft: CommandBarWorktreeCreationDraft,
        targetedSpecResolver: CommandBarTargetedSpecResolver = { command, targetType in
            CommandBarCommandPresentation.targetedSpec(for: command, targetType: targetType)
        }
    ) -> CommandBarWorktreeCreationResolution {
        guard case .success(let branchName) = draft.branchName else { return .notActionable }
        let targetType: SearchItemType = draft.kind == .fork ? .worktree : .repo
        guard targetedSpecResolver(draft.kind.command, targetType) != nil else { return .notActionable }
        return .dispatch(WorktreeCreationRequest(kind: draft.kind, targetId: draft.targetId, branchName: branchName))
    }

    @MainActor
    static func dispatchableRequest(
        draft: CommandBarWorktreeCreationDraft,
        dispatcher: any AppCommandDispatching
    ) -> WorktreeCreationRequest? {
        guard case .dispatch(let request) = resolve(draft: draft),
            dispatcher.canDispatch(request.kind.command, target: request.targetId, targetType: request.targetType)
        else { return nil }
        return request
    }

    @MainActor
    static func isActionable(
        _ draft: CommandBarWorktreeCreationDraft,
        dispatcher: any AppCommandDispatching
    ) -> Bool {
        dispatchableRequest(draft: draft, dispatcher: dispatcher) != nil
    }

    static func footerHints(for _: CommandBarWorktreeCreationDraft) -> [FooterHint] {
        [FooterHint(id: "create-worktree", key: "↵", label: "Create")]
    }
}
