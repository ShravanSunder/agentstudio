import Foundation
import os.log

private let repoCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "RepoCacheStore")

@MainActor
final class RepoCacheStore {
    private let atom: RepoCacheAtom
    private let persistor: WorkspacePersistor
    private let recoveryReporter: PersistenceRecoveryReporter?

    init(
        atom: RepoCacheAtom,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.atom = atom
        self.persistor = persistor
        self.recoveryReporter = recoveryReporter
    }

    func restore(for workspaceId: UUID) {
        switch persistor.loadCache(for: workspaceId) {
        case .loaded(let cacheState):
            atom.hydrate(
                .init(
                    repoEnrichmentByRepoId: cacheState.repoEnrichmentByRepoId,
                    worktreeEnrichmentByWorktreeId: cacheState.worktreeEnrichmentByWorktreeId,
                    pullRequestCountByWorktreeId: cacheState.pullRequestCountByWorktreeId,
                    notificationCountByWorktreeId: cacheState.notificationCountByWorktreeId,
                    recentTargets: cacheState.recentTargets,
                    sourceRevision: cacheState.sourceRevision,
                    lastRebuiltAt: cacheState.lastRebuiltAt
                )
            )
        case .missing:
            break
        case .corrupt(let error):
            repoCacheStoreLogger.warning("Cache file corrupt, will rebuild from events: \(error)")
            recoveryReporter?(
                .init(
                    store: .repoCache,
                    workspaceId: workspaceId,
                    recovery: .rebuiltFromEvents
                )
            )
        }
    }

    func flush(for workspaceId: UUID) throws {
        guard persistor.ensureDirectory() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try persistor.saveCache(
            .init(
                workspaceId: workspaceId,
                repoEnrichmentByRepoId: atom.repoEnrichmentByRepoId,
                worktreeEnrichmentByWorktreeId: atom.worktreeEnrichmentByWorktreeId,
                pullRequestCountByWorktreeId: atom.pullRequestCountByWorktreeId,
                notificationCountByWorktreeId: atom.notificationCountByWorktreeId,
                recentTargets: atom.recentTargets,
                sourceRevision: atom.sourceRevision,
                lastRebuiltAt: atom.lastRebuiltAt
            )
        )
    }
}
