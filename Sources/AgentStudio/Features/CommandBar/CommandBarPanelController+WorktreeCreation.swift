import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

/// One in-flight fork-eligibility query, owned by the bar session that issued it. A query
/// from an earlier session never answers, or stands in for, a query of the current one.
struct InFlightForkEligibilityQuery {
    let rootSessionGeneration: Int
    let token: UUID
    let task: Task<Void, Never>
}

extension CommandBarPanelController {
    /// Asks the fork-eligibility port about a text-entry level's source once per bar session,
    /// off the main actor, and records the answer as bar-local state. The row shows Fork
    /// while pending.
    @discardableResult
    func requestForkEligibilityIfNeeded(for level: CommandBarLevel) -> Task<Void, Never>? {
        guard
            let query = level.textEntry?.forkEligibilityQuery,
            let worktreeForkEligibility,
            state.forkEligibilityBySourceWorktreeId[query.sourceWorktreeId] == nil,
            currentSessionForkEligibilityQuery(for: query.sourceWorktreeId) == nil
        else { return nil }
        let rootSessionGeneration = state.rootSessionGeneration
        let token = UUIDv7.generate()
        let queryTask = Task { @MainActor [weak self] in
            let eligibility = await worktreeForkEligibility.forkEligibility(
                sourceWorktreePath: query.sourceWorktreePath,
                destinationDirectory: query.destinationDirectory
            )
            guard let self else { return }
            if self.forkEligibilityQueriesBySourceWorktreeId[query.sourceWorktreeId]?.token == token {
                self.forkEligibilityQueriesBySourceWorktreeId.removeValue(forKey: query.sourceWorktreeId)
            }
            guard self.state.rootSessionGeneration == rootSessionGeneration else { return }
            self.state.recordForkEligibility(eligibility, forSourceWorktreeId: query.sourceWorktreeId)
        }
        forkEligibilityQueriesBySourceWorktreeId[query.sourceWorktreeId] = InFlightForkEligibilityQuery(
            rootSessionGeneration: rootSessionGeneration,
            token: token,
            task: queryTask
        )
        return queryTask
    }

    /// A Fork Return that arrived before the eligibility answer waits for it (milliseconds)
    /// with the bar still open, then re-executes the row with the answer: fork where it is
    /// available, the clean fallback where it is not. Nothing runs without a query in flight,
    /// or once the user has left the level the Return was pressed on.
    func resumeWorktreeCreationAfterForkEligibility(
        item: CommandBarItem,
        draft: CommandBarWorktreeCreationDraft,
        modifier: EnterModifier
    ) {
        guard
            CommandBarWorktreeCreationResolver.resolve(draft: draft, modifier: modifier) == .awaitingForkEligibility,
            let query = currentSessionForkEligibilityQuery(for: draft.sourceWorktreeId)
        else { return }
        let rootSessionGeneration = state.rootSessionGeneration
        let levelVisitRevision = state.levelVisitRevision
        pendingWorktreeCreation = Task { @MainActor [weak self] in
            await query.task.value
            guard
                let self,
                self.state.rootSessionGeneration == rootSessionGeneration,
                self.state.levelVisitRevision == levelVisitRevision,
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

    private func currentSessionForkEligibilityQuery(for sourceWorktreeId: UUID) -> InFlightForkEligibilityQuery? {
        guard
            let query = forkEligibilityQueriesBySourceWorktreeId[sourceWorktreeId],
            query.rootSessionGeneration == state.rootSessionGeneration
        else { return nil }
        return query
    }
}
