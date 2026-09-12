import AgentStudioInfrastructure
import Foundation

package enum RepositoryRetentionPreparation {
    @concurrent nonisolated package static func validationScopeIDs(
        _ input: RepositoryLifecycleInput, at time: RepositoryRetentionTime
    ) async -> Set<UUID> {
        func needsValidation(_ absence: RepositoryLocationAbsence?) -> Bool {
            guard let absence else { return false }
            guard let elapsed = RepositoryRetentionPolicy.elapsedSeconds(for: absence, at: time) else { return true }
            return elapsed >= RepositoryRetentionPolicy.retentionSeconds
        }
        var locations: [URL] = []
        for repository in input.repositories {
            for worktree in repository.worktrees
            where needsValidation(
                input.absenceRecords.worktrees[worktree.id]
                    ?? input.absenceRecords.repositories[repository.id])
            {
                locations.append(worktree.path)
            }
            if repository.worktrees.isEmpty, needsValidation(input.absenceRecords.repositories[repository.id]) {
                locations.append(repository.repoPath)
            }
        }
        return Set(
            input.watchedPaths.compactMap { watch in
                let roots = [watch.path.standardizedFileURL, watch.path.resolvingSymlinksInPath()]
                return locations.contains(where: { path in roots.contains { contains(path, root: $0) } })
                    ? watch.id : nil
            })
    }

    @concurrent nonisolated package static func nextDelay(
        _ input: RepositoryLifecycleInput, at time: RepositoryRetentionTime?
    ) async -> Duration? {
        let roots = input.watchedPaths.flatMap { [$0.path.standardizedFileURL, $0.path.resolvingSymlinksInPath()] }
        let worktrees = input.repositories.flatMap(\.worktrees)
        var values = worktrees.compactMap { worktree -> Duration? in
            guard roots.contains(where: { contains(worktree.path, root: $0) }),
                let absence = input.absenceRecords.worktrees[worktree.id]
                    ?? input.absenceRecords.repositories[worktree.repoId]
            else { return nil }
            guard let time, let elapsed = RepositoryRetentionPolicy.elapsedSeconds(for: absence, at: time) else {
                return AppPolicies.RepositoryRetention.retryDelay
            }
            return .seconds(max(0, RepositoryRetentionPolicy.retentionSeconds - elapsed))
        }
        values += input.repositories.compactMap { repository -> Duration? in
            guard repository.worktrees.isEmpty,
                roots.contains(where: { contains(repository.repoPath, root: $0) }),
                let absence = input.absenceRecords.repositories[repository.id]
            else { return nil }
            guard let time, let elapsed = RepositoryRetentionPolicy.elapsedSeconds(for: absence, at: time) else {
                return AppPolicies.RepositoryRetention.retryDelay
            }
            return .seconds(max(0, RepositoryRetentionPolicy.retentionSeconds - elapsed))
        }
        return values.min()
    }

    @concurrent nonisolated package static func candidates(
        _ input: RepositoryLifecycleInput,
        observations: [WatchedFolderTopologyObservation],
        at time: RepositoryRetentionTime,
        excludingRepositoryKeys: Set<String> = [],
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) async -> RepositoryRetentionCandidates {
        let preparationStart = ContinuousClock.now
        defer {
            performanceTraceRecorder?.recordDuration(
                .repositoryRetentionPreparation,
                duration: preparationStart.duration(to: .now),
                attributes: [
                    "agentstudio.performance.repository_lifecycle.repository.count": .int(input.repositories.count),
                    "agentstudio.performance.repository_lifecycle.observation.count": .int(observations.count),
                ])
        }
        let currentScopes = Set(input.watchedPaths.map(\.id))
        let authoritative = observations.filter {
            guard currentScopes.contains($0.registration.sourceID.rootID) else { return false }
            if case .authoritative = $0.coverage { return true }
            return false
        }
        let positiveKeys = Set(
            observations.flatMap { observation in
                observation.entries.map { StableKey.fromPath($0.path) }
                    + observation.otherObservedPaths.map(StableKey.fromPath)
            }
        )
        var worktreeAbsences: [UUID: RepositoryLocationAbsence] = [:]
        var repositoryAbsences: [UUID: RepositoryLocationAbsence] = [:]
        for repository in input.repositories {
            guard
                !excludingRepositoryKeys.contains(
                    input.stableIdentity.repositoryStableKeysByID[repository.id] ?? repository.stableKey)
            else { continue }
            for worktree in repository.worktrees {
                guard
                    worktreeAbsences.count + repositoryAbsences.count
                        < AppPolicies.RepositoryRetention.collectionBatchLimit,
                    let absence = input.absenceRecords.worktrees[worktree.id],
                    RepositoryRetentionPolicy.isDue(absence, at: time),
                    !positiveKeys.contains(
                        input.stableIdentity.worktreeStableKeysByID[worktree.id] ?? worktree.stableKey),
                    authoritative.contains(where: { observation in
                        (contains(worktree.path, root: observation.root)
                            || contains(worktree.path, root: observation.canonicalRoot))
                            && !observation.incompleteOtherScopes.contains(where: { contains(worktree.path, root: $0) })
                    })
                else { continue }
                worktreeAbsences[worktree.id] = absence
            }
            guard
                worktreeAbsences.count + repositoryAbsences.count
                    < AppPolicies.RepositoryRetention.collectionBatchLimit,
                let absence = input.absenceRecords.repositories[repository.id],
                RepositoryRetentionPolicy.isDue(absence, at: time),
                !positiveKeys.contains(
                    input.stableIdentity.repositoryStableKeysByID[repository.id] ?? repository.stableKey),
                repository.worktrees.allSatisfy({ worktreeAbsences[$0.id] != nil }),
                !repository.worktrees.isEmpty
                    || authoritative.contains(where: {
                        (contains(repository.repoPath, root: $0.root)
                            || contains(repository.repoPath, root: $0.canonicalRoot))
                            && !$0.incompleteOtherScopes.contains(where: { contains(repository.repoPath, root: $0) })
                    })
            else { continue }
            repositoryAbsences[repository.id] = absence
        }
        return .init(repositoryAbsences: repositoryAbsences, worktreeAbsences: worktreeAbsences)
    }

    private static func contains(_ path: URL, root: URL) -> Bool {
        let candidate = path.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return rootPath == "/" || candidate == rootPath || candidate.hasPrefix(rootPath + "/")
    }
}
