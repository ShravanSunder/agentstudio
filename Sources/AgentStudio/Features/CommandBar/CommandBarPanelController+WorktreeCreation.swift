import AgentStudioCore
import Foundation

extension CommandBarPanelController {
    /// Asks the fork-eligibility port about a text-entry level's source once, off the main
    /// actor, and records the answer as bar-local state. The row shows Fork while pending.
    @discardableResult
    func requestForkEligibilityIfNeeded(for level: CommandBarLevel) -> Task<Void, Never>? {
        guard
            let query = level.textEntry?.forkEligibilityQuery,
            let worktreeForkEligibility,
            state.forkEligibilityBySourceWorktreeId[query.sourceWorktreeId] == nil,
            forkEligibilityQueriesBySourceWorktreeId[query.sourceWorktreeId] == nil
        else { return nil }
        let rootSessionGeneration = state.rootSessionGeneration
        let queryTask = Task { @MainActor [weak self] in
            let eligibility = await worktreeForkEligibility.forkEligibility(
                sourceWorktreePath: query.sourceWorktreePath,
                destinationDirectory: query.destinationDirectory
            )
            guard let self else { return }
            self.forkEligibilityQueriesBySourceWorktreeId.removeValue(forKey: query.sourceWorktreeId)
            guard self.state.rootSessionGeneration == rootSessionGeneration else { return }
            self.state.recordForkEligibility(eligibility, forSourceWorktreeId: query.sourceWorktreeId)
        }
        forkEligibilityQueriesBySourceWorktreeId[query.sourceWorktreeId] = queryTask
        return queryTask
    }

    /// A Fork Return that arrived before the eligibility answer waits for it (milliseconds)
    /// with the bar still open, then re-executes the row with the answer: fork where it is
    /// available, the clean fallback where it is not. Without a query in flight nothing runs.
    func resumeWorktreeCreationAfterForkEligibility(
        item: CommandBarItem,
        draft: CommandBarWorktreeCreationDraft,
        modifier: EnterModifier
    ) {
        guard
            CommandBarWorktreeCreationResolver.resolve(draft: draft, modifier: modifier) == .awaitingForkEligibility,
            let query = forkEligibilityQueriesBySourceWorktreeId[draft.sourceWorktreeId]
        else { return }
        let rootSessionGeneration = state.rootSessionGeneration
        pendingWorktreeCreation = Task { @MainActor [weak self] in
            await query.value
            guard
                let self,
                self.state.rootSessionGeneration == rootSessionGeneration,
                let eligibility = self.state.forkEligibilityBySourceWorktreeId[draft.sourceWorktreeId]
            else { return }
            let answeredItem = item.projected(
                group: item.group,
                groupPriority: item.groupPriority,
                action: .createWorktree(draft.answering(eligibility))
            )
            self.executeItem(answeredItem, modifier: modifier)
        }
    }
}
