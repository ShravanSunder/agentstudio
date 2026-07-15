import Foundation
import Observation

enum RepositoryTopologyAtomError: Error, Equatable {
    case invalidRepositoryTag(String)
    case duplicateRepositoryTag(String)
    case repoNotFound(UUID)
    case worktreeNotFound(UUID)
}

@MainActor
@Observable
final class RepositoryTopologyAtom {
    private(set) var repos: [Repo] = []
    private(set) var watchedPaths: [WatchedPath] = []
    private(set) var unavailableRepoIds: Set<UUID> = []
    private(set) var worktreePathIndexGeneration: UInt64 = 0

    @ObservationIgnored private var worktreePathIndex: [WorktreePathIndexEntry] = []
    @ObservationIgnored private var performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    @ObservationIgnored private var deferredWorktreePathIndexRebuildDepth = 0
    @ObservationIgnored private var deferredWorktreePathIndexRebuildNeeded = false
    @ObservationIgnored let snapshotStorage = RepositoryTopologySnapshotStorage()

    private struct WorktreePathIndexEntry {
        let repo: Repo
        let worktree: Worktree
        let normalizedWorktreePath: String
        let repoWorktreeCount: Int
        let repoPathMatchesWorktree: Bool
        let isMainWorktree: Bool
        let stableTieBreaker: String
    }

    var allWorktreeIds: Set<UUID> {
        snapshotStorage.allWorktreeIDs
    }

    func setPerformanceTraceRecorder(_ recorder: AgentStudioPerformanceTraceRecorder?) {
        performanceTraceRecorder = recorder
    }

    func performBatchedTopologyMutation(_ mutation: () -> Void) {
        deferredWorktreePathIndexRebuildDepth += 1
        defer {
            deferredWorktreePathIndexRebuildDepth -= 1
            if deferredWorktreePathIndexRebuildDepth == 0, deferredWorktreePathIndexRebuildNeeded {
                deferredWorktreePathIndexRebuildNeeded = false
                rebuildWorktreePathIndexAndBumpGeneration()
            }
        }
        mutation()
    }

    @discardableResult
    func hydrate(
        runtimeRepos: [Repo],
        watchedPaths: [WatchedPath],
        unavailableRepoIds: Set<UUID>
    ) -> RepositoryTopologyHydrationResult {
        if let rejection = snapshotStorage.validate(
            repositories: runtimeRepos,
            watchedPaths: watchedPaths,
            unavailableRepositoryIDs: unavailableRepoIds
        ) {
            return .rejected(rejection)
        }
        repos = runtimeRepos
        self.watchedPaths = watchedPaths
        self.unavailableRepoIds = unavailableRepoIds
        synchronizeSnapshotStorage()
        scheduleWorktreePathIndexRebuild()
        return .applied
    }

    func repo(_ id: UUID) -> Repo? {
        snapshotStorage.runtimeRepository(for: id)
    }

    func worktree(_ id: UUID) -> Worktree? {
        snapshotStorage.runtimeWorktree(for: id)
    }

    func repo(containing worktreeId: UUID) -> Repo? {
        guard let worktree = snapshotStorage.runtimeWorktree(for: worktreeId) else { return nil }
        return snapshotStorage.runtimeRepository(for: worktree.repoId)
    }

    func repoAndWorktree(containing cwd: URL?) -> (repo: Repo, worktree: Worktree)? {
        guard let cwd else { return nil }
        let clock = ContinuousClock()
        let start = clock.now
        _ = worktreePathIndexGeneration

        let normalizedCWD = cwd.standardizedFileURL.path
        let match = worktreePathIndex.first(where: {
            normalizedCWD == $0.normalizedWorktreePath
                || normalizedCWD.hasPrefix($0.normalizedWorktreePath + "/")
        })

        performanceTraceRecorder?.recordDuration(
            .repoAndWorktreeLookup,
            duration: start.duration(to: clock.now),
            attributes: [
                "agentstudio.performance.topology.index.count": .int(worktreePathIndex.count),
                "agentstudio.performance.topology.has_match": .bool(match != nil),
            ]
        )

        guard let match else { return nil }
        return (match.repo, match.worktree)
    }

