import Foundation

enum RepositoryTopologyMutationError: Error, Equatable {
    case invalidRepositoryTag(String)
    case duplicateRepositoryTag(String)
    case repoNotFound(UUID)
    case worktreeNotFound(UUID)
}

extension WorkspaceMutationCoordinator {
    func performBatchedTopologyMutation(_ mutation: () -> Void) {
        repositoryTopologyAtom.withDeferredWorktreePathIndexRebuild(mutation)
    }

    @discardableResult
    func addRepo(at path: URL) -> Repo {
        let normalizedPath = path.standardizedFileURL
        let incomingStableKey = StableKey.fromPath(normalizedPath)
        if let existing = repositoryTopologyAtom.repos.first(where: {
            $0.repoPath.standardizedFileURL == normalizedPath || $0.stableKey == incomingStableKey
        }) {
            if repositoryTopologyAtom.isRepoUnavailable(existing.id) {
                applyTopology(
                    repositories: repositoryTopologyAtom.repos,
                    watchedPaths: repositoryTopologyAtom.watchedPaths,
                    unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds.subtracting([existing.id])
                )
            }
            return existing
        }

        let repositoryID = UUIDv7.generate()
        let mainWorktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repositoryID,
            name: normalizedPath.lastPathComponent,
            path: normalizedPath,
            isMainWorktree: true
        )
        let repository = Repo(
            id: repositoryID,
            name: normalizedPath.lastPathComponent,
            repoPath: normalizedPath,
            worktrees: [mainWorktree]
        )
        applyTopology(
            repositories: repositoryTopologyAtom.repos + [repository],
            watchedPaths: repositoryTopologyAtom.watchedPaths,
            unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds.subtracting([repositoryID])
        )
        return repository
    }

    @discardableResult
    func ensureMainWorktree(at path: URL) -> Worktree {
        let normalizedPath = path.standardizedFileURL
        let incomingStableKey = StableKey.fromPath(normalizedPath)
        if let repositoryIndex = repositoryTopologyAtom.repos.firstIndex(where: {
            $0.repoPath.standardizedFileURL == normalizedPath || $0.stableKey == incomingStableKey
        }) {
            let repository = repositoryTopologyAtom.repos[repositoryIndex]
            if let existingWorktree = repository.worktrees.first(where: \.isMainWorktree)
                ?? repository.worktrees.first
            {
                if repositoryTopologyAtom.isRepoUnavailable(repository.id) {
                    applyTopology(
                        repositories: repositoryTopologyAtom.repos,
                        watchedPaths: repositoryTopologyAtom.watchedPaths,
                        unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds.subtracting([
                            repository.id
                        ])
                    )
                }
                return existingWorktree
            }

            let repairedWorktree = Worktree(
                repoId: repository.id,
                name: normalizedPath.lastPathComponent,
                path: normalizedPath,
                isMainWorktree: true
            )
            var repairedRepositories = repositoryTopologyAtom.repos
            repairedRepositories[repositoryIndex].name = normalizedPath.lastPathComponent
            repairedRepositories[repositoryIndex].repoPath = normalizedPath
            repairedRepositories[repositoryIndex].worktrees = [repairedWorktree]
            applyTopology(
                repositories: repairedRepositories,
                watchedPaths: repositoryTopologyAtom.watchedPaths,
                unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds.subtracting([repository.id])
            )
            return repairedWorktree
        }

        let repository = addRepo(at: normalizedPath)
        guard let mainWorktree = repository.worktrees.first(where: \.isMainWorktree) else {
            preconditionFailure("newly added repository is missing its main worktree")
        }
        return mainWorktree
    }

    func removeRepo(_ repositoryID: UUID) {
        guard repositoryTopologyAtom.repo(repositoryID) != nil else { return }
        applyTopology(
            repositories: repositoryTopologyAtom.repos.filter { $0.id != repositoryID },
            watchedPaths: repositoryTopologyAtom.watchedPaths,
            unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds.subtracting([repositoryID])
        )
    }

    func markRepoUnavailable(_ repositoryID: UUID) {
        guard repositoryTopologyAtom.repo(repositoryID) != nil else { return }
        applyTopology(
            repositories: repositoryTopologyAtom.repos,
            watchedPaths: repositoryTopologyAtom.watchedPaths,
            unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds.union([repositoryID])
        )
    }

    func setRepoFavorite(_ repositoryID: UUID, isFavorite: Bool) {
        guard let repository = repositoryTopologyAtom.repo(repositoryID) else { return }
        repositoryTopologyAtom.applyValidatedRepositoryMetadata(
            repositoryID: repositoryID,
            isFavorite: isFavorite,
            note: repository.note,
            tags: repository.tags
        )
    }

    func updateRepoNote(_ repositoryID: UUID, note: String?) {
        guard let repository = repositoryTopologyAtom.repo(repositoryID) else { return }
        repositoryTopologyAtom.applyValidatedRepositoryMetadata(
            repositoryID: repositoryID,
            isFavorite: repository.isFavorite,
            note: normalizedRepositoryNote(note),
            tags: repository.tags
        )
    }

    func setRepoTags(_ tags: [String], repositoryID: UUID) throws {
        guard let repository = repositoryTopologyAtom.repo(repositoryID) else {
            throw RepositoryTopologyMutationError.repoNotFound(repositoryID)
        }
        var seenTags = Set<String>()
        for tag in tags {
            guard RepositoryTagValidation.isValid(tag) else {
                throw RepositoryTopologyMutationError.invalidRepositoryTag(tag)
            }
            guard seenTags.insert(tag).inserted else {
                throw RepositoryTopologyMutationError.duplicateRepositoryTag(tag)
            }
        }
        repositoryTopologyAtom.applyValidatedRepositoryMetadata(
            repositoryID: repositoryID,
            isFavorite: repository.isFavorite,
            note: repository.note,
            tags: tags.sorted()
        )
    }

    func updateWorktreeNote(_ worktreeID: UUID, note: String?) throws {
        guard repositoryTopologyAtom.worktree(worktreeID) != nil else {
            throw RepositoryTopologyMutationError.worktreeNotFound(worktreeID)
        }
        repositoryTopologyAtom.applyValidatedWorktreeNote(
            worktreeID: worktreeID,
            note: normalizedRepositoryNote(note)
        )
    }

    @discardableResult
    func addWatchedPath(_ path: URL) -> WatchedPath? {
        let normalizedPath = path.standardizedFileURL
        let incomingStableKey = StableKey.fromPath(normalizedPath)
        if let existing = repositoryTopologyAtom.watchedPaths.first(where: { $0.stableKey == incomingStableKey }) {
            return existing
        }

        let watchedPath = WatchedPath(path: normalizedPath)
        applyTopology(
            repositories: repositoryTopologyAtom.repos,
            watchedPaths: repositoryTopologyAtom.watchedPaths + [watchedPath],
            unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds
        )
        return watchedPath
    }

    func removeWatchedPath(_ watchedPathID: UUID) {
        guard repositoryTopologyAtom.watchedPath(watchedPathID) != nil else { return }
        applyTopology(
            repositories: repositoryTopologyAtom.repos,
            watchedPaths: repositoryTopologyAtom.watchedPaths.filter { $0.id != watchedPathID },
            unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds
        )
    }

    @discardableResult
    func reassociateRepo(
        _ repositoryID: UUID,
        to newPath: URL,
        discoveredWorktrees: [Worktree]
    ) -> RepositoryReassociationResult {
        applyRepoReassociation(
            reassociateRepo(
                repositoryID,
                to: newPath,
                candidates: discoveredWorktrees.map(WorktreeReconciliationCandidate.identified),
                traceID: nil
            )
        )
    }

    @discardableResult
    func reassociateRepo(
        _ repositoryID: UUID,
        to newPath: URL,
        scannedWorktrees: RepositoryScannedWorktrees,
        traceId: UUID
    ) -> RepositoryReassociationResult {
        applyRepoReassociation(
            reassociateRepo(
                repositoryID,
                to: newPath,
                candidates: [.scannedMain(scannedWorktrees.main)]
                    + scannedWorktrees.linked.map(WorktreeReconciliationCandidate.scannedLinked),
                traceID: traceId
            )
        )
    }

    @discardableResult
    func reconcileScannedWorktrees(
        _ repositoryID: UUID,
        scannedWorktrees: RepositoryScannedWorktrees,
        traceId: UUID
    ) -> RepositoryWorktreeReconciliationResult {
        reconcileWorktrees(
            repositoryID,
            candidates: [.scannedMain(scannedWorktrees.main)]
                + scannedWorktrees.linked.map(WorktreeReconciliationCandidate.scannedLinked),
            traceID: traceId
        )
    }

    @discardableResult
    func reconcileDiscoveredWorktrees(
        _ repositoryID: UUID,
        worktrees: [Worktree]
    ) -> RepositoryWorktreeReconciliationResult {
        reconcileWorktrees(
            repositoryID,
            candidates: worktrees.map(WorktreeReconciliationCandidate.identified),
            traceID: nil
        )
    }

    private func reassociateRepo(
        _ repositoryID: UUID,
        to newPath: URL,
        candidates: [WorktreeReconciliationCandidate],
        traceID: UUID?
    ) -> RepositoryReassociationResult {
        let normalizedPath = newPath.standardizedFileURL
        let incomingStableKey = StableKey.fromPath(normalizedPath)
        if repositoryTopologyAtom.repos.contains(where: {
            $0.id != repositoryID && $0.stableKey == incomingStableKey
        }) {
            return .rejected(.duplicateRepositoryStableKey(incomingStableKey))
        }

        let preparation = prepareWorktreeReconciliation(
            repositoryID,
            candidates: candidates,
            traceID: traceID
        )
        switch preparation {
        case .rejected(let rejection):
            return .rejected(.worktreeReconciliation(rejection))
        case .prepared(let prepared):
            var repositories = repositoryTopologyAtom.repos
            repositories[prepared.repositoryIndex].name = normalizedPath.lastPathComponent
            repositories[prepared.repositoryIndex].repoPath = normalizedPath
            repositories[prepared.repositoryIndex].worktrees = prepared.mergedWorktrees
            applyTopology(
                repositories: repositories,
                watchedPaths: repositoryTopologyAtom.watchedPaths,
                unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds.subtracting([repositoryID])
            )
            return .accepted(
                .init(
                    worktreeIds: Set(prepared.mergedWorktrees.map(\.id)),
                    delta: prepared.delta
                )
            )
        }
    }

    private func reconcileWorktrees(
        _ repositoryID: UUID,
        candidates: [WorktreeReconciliationCandidate],
        traceID: UUID?
    ) -> RepositoryWorktreeReconciliationResult {
        let preparation = prepareWorktreeReconciliation(
            repositoryID,
            candidates: candidates,
            traceID: traceID
        )
        switch preparation {
        case .rejected(let rejection):
            return .rejected(rejection)
        case .prepared(let prepared):
            if prepared.delta.didChange {
                var repositories = repositoryTopologyAtom.repos
                repositories[prepared.repositoryIndex].worktrees = prepared.mergedWorktrees
                applyTopology(
                    repositories: repositories,
                    watchedPaths: repositoryTopologyAtom.watchedPaths,
                    unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds
                )
            }
            return .accepted(.init(delta: prepared.delta))
        }
    }

    private func prepareWorktreeReconciliation(
        _ repositoryID: UUID,
        candidates: [WorktreeReconciliationCandidate],
        traceID: UUID?
    ) -> WorktreeReconciliationPreparation {
        guard let repositoryIndex = repositoryTopologyAtom.repos.firstIndex(where: { $0.id == repositoryID }) else {
            return .rejected(.repoNotFound(repositoryID))
        }
        if let rejection = identifiedCandidateOwnershipRejection(
            repositoryID: repositoryID,
            candidates: candidates
        ) {
            return .rejected(rejection)
        }

        let existingWorktrees = repositoryTopologyAtom.repos[repositoryIndex].worktrees
        let existingByPath = Dictionary(
            existingWorktrees.map { ($0.path.standardizedFileURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingMainWorktree = existingWorktrees.first(where: \.isMainWorktree)
        let existingByName = Dictionary(
            existingWorktrees.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var consumedExistingIDs = Set<UUID>()
        var preservedWorktreeIDs: [UUID] = []

        let mergedWorktrees = candidates.map { candidate -> Worktree in
            let matchedWorktree: Worktree?
            if let pathMatch = existingByPath[candidate.path.standardizedFileURL],
                !consumedExistingIDs.contains(pathMatch.id)
            {
                matchedWorktree = pathMatch
            } else if candidate.isMainWorktree,
                let existingMainWorktree,
                !consumedExistingIDs.contains(existingMainWorktree.id)
            {
                matchedWorktree = existingMainWorktree
            } else if let nameMatch = existingByName[candidate.name],
                !consumedExistingIDs.contains(nameMatch.id)
            {
                matchedWorktree = nameMatch
            } else {
                matchedWorktree = nil
            }

            if let matchedWorktree {
                consumedExistingIDs.insert(matchedWorktree.id)
                preservedWorktreeIDs.append(matchedWorktree.id)
                return Worktree(
                    id: matchedWorktree.id,
                    repoId: repositoryID,
                    name: candidate.name,
                    path: candidate.path,
                    isMainWorktree: candidate.isMainWorktree,
                    note: matchedWorktree.note
                )
            }
            return candidate.makeUnmatchedWorktree(repositoryID: repositoryID)
        }

        var seenWorktreeIDs = Set(
            repositoryTopologyAtom.repos
                .filter { $0.id != repositoryID }
                .flatMap(\.worktrees)
                .map(\.id)
        )
        for worktree in mergedWorktrees where !seenWorktreeIDs.insert(worktree.id).inserted {
            return .rejected(.duplicateWorktreeId(worktree.id))
        }

        var seenStableKeys = Set(
            repositoryTopologyAtom.repos
                .filter { $0.id != repositoryID }
                .flatMap(\.worktrees)
                .map(\.stableKey)
        )
        for worktree in mergedWorktrees where !seenStableKeys.insert(worktree.stableKey).inserted {
            return .rejected(.duplicateWorktreeStableKey(worktree.stableKey))
        }

        let preservedWorktreeIDSet = Set(preservedWorktreeIDs)
        let removedWorktrees =
            existingWorktrees
            .filter { !preservedWorktreeIDSet.contains($0.id) }
            .map { RemovedWorktreeEntry(id: $0.id, path: $0.path) }
        let addedWorktreeIDs =
            mergedWorktrees
            .filter { !preservedWorktreeIDSet.contains($0.id) }
            .map(\.id)
        let delta = WorktreeTopologyDelta(
            repoId: repositoryID,
            addedWorktreeIds: addedWorktreeIDs,
            removedWorktrees: removedWorktrees,
            preservedWorktreeIds: preservedWorktreeIDs,
            didChange: mergedWorktrees != existingWorktrees,
            traceId: traceID
        )

        return .prepared(
            .init(
                repositoryIndex: repositoryIndex,
                mergedWorktrees: mergedWorktrees,
                delta: delta
            )
        )
    }

    private func identifiedCandidateOwnershipRejection(
        repositoryID: UUID,
        candidates: [WorktreeReconciliationCandidate]
    ) -> RepositoryWorktreeReconciliationRejection? {
        for candidate in candidates {
            guard case .identified(let worktree) = candidate else { continue }
            guard worktree.repoId == repositoryID else {
                return .worktreeRepoMismatch(
                    worktreeId: worktree.id,
                    expectedRepoId: repositoryID,
                    actualRepoId: worktree.repoId
                )
            }
        }
        return nil
    }

    private func applyTopology(
        repositories: [Repo],
        watchedPaths: [WatchedPath],
        unavailableRepositoryIDs: Set<UUID>
    ) {
        switch RepositoryTopologyReplacement.prepare(
            repositories: repositories,
            watchedPaths: watchedPaths,
            unavailableRepositoryIDs: unavailableRepositoryIDs
        ) {
        case .prepared(let replacement):
            repositoryTopologyAtom.replaceTopology(replacement)
        case .rejected(let rejection):
            preconditionFailure("coordinator produced invalid repository topology: \(rejection)")
        }
    }

    private func normalizedRepositoryNote(_ note: String?) -> String? {
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNote?.isEmpty == true ? nil : trimmedNote
    }
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

    func makeUnmatchedWorktree(repositoryID: UUID) -> Worktree {
        switch self {
        case .scannedMain(let candidate):
            Worktree(
                id: UUIDv7.generate(),
                repoId: repositoryID,
                name: candidate.name,
                path: candidate.path,
                isMainWorktree: true
            )
        case .scannedLinked(let candidate):
            Worktree(
                id: UUIDv7.generate(),
                repoId: repositoryID,
                name: candidate.name,
                path: candidate.path,
                isMainWorktree: false
            )
        case .identified(let worktree):
            worktree
        }
    }
}

private struct PreparedWorktreeReconciliation {
    let repositoryIndex: Int
    let mergedWorktrees: [Worktree]
    let delta: WorktreeTopologyDelta
}

private enum WorktreeReconciliationPreparation {
    case prepared(PreparedWorktreeReconciliation)
    case rejected(RepositoryWorktreeReconciliationRejection)
}
