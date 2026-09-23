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
            state.forkEligibilityBySourceWorktreeId[query.sourceWorktreeId] == nil
        else { return nil }
        let rootSessionGeneration = state.rootSessionGeneration
        return Task { @MainActor [weak self] in
            let eligibility = await worktreeForkEligibility.forkEligibility(
                sourceWorktreePath: query.sourceWorktreePath,
                destinationDirectory: query.destinationDirectory
            )
            guard let self, self.state.rootSessionGeneration == rootSessionGeneration else { return }
            self.state.recordForkEligibility(eligibility, forSourceWorktreeId: query.sourceWorktreeId)
        }
    }
}