    @discardableResult
    func addRepo(at path: URL) -> Repo {
        let normalizedPath = path.standardizedFileURL
        let incomingStableKey = StableKey.fromPath(normalizedPath)
        if let existing = repos.first(where: {
            $0.repoPath.standardizedFileURL == normalizedPath || $0.stableKey == incomingStableKey
        }) {
            if unavailableRepoIds.remove(existing.id) != nil {
                synchronizeSnapshotStorage()
            }
            return existing
        }

        let repoId = UUIDv7.generate()
        let mainWorktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repoId,
            name: normalizedPath.lastPathComponent,
            path: normalizedPath,
            isMainWorktree: true
        )
        let repo = Repo(
            id: repoId,
            name: normalizedPath.lastPathComponent,
            repoPath: normalizedPath,
            worktrees: [mainWorktree]
        )
        repos.append(repo)
        unavailableRepoIds.remove(repo.id)
        synchronizeSnapshotStorage()
        scheduleWorktreePathIndexRebuild()
        return repo
    }

    func removeRepo(_ repoId: UUID) {
        guard repos.contains(where: { $0.id == repoId }) else { return }
        repos.removeAll { $0.id == repoId }
        unavailableRepoIds.remove(repoId)
        synchronizeSnapshotStorage()
        scheduleWorktreePathIndexRebuild()
    }

    func markRepoUnavailable(_ repoId: UUID) {
        guard repos.contains(where: { $0.id == repoId }) else { return }
        unavailableRepoIds.insert(repoId)
        synchronizeSnapshotStorage()
    }

    func markRepoAvailable(_ repoId: UUID) {
        unavailableRepoIds.remove(repoId)
        synchronizeSnapshotStorage()
    }

    func isRepoUnavailable(_ repoId: UUID) -> Bool {
        unavailableRepoIds.contains(repoId)
    }

    func setRepoTags(_ tags: [String], repoId: UUID) throws {
        guard let repoIndex = repos.firstIndex(where: { $0.id == repoId }) else {
            throw RepositoryTopologyAtomError.repoNotFound(repoId)
        }
        repos[repoIndex].tags = try Self.canonicalRepositoryTags(tags)
        synchronizeSnapshotStorage()
    }

    func setWorktreeTags(_ tags: [String], worktreeId: UUID) throws {
        for repoIndex in repos.indices {
            guard let worktreeIndex = repos[repoIndex].worktrees.firstIndex(where: { $0.id == worktreeId }) else {
                continue
            }
            repos[repoIndex].worktrees[worktreeIndex].tags = try Self.canonicalRepositoryTags(tags)
            synchronizeSnapshotStorage()
            return
        }
        throw RepositoryTopologyAtomError.worktreeNotFound(worktreeId)
    }

    @discardableResult
    func addWatchedPath(_ path: URL) -> WatchedPath? {
        let normalizedPath = path.standardizedFileURL
        let key = StableKey.fromPath(normalizedPath)
        guard !watchedPaths.contains(where: { $0.stableKey == key }) else {
            return watchedPaths.first { $0.stableKey == key }
        }
        let watchedPath = WatchedPath(path: normalizedPath)
        watchedPaths.append(watchedPath)
        synchronizeSnapshotStorage()
        return watchedPath
    }

    func removeWatchedPath(_ id: UUID) {
        watchedPaths.removeAll { $0.id == id }
        synchronizeSnapshotStorage()
    }

    @discardableResult
    func reassociateRepo(
        _ repoId: UUID,
        to newPath: URL,
        discoveredWorktrees: [Worktree]
    ) -> RepositoryReassociationResult {
        reassociateRepo(
            repoId,
            to: newPath,
            candidates: discoveredWorktrees.map(WorktreeReconciliationCandidate.identified),
            traceId: nil
        )
    }

    @discardableResult
    func reassociateRepo(
        _ repoId: UUID,
        to newPath: URL,
        scannedWorktrees: RepositoryScannedWorktrees,
        traceId: UUID
    ) -> RepositoryReassociationResult {
        reassociateRepo(
            repoId,
            to: newPath,
            candidates: [.scannedMain(scannedWorktrees.main)]
                + scannedWorktrees.linked.map(WorktreeReconciliationCandidate.scannedLinked),
            traceId: traceId
        )
    }

    private func reassociateRepo(
        _ repoId: UUID,
        to newPath: URL,
        candidates: [WorktreeReconciliationCandidate],
        traceId: UUID?
    ) -> RepositoryReassociationResult {
        let normalizedPath = newPath.standardizedFileURL
        let incomingStableKey = StableKey.fromPath(normalizedPath)
        if repos.contains(where: { $0.id != repoId && $0.stableKey == incomingStableKey }) {
            return .rejected(.duplicateRepositoryStableKey(incomingStableKey))
        }
        let preparation = prepareWorktreeReconciliation(
            repoId,
            candidates: candidates,
            traceId: traceId
        )
        switch preparation {
        case .rejected(let rejection):
            return .rejected(.worktreeReconciliation(rejection))
        case .prepared(let prepared):
            repos[prepared.repoIndex].name = normalizedPath.lastPathComponent
            repos[prepared.repoIndex].repoPath = normalizedPath
            repos[prepared.repoIndex].worktrees = prepared.mergedWorktrees
            unavailableRepoIds.remove(repoId)
            synchronizeSnapshotStorage()
            scheduleWorktreePathIndexRebuild()
            return .accepted(
                .init(
                    worktreeIds: Set(prepared.mergedWorktrees.map(\.id)),
                    delta: prepared.delta
                )
            )
        }
    }

    @discardableResult
    func reconcileScannedWorktrees(
        _ repoId: UUID,
        scannedWorktrees: RepositoryScannedWorktrees,
        traceId: UUID
    ) -> RepositoryWorktreeReconciliationResult {
        reconcileWorktrees(
            repoId,
            candidates: [.scannedMain(scannedWorktrees.main)]
                + scannedWorktrees.linked.map(WorktreeReconciliationCandidate.scannedLinked),
            traceId: traceId
        )
    }

    @discardableResult
    func reconcileDiscoveredWorktrees(
        _ repoId: UUID,
        worktrees: [Worktree]
    ) -> RepositoryWorktreeReconciliationResult {
        reconcileWorktrees(
            repoId,
            candidates: worktrees.map(WorktreeReconciliationCandidate.identified),
            traceId: nil
        )
    }

    private enum WorktreeReconciliationCandidate {
        case scannedMain(RepositoryScannedMainWorktree)
        case scannedLinked(RepositoryScannedLinkedWorktree)
        case identified(Worktree)

        var name: String {
            switch self {
            case .scannedMain(let candidate): candidate.name
            case .scannedLinked(let candidate): candidate.name
            case .identified(let worktree): worktree.name
            }
        }

        var path: URL {
            switch self {
            case .scannedMain(let candidate): candidate.path
            case .scannedLinked(let candidate): candidate.path
            case .identified(let worktree): worktree.path
            }
        }

        var isMainWorktree: Bool {
            switch self {
            case .scannedMain: true
            case .scannedLinked: false
            case .identified(let worktree): worktree.isMainWorktree
            }
        }

        func makeUnmatchedWorktree(repoId: UUID) -> Worktree {
            switch self {
            case .scannedMain(let candidate):
                return Worktree(
                    id: UUIDv7.generate(),
                    repoId: repoId,
                    name: candidate.name,
                    path: candidate.path,
                    isMainWorktree: true
                )
            case .scannedLinked(let candidate):
                return Worktree(
                    id: UUIDv7.generate(),
                    repoId: repoId,
                    name: candidate.name,
                    path: candidate.path,
                    isMainWorktree: false
                )
            case .identified(let worktree):
                return worktree
            }
        }
    }

    private struct PreparedWorktreeReconciliation {
        let repoIndex: Int
        let mergedWorktrees: [Worktree]
        let delta: WorktreeTopologyDelta
    }

    private enum WorktreeReconciliationPreparation {
        case prepared(PreparedWorktreeReconciliation)
        case rejected(RepositoryWorktreeReconciliationRejection)
    }

    private func reconcileWorktrees(
        _ repoId: UUID,
        candidates: [WorktreeReconciliationCandidate],
        traceId: UUID?
    ) -> RepositoryWorktreeReconciliationResult {
        let preparation = prepareWorktreeReconciliation(
            repoId,
            candidates: candidates,
            traceId: traceId
        )
        switch preparation {
        case .rejected(let rejection):
            return .rejected(rejection)
        case .prepared(let prepared):
            if prepared.delta.didChange {
                repos[prepared.repoIndex].worktrees = prepared.mergedWorktrees
                synchronizeSnapshotStorage()
                scheduleWorktreePathIndexRebuild()
            }
            return .accepted(.init(delta: prepared.delta))
        }
    }

    private func prepareWorktreeReconciliation(
        _ repoId: UUID,
        candidates: [WorktreeReconciliationCandidate],
        traceId: UUID?
    ) -> WorktreeReconciliationPreparation {
        guard let index = repos.firstIndex(where: { $0.id == repoId }) else {
            return .rejected(.repoNotFound(repoId))
        }
        for candidate in candidates {
            guard case .identified(let worktree) = candidate else { continue }
            guard worktree.repoId == repoId else {
                return .rejected(
                    .worktreeRepoMismatch(
                        worktreeId: worktree.id,
                        expectedRepoId: repoId,
                        actualRepoId: worktree.repoId
                    )
                )
            }
        }

        let existing = repos[index].worktrees

        let existingByPath = Dictionary(
            existing.map { ($0.path.standardizedFileURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingMain = existing.first(where: \.isMainWorktree)
        let existingByName = Dictionary(existing.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var consumedExistingIds = Set<UUID>()
        var preservedWorktreeIds: [UUID] = []

        let merged = candidates.map { candidate -> Worktree in
            let matchedWorktree: Worktree?
            if let pathMatch = existingByPath[candidate.path.standardizedFileURL],
                !consumedExistingIds.contains(pathMatch.id)
            {
                matchedWorktree = pathMatch
            } else if candidate.isMainWorktree,
                let existingMain,
                !consumedExistingIds.contains(existingMain.id)
            {
                matchedWorktree = existingMain
            } else if let nameMatch = existingByName[candidate.name],
                !consumedExistingIds.contains(nameMatch.id)
            {
                matchedWorktree = nameMatch
            } else {
                matchedWorktree = nil
            }

            if let matchedWorktree {
                consumedExistingIds.insert(matchedWorktree.id)
                preservedWorktreeIds.append(matchedWorktree.id)
                return Worktree(
                    id: matchedWorktree.id,
                    repoId: repoId,
                    name: candidate.name,
                    path: candidate.path,
                    isMainWorktree: candidate.isMainWorktree,
                    tags: matchedWorktree.tags
                )
            }
            return candidate.makeUnmatchedWorktree(repoId: repoId)
        }

        var seenWorktreeIds = Set<UUID>()
        for worktree in repos.filter({ $0.id != repoId }).flatMap(\.worktrees) {
            seenWorktreeIds.insert(worktree.id)
        }
        for worktree in merged where !seenWorktreeIds.insert(worktree.id).inserted {
            return .rejected(.duplicateWorktreeId(worktree.id))
        }

        var seenStableKeys = Set<String>()
        for worktree in repos.filter({ $0.id != repoId }).flatMap(\.worktrees) {
            seenStableKeys.insert(worktree.stableKey)
        }
        for worktree in merged where !seenStableKeys.insert(worktree.stableKey).inserted {
            return .rejected(.duplicateWorktreeStableKey(worktree.stableKey))
        }

        let preservedWorktreeIdSet = Set(preservedWorktreeIds)
        let removedWorktrees =
            existing
            .filter { !preservedWorktreeIdSet.contains($0.id) }
            .map { RemovedWorktreeEntry(id: $0.id, path: $0.path) }
        let addedWorktreeIds =
            merged
            .filter { !preservedWorktreeIdSet.contains($0.id) }
            .map(\.id)
        let delta = WorktreeTopologyDelta(
            repoId: repoId,
            addedWorktreeIds: addedWorktreeIds,
            removedWorktrees: removedWorktrees,
            preservedWorktreeIds: preservedWorktreeIds,
            didChange: merged != existing,
            traceId: traceId
        )

        return .prepared(
            .init(
                repoIndex: index,
                mergedWorktrees: merged,
                delta: delta
            )
        )
    }

    private func scheduleWorktreePathIndexRebuild() {
        guard deferredWorktreePathIndexRebuildDepth == 0 else {
            deferredWorktreePathIndexRebuildNeeded = true
            return
        }
        rebuildWorktreePathIndexAndBumpGeneration()
    }

    private func synchronizeSnapshotStorage() {
        snapshotStorage.synchronize(
            repositories: repos,
            watchedPaths: watchedPaths,
            unavailableRepositoryIDs: unavailableRepoIds
        )
    }

    func prepareSnapshotMutation(
        _ batch: RepositoryTopologyStagedMutationBatch,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<RepositoryTopologyStagedMutationReceipt> {
        try snapshotStorage.validate(batch)
        try snapshotStorage.prepare(batch, preparation: preparation, revisionOwner: revisionOwner)
        return preparation.commit { [self] in
            snapshotStorage.apply(
                batch,
                repositories: &repos,
                watchedPaths: &watchedPaths,
                unavailableRepositoryIDs: &unavailableRepoIds
            )
            scheduleWorktreePathIndexRebuild()
            return RepositoryTopologyStagedMutationReceipt(revision: preparation.transaction.proposedRevision)
        }
    }

    private func rebuildWorktreePathIndexAndBumpGeneration() {
        worktreePathIndex = repos.flatMap { repo -> [WorktreePathIndexEntry] in
            let normalizedRepoPath = repo.repoPath.standardizedFileURL.path
            let normalizedWorktrees = repo.worktrees.map { worktree in
                (worktree: worktree, normalizedPath: worktree.path.standardizedFileURL.path)
            }
            let repoPathMatchesAnyWorktree = normalizedWorktrees.contains {
                $0.normalizedPath == normalizedRepoPath
            }

            return normalizedWorktrees.map { item in
                WorktreePathIndexEntry(
                    repo: repo,
                    worktree: item.worktree,
                    normalizedWorktreePath: item.normalizedPath,
                    repoWorktreeCount: repo.worktrees.count,
                    repoPathMatchesWorktree: repoPathMatchesAnyWorktree
                        && normalizedRepoPath == item.normalizedPath,
                    isMainWorktree: item.worktree.isMainWorktree,
                    stableTieBreaker: "\(repo.id.uuidString)|\(item.worktree.id.uuidString)"
                )
            }
        }
        .sorted(by: Self.worktreePathIndexEntryPrecedes)

        worktreePathIndexGeneration &+= 1
    }

    private static func worktreePathIndexEntryPrecedes(
        lhs: WorktreePathIndexEntry,
        rhs: WorktreePathIndexEntry
    ) -> Bool {
        if lhs.normalizedWorktreePath.count != rhs.normalizedWorktreePath.count {
            return lhs.normalizedWorktreePath.count > rhs.normalizedWorktreePath.count
        }
        if lhs.repoWorktreeCount != rhs.repoWorktreeCount {
            return lhs.repoWorktreeCount < rhs.repoWorktreeCount
        }
        if lhs.repoPathMatchesWorktree != rhs.repoPathMatchesWorktree {
            return lhs.repoPathMatchesWorktree && !rhs.repoPathMatchesWorktree
        }
        if lhs.isMainWorktree != rhs.isMainWorktree {
            return !lhs.isMainWorktree && rhs.isMainWorktree
        }
        return lhs.stableTieBreaker < rhs.stableTieBreaker
    }

    private static func canonicalRepositoryTags(_ tags: [String]) throws -> [String] {
        var seenTags = Set<String>()
        var canonicalTags: [String] = []
        for tag in tags {
            guard isValidRepositoryTag(tag) else {
                throw RepositoryTopologyAtomError.invalidRepositoryTag(tag)
            }
            guard seenTags.insert(tag).inserted else {
                throw RepositoryTopologyAtomError.duplicateRepositoryTag(tag)
            }
            canonicalTags.append(tag)
        }
        return canonicalTags.sorted()
    }

    private static func isValidRepositoryTag(_ tag: String) -> Bool {
        RepositoryTagValidation.isValid(tag)
    }
}
