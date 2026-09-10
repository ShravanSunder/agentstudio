import AgentStudioInfrastructure
import Foundation

enum RepositoryTopologyMutationError: Error, Equatable {
    case invalidRepositoryTag(String)
    case duplicateRepositoryTag(String)
    case repoNotFound(UUID)
    case worktreeNotFound(UUID)
}

extension WorkspaceMutationCoordinator {
    package func performBatchedTopologyMutation(_ mutation: () -> Void) {
        repositoryTopologyAtom.withDeferredWorktreePathIndexRebuild(mutation)
    }

    @discardableResult
    package func addRepo(at path: URL) -> Repo {
        let normalizedPath = path.standardizedFileURL
        return addRepo(at: normalizedPath, stableKey: StableKey.fromPath(normalizedPath))
    }

    @discardableResult
    package func addRepo(at path: URL, stableKey incomingStableKey: String) -> Repo {
        let normalizedPath = path.standardizedFileURL
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
            unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds.subtracting([repositoryID]),
            repositoryStableKeyOverrides: [repositoryID: incomingStableKey],
            worktreeStableKeyOverrides: [mainWorktree.id: incomingStableKey]
        )
        return repository
    }

    @discardableResult
    package func ensureMainWorktree(at path: URL) -> Worktree {
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
                id: UUIDv7.generate(),
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

    package func removeRepo(_ repositoryID: UUID) {
        guard repositoryTopologyAtom.repo(repositoryID) != nil else { return }
        applyTopology(
            repositories: repositoryTopologyAtom.repos.filter { $0.id != repositoryID },
            watchedPaths: repositoryTopologyAtom.watchedPaths,
            unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds.subtracting([repositoryID])
        )
    }

    package func markRepoUnavailable(_ repositoryID: UUID) {
        guard repositoryTopologyAtom.repo(repositoryID) != nil else { return }
        applyTopology(
            repositories: repositoryTopologyAtom.repos,
            watchedPaths: repositoryTopologyAtom.watchedPaths,
            unavailableRepositoryIDs: repositoryTopologyAtom.unavailableRepoIds.union([repositoryID])
        )
    }

    package func setRepoFavorite(_ repositoryID: UUID, isFavorite: Bool) {
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

    package func setRepoTags(_ tags: [String], repositoryID: UUID) throws {
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
    package func addWatchedPath(_ path: URL) -> WatchedPath? {
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
    package func reassociateRepo(
        _ repositoryID: UUID,
        to newPath: URL,
        discoveredWorktrees: [Worktree]
    ) -> RepositoryReassociationResult {
        applyRepoReassociation(
            reassociateRepo(
                repositoryID,
                to: newPath,
                candidates: discoveredWorktrees.map(WorktreeReconciliationCandidate.identified),
                repositoryStableKey: nil,
                traceID: nil
            )
        )
    }

    @discardableResult
    package func reassociateRepo(
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
                repositoryStableKey: scannedWorktrees.main.stableKey,
                traceID: traceId
            )
        )
    }

    @discardableResult
    package func reconcileScannedWorktrees(
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
    package func reconcileDiscoveredWorktrees(
        _ repositoryID: UUID,
        worktrees: [Worktree]
    ) -> RepositoryWorktreeReconciliationResult {
        reconcileWorktrees(
            repositoryID,
            candidates: worktrees.map(WorktreeReconciliationCandidate.identified),
            traceID: nil
        )
    }

    @discardableResult
    package func unregisterWorktree(
        _ worktreeID: UUID,
        from repositoryID: UUID
    ) -> RepositoryWorktreeReconciliationResult {
        guard let repository = repositoryTopologyAtom.repo(repositoryID) else {
            return .rejected(.repoNotFound(repositoryID))
        }
        guard let removedWorktree = repository.worktrees.first(where: { $0.id == worktreeID }) else {
            return .rejected(.worktreeNotFound(worktreeID))
        }

        let preparation = prepareWorktreeReconciliation(
            repositoryID,
            candidates: repository.worktrees
                .filter { $0.id != worktreeID }
                .map(WorktreeReconciliationCandidate.identified),
            traceID: nil
        )
        switch preparation {
        case .rejected(let rejection):
            return .rejected(rejection)
        case .prepared(let prepared):
            var repositories = repositoryTopologyAtom.repos
            repositories[prepared.repositoryIndex].worktrees = prepared.mergedWorktrees
            let unavailableRepositoryIDs =
                removedWorktree.isMainWorktree
                ? repositoryTopologyAtom.unavailableRepoIds.union([repositoryID])
                : repositoryTopologyAtom.unavailableRepoIds
            switch RepositoryTopologyReplacement.prepare(
                repositories: repositories,
                watchedPaths: repositoryTopologyAtom.watchedPaths,
                unavailableRepositoryIDs: unavailableRepositoryIDs,
                stableIdentity: stableIdentity(
                    repositories: repositories,
                    watchedPaths: repositoryTopologyAtom.watchedPaths
                )
            ) {
            case .prepared(let replacement):
                repositoryTopologyAtom.replaceTopology(replacement)
                return .accepted(.init(delta: prepared.delta))
            case .rejected(let rejection):
                return .rejected(.topologyRejected(rejection))
            }
        }
    }

    private func reassociateRepo(
        _ repositoryID: UUID,
        to newPath: URL,
        candidates: [WorktreeReconciliationCandidate],
        repositoryStableKey: String?,
        traceID: UUID?
    ) -> RepositoryReassociationResult {
        let normalizedPath = newPath.standardizedFileURL
        let incomingStableKey = repositoryStableKey ?? StableKey.fromPath(normalizedPath)
        if repositoryTopologyAtom.repos.contains(where: {
            $0.id != repositoryID && $0.stableKey == incomingStableKey
        }) {
            return .rejected(.duplicateRepositoryStableKey(incomingStableKey))
        }

        let preparation = prepareWorktreeReconciliation(
            repositoryID,
            candidates: candidates,
            repositoryPath: normalizedPath,
            traceID: traceID
        )
        switch preparation {
        case .rejected(let rejection):
            return .rejected(.worktreeReconciliation(rejection))
        case .prepared(let prepared):
            let previousRepository = repositoryTopologyAtom.repos[prepared.repositoryIndex]
            let previousUnavailableRepositoryIDs = repositoryTopologyAtom.unavailableRepoIds
            var repositories = repositoryTopologyAtom.repos
            repositories[prepared.repositoryIndex].name = normalizedPath.lastPathComponent
            repositories[prepared.repositoryIndex].repoPath = normalizedPath
            repositories[prepared.repositoryIndex].worktrees = prepared.mergedWorktrees
            let unavailableRepositoryIDs =
                prepared.hasValidMainWorktree
                ? previousUnavailableRepositoryIDs.subtracting([repositoryID])
                : previousUnavailableRepositoryIDs.union([repositoryID])
            let acceptedDelta = WorktreeTopologyDelta(
                repoId: prepared.delta.repoId,
                addedWorktreeIds: prepared.delta.addedWorktreeIds,
                removedWorktrees: prepared.delta.removedWorktrees,
                preservedWorktreeIds: prepared.delta.preservedWorktreeIds,
                didChange: prepared.delta.didChange
                    || previousRepository.repoPath != normalizedPath
                    || unavailableRepositoryIDs != previousUnavailableRepositoryIDs,
                traceId: prepared.delta.traceId
            )
            applyTopology(
                repositories: repositories,
                watchedPaths: repositoryTopologyAtom.watchedPaths,
                unavailableRepositoryIDs: unavailableRepositoryIDs,
                repositoryStableKeyOverrides: [repositoryID: incomingStableKey],
                worktreeStableKeyOverrides: prepared.worktreeStableKeysByID
            )
            return .accepted(
                .init(
                    worktreeIds: Set(prepared.mergedWorktrees.map(\.id)),
                    delta: acceptedDelta
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
            let previousUnavailableRepositoryIDs = repositoryTopologyAtom.unavailableRepoIds
            let unavailableRepositoryIDs =
                prepared.hasValidMainWorktree
                ? previousUnavailableRepositoryIDs.subtracting([repositoryID])
                : previousUnavailableRepositoryIDs.union([repositoryID])
            let acceptedDelta = WorktreeTopologyDelta(
                repoId: prepared.delta.repoId,
                addedWorktreeIds: prepared.delta.addedWorktreeIds,
                removedWorktrees: prepared.delta.removedWorktrees,
                preservedWorktreeIds: prepared.delta.preservedWorktreeIds,
                didChange: prepared.delta.didChange
                    || unavailableRepositoryIDs != previousUnavailableRepositoryIDs,
                traceId: prepared.delta.traceId
            )
            if acceptedDelta.didChange {
                var repositories = repositoryTopologyAtom.repos
                repositories[prepared.repositoryIndex].worktrees = prepared.mergedWorktrees
                applyTopology(
                    repositories: repositories,
                    watchedPaths: repositoryTopologyAtom.watchedPaths,
                    unavailableRepositoryIDs: unavailableRepositoryIDs,
                    worktreeStableKeyOverrides: prepared.worktreeStableKeysByID
                )
            }
            return .accepted(.init(delta: acceptedDelta))
        }
    }

    private func prepareWorktreeReconciliation(
        _ repositoryID: UUID,
        candidates: [WorktreeReconciliationCandidate],
        repositoryPath: URL? = nil,
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
        let matchedCandidates = matchCandidatesPreservingExistingWorktreeIdentity(
            repositoryID: repositoryID,
            candidates: candidates,
            existingWorktrees: existingWorktrees
        )
        let candidateWorktrees = matchedCandidates.worktrees
        let candidateStableKeysByID = matchedCandidates.stableKeysByID
        let preservedWorktreeIDs = matchedCandidates.preservedWorktreeIDs
        let normalizedRepositoryPath = (repositoryPath ?? repositoryTopologyAtom.repos[repositoryIndex].repoPath)
            .standardizedFileURL
        let rootWorktreeIndexes = candidateWorktrees.indices.filter { index in
            candidateWorktrees[index].path.standardizedFileURL == normalizedRepositoryPath
        }
        let hasValidMainWorktree = rootWorktreeIndexes.count == 1
        let rootWorktreeIndex = rootWorktreeIndexes.first
        let mergedWorktrees = candidateWorktrees.enumerated().map { index, worktree in
            guard hasValidMainWorktree else { return worktree }
            var normalizedWorktree = worktree
            normalizedWorktree.isMainWorktree = index == rootWorktreeIndex
            return normalizedWorktree
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
                .compactMap { repositoryTopologyAtom.worktreeStableKey(for: $0.id) }
        )
        for worktree in mergedWorktrees {
            guard let stableKey = candidateStableKeysByID[worktree.id] else {
                return .rejected(.topologyRejected(.missingWorktreeStableKey(worktree.id)))
            }
            guard seenStableKeys.insert(stableKey).inserted else {
                return .rejected(.duplicateWorktreeStableKey(stableKey))
            }
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
                worktreeStableKeysByID: candidateStableKeysByID,
                hasValidMainWorktree: hasValidMainWorktree,
                delta: delta
            )
        )
    }

    private func matchCandidatesPreservingExistingWorktreeIdentity(
        repositoryID: UUID,
        candidates: [WorktreeReconciliationCandidate],
        existingWorktrees: [Worktree]
    ) -> MatchedCandidateWorktrees {
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
        var stableKeysByID: [UUID: String] = [:]

        let worktrees = candidates.map { candidate -> Worktree in
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
                let updatedWorktree = Worktree(
                    id: matchedWorktree.id,
                    repoId: repositoryID,
                    name: candidate.name,
                    path: candidate.path,
                    isMainWorktree: candidate.isMainWorktree,
                    note: matchedWorktree.note
                )
                stableKeysByID[updatedWorktree.id] = candidate.stableKey
                return updatedWorktree
            }
            let unmatchedWorktree = candidate.makeUnmatchedWorktree(repositoryID: repositoryID)
            stableKeysByID[unmatchedWorktree.id] = candidate.stableKey
            return unmatchedWorktree
        }
        return MatchedCandidateWorktrees(
            worktrees: worktrees,
            preservedWorktreeIDs: preservedWorktreeIDs,
            stableKeysByID: stableKeysByID
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
        unavailableRepositoryIDs: Set<UUID>,
        repositoryStableKeyOverrides: [UUID: String] = [:],
        worktreeStableKeyOverrides: [UUID: String] = [:],
        watchedPathStableKeyOverrides: [UUID: String] = [:]
    ) {
        switch RepositoryTopologyReplacement.prepare(
            repositories: repositories,
            watchedPaths: watchedPaths,
            unavailableRepositoryIDs: unavailableRepositoryIDs,
            stableIdentity: stableIdentity(
                repositories: repositories,
                watchedPaths: watchedPaths,
                repositoryStableKeyOverrides: repositoryStableKeyOverrides,
                worktreeStableKeyOverrides: worktreeStableKeyOverrides,
                watchedPathStableKeyOverrides: watchedPathStableKeyOverrides
            )
        ) {
        case .prepared(let replacement):
            repositoryTopologyAtom.replaceTopology(replacement)
        case .rejected(let rejection):
            preconditionFailure("coordinator produced invalid repository topology: \(rejection)")
        }
    }

    private func stableIdentity(
        repositories: [Repo],
        watchedPaths: [WatchedPath],
        repositoryStableKeyOverrides: [UUID: String] = [:],
        worktreeStableKeyOverrides: [UUID: String] = [:],
        watchedPathStableKeyOverrides: [UUID: String] = [:]
    ) -> RepositoryTopologyStableIdentity {
        var repositoryStableKeysByID: [UUID: String] = [:]
        var worktreeStableKeysByID: [UUID: String] = [:]
        var watchedPathStableKeysByID: [UUID: String] = [:]

        for repository in repositories {
            if let stableKey = repositoryStableKeyOverrides[repository.id] {
                repositoryStableKeysByID[repository.id] = stableKey
            } else {
                let previousRepository = repositoryTopologyAtom.repo(repository.id)
                if previousRepository?.repoPath.standardizedFileURL == repository.repoPath.standardizedFileURL,
                    let stableKey = repositoryTopologyAtom.repositoryStableKey(for: repository.id)
                {
                    repositoryStableKeysByID[repository.id] = stableKey
                } else {
                    repositoryStableKeysByID[repository.id] = StableKey.fromPath(repository.repoPath)
                }
            }
            for worktree in repository.worktrees {
                if let stableKey = worktreeStableKeyOverrides[worktree.id] {
                    worktreeStableKeysByID[worktree.id] = stableKey
                    continue
                }
                let previousWorktree = repositoryTopologyAtom.worktree(worktree.id)
                if previousWorktree?.path.standardizedFileURL == worktree.path.standardizedFileURL,
                    let stableKey = repositoryTopologyAtom.worktreeStableKey(for: worktree.id)
                {
                    worktreeStableKeysByID[worktree.id] = stableKey
                } else {
                    worktreeStableKeysByID[worktree.id] = StableKey.fromPath(worktree.path)
                }
            }
        }
        for watchedPath in watchedPaths {
            if let stableKey = watchedPathStableKeyOverrides[watchedPath.id] {
                watchedPathStableKeysByID[watchedPath.id] = stableKey
                continue
            }
            let previousWatchedPath = repositoryTopologyAtom.watchedPath(watchedPath.id)
            if previousWatchedPath?.path.standardizedFileURL == watchedPath.path.standardizedFileURL,
                let stableKey = repositoryTopologyAtom.watchedPathStableKeysByID[watchedPath.id]
            {
                watchedPathStableKeysByID[watchedPath.id] = stableKey
            } else {
                watchedPathStableKeysByID[watchedPath.id] = StableKey.fromPath(watchedPath.path)
            }
        }
        return RepositoryTopologyStableIdentity(
            repositoryStableKeysByID: repositoryStableKeysByID,
            worktreeStableKeysByID: worktreeStableKeysByID,
            watchedPathStableKeysByID: watchedPathStableKeysByID
        )
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

    var stableKey: String {
        switch self {
        case .scannedMain(let candidate): candidate.stableKey
        case .scannedLinked(let candidate): candidate.stableKey
        case .identified(let worktree): worktree.stableKey
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
    let worktreeStableKeysByID: [UUID: String]
    let hasValidMainWorktree: Bool
    let delta: WorktreeTopologyDelta
}

private struct MatchedCandidateWorktrees {
    let worktrees: [Worktree]
    let preservedWorktreeIDs: [UUID]
    let stableKeysByID: [UUID: String]
}

private enum WorktreeReconciliationPreparation {
    case prepared(PreparedWorktreeReconciliation)
    case rejected(RepositoryWorktreeReconciliationRejection)
}
