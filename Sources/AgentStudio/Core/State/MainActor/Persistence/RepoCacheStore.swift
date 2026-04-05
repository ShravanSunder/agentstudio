import Foundation
import os.log

private let repoCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "RepoCacheStore")

@MainActor
final class RepoCacheStore {
    private let atom: RepoCacheAtom
    private let persistor: WorkspacePersistor

    init(
        atom: RepoCacheAtom,
        persistor: WorkspacePersistor = WorkspacePersistor()
    ) {
        self.atom = atom
        self.persistor = persistor
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
