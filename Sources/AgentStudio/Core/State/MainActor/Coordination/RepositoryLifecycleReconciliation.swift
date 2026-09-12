import AgentStudioInfrastructure
import Foundation

package struct RepositoryLifecycleInput: Sendable {
    package let revision: UInt64
    let membershipRevision: UInt64
    let repositories: [Repo]
    let watchedPaths: [WatchedPath]
    let absenceRecords: RepositoryTopologyAbsenceRecords
    let stableIdentity: RepositoryTopologyStableIdentity
}

package struct RepositoryLifecycleChange: Sendable {
    let expectedRevision: UInt64
    let replacement: RepositoryTopologyReplacement
    package let deltas: [WorktreeTopologyDelta]
    package let reparenting: [RepositoryWorktreeReparenting]
}

package enum RepositoryLifecyclePreparation: Sendable {
    case prepared(RepositoryLifecycleChange)
    case invalid(RepositoryTopologyIdentityRejection)
    case outsideScope
}

package enum RepositoryLifecycleReconciliation {
    @concurrent nonisolated package static func prepare(
        _ input: RepositoryLifecycleInput,
        observation: WatchedFolderTopologyObservation,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil
    ) async -> RepositoryLifecyclePreparation {
        let preparationStart = ContinuousClock.now
        defer {
            performanceTraceRecorder?.recordDuration(
                .repositoryLifecyclePreparation,
                duration: preparationStart.duration(to: .now),
                attributes: [
                    "agentstudio.performance.repository_lifecycle.repository.count": .int(input.repositories.count),
                    "agentstudio.performance.repository_lifecycle.observation.count": .int(observation.entries.count),
                ])
        }
        guard observation.baselineMembershipRevision == input.membershipRevision else { return .outsideScope }
        let root = observation.root.standardizedFileURL
        guard input.watchedPaths.contains(where: { $0.path.standardizedFileURL == root }) else {
            return .outsideScope
        }
        if let conflict = conflictingEvidence(in: observation) { return .invalid(conflict) }
        var repositories = input.repositories
        var absences = input.absenceRecords
        var reparenting: [RepositoryWorktreeReparenting] = []
        let knownByPath = Dictionary(
            input.repositories.flatMap(\.worktrees).map { ($0.path.standardizedFileURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let knownByStableKey = Dictionary(
            input.repositories.flatMap(\.worktrees).compactMap { worktree in
                input.stableIdentity.worktreeStableKeysByID[worktree.id].map { ($0, worktree) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let groups = RepoScanner.groupResolvedEntries(observation.entries)
        // Directory hints can differ between package URLs and grouped URLs for the same canonical path.
        let positivePathKeys = Set(observation.entries.map { $0.path.standardizedFileURL.path })

        for group in groups {
            let familyPath = group.clonePath.standardizedFileURL
            let repositoryID: UUID
            let familyKey = StableKey.fromPath(familyPath)
            if let index = repositories.firstIndex(where: {
                $0.repoPath.standardizedFileURL == familyPath
                    || input.stableIdentity.repositoryStableKeysByID[$0.id] == familyKey
            }) {
                repositoryID = repositories[index].id
                repositories[index].repoPath = familyPath
            } else {
                repositoryID = UUIDv7.generate()
                repositories.append(Repo(id: repositoryID, name: familyPath.lastPathComponent, repoPath: familyPath))
            }
            let paths = ([familyPath] + group.linkedWorktreePaths).filter { positivePathKeys.contains($0.path) }
            for path in paths {
                let canonicalPath = path.standardizedFileURL
                let previous = knownByPath[canonicalPath] ?? knownByStableKey[StableKey.fromPath(canonicalPath)]
                let worktreeID = previous?.id ?? UUIDv7.generate()
                if let previous, previous.repoId != repositoryID {
                    reparenting.append(
                        .init(
                            worktreeID: worktreeID, expectedRepositoryID: previous.repoId, repositoryID: repositoryID
                        ))
                }
                for index in repositories.indices where repositories[index].id != repositoryID {
                    repositories[index].worktrees.removeAll { $0.id == worktreeID }
                }
                guard let target = repositories.firstIndex(where: { $0.id == repositoryID }) else { continue }
                let worktree = Worktree(
                    id: worktreeID,
                    repoId: repositoryID,
                    name: canonicalPath.lastPathComponent,
                    path: canonicalPath,
                    isMainWorktree: canonicalPath == familyPath,
                    note: previous?.note
                )
                if let index = repositories[target].worktrees.firstIndex(where: { $0.id == worktreeID }) {
                    repositories[target].worktrees[index] = worktree
                } else {
                    repositories[target].worktrees.append(worktree)
                }
                absences.worktrees.removeValue(forKey: worktreeID)
                absences.repositories.removeValue(forKey: repositoryID)
            }
        }

        retainEmptyFamiliesWithoutAbsenceEvidence(repositories, absences: &absences)
        applyAuthoritativeAbsence(
            input: input, observation: observation, repositories: repositories, absences: &absences)

        switch RepositoryTopologyReplacement.prepare(
            repositories: repositories,
            watchedPaths: input.watchedPaths,
            unavailableRepositoryIDs: absences.unavailableRepositoryIDs,
            stableIdentity: stableIdentity(for: repositories, retaining: input),
            absenceRecords: absences
        ) {
        case .rejected(let rejection):
            return .invalid(rejection)
        case .prepared(let replacement):
            return .prepared(
                RepositoryLifecycleChange(
                    expectedRevision: input.revision,
                    replacement: replacement,
                    deltas: deltas(previous: input, repositories: repositories, absences: absences),
                    reparenting: reparenting
                )
            )
        }
    }

    private static func retainEmptyFamiliesWithoutAbsenceEvidence(
        _ repositories: [Repo], absences: inout RepositoryTopologyAbsenceRecords
    ) {
        // Positive reparenting can empty a family without providing negative filesystem evidence.
        for repository in repositories where repository.worktrees.isEmpty && absences.repositories[repository.id] == nil
        {
            absences.repositories[repository.id] = .unconfirmed
        }
    }

    private static func stableIdentity(
        for repositories: [Repo], retaining input: RepositoryLifecycleInput
    ) -> RepositoryTopologyStableIdentity {
        RepositoryTopologyStableIdentity(
            repositoryStableKeysByID: Dictionary(
                uniqueKeysWithValues: repositories.map {
                    ($0.id, input.stableIdentity.repositoryStableKeysByID[$0.id] ?? $0.stableKey)
                }),
            worktreeStableKeysByID: Dictionary(
                uniqueKeysWithValues: repositories.flatMap(\.worktrees).map {
                    ($0.id, input.stableIdentity.worktreeStableKeysByID[$0.id] ?? $0.stableKey)
                }),
            watchedPathStableKeysByID: input.stableIdentity.watchedPathStableKeysByID
        )
    }

    private static func conflictingEvidence(in observation: WatchedFolderTopologyObservation)
        -> RepositoryTopologyIdentityRejection?
    {
        let incomingPaths = Set(observation.entries.map { $0.path.standardizedFileURL.path })
        let competingEntries = observation.otherObservedEntries.filter {
            incomingPaths.contains($0.path.standardizedFileURL.path)
        }
        var evidenceByPath: [String: RepoScanner.ResolvedGitEntry] = [:]
        for entry in observation.entries + competingEntries {
            let path = entry.path.standardizedFileURL.path
            if let previous = evidenceByPath[path],
                previous.repositoryKey != entry.repositoryKey || previous.kind != entry.kind
            {
                return .duplicateWorktreeStableKey(StableKey.fromPath(entry.path.standardizedFileURL))
            }
            evidenceByPath[path] = entry
        }
        return nil
    }

    private static func applyAuthoritativeAbsence(
        input: RepositoryLifecycleInput,
        observation: WatchedFolderTopologyObservation,
        repositories: [Repo],
        absences: inout RepositoryTopologyAbsenceRecords
    ) {
        let coveredRoots = Set([observation.root.standardizedFileURL, observation.canonicalRoot.standardizedFileURL])
        let positivePaths = Set(observation.entries.map { $0.path.standardizedFileURL })
        let protectedPaths = observation.otherObservedPaths.union(positivePaths)
        let protectedStableKeys = Set(protectedPaths.map(StableKey.fromPath))
        if case .authoritative(let observedAt) = observation.coverage {
            for repository in repositories {
                for worktree in repository.worktrees {
                    let path = worktree.path.standardizedFileURL
                    guard coveredRoots.contains(where: { covered(path, by: $0) }), !protectedPaths.contains(path),
                        !protectedStableKeys.contains(
                            input.stableIdentity.worktreeStableKeysByID[worktree.id] ?? worktree.stableKey),
                        !observation.incompleteOtherScopes.contains(where: { covered(path, by: $0) })
                    else { continue }
                    if let absence = RepositoryRetentionPolicy.confirmedAbsence(
                        retaining: absences.worktrees[worktree.id], at: observedAt
                    ) {
                        absences.worktrees[worktree.id] = absence
                    }
                }
                let allHidden = repository.worktrees.allSatisfy { absences.worktrees[$0.id] != nil }
                if allHidden {
                    if coveredRoots.contains(where: { covered(repository.repoPath, by: $0) }),
                        !observation.incompleteOtherScopes.contains(where: { covered(repository.repoPath, by: $0) }),
                        !protectedPaths.contains(repository.repoPath),
                        !protectedStableKeys.contains(
                            input.stableIdentity.repositoryStableKeysByID[repository.id] ?? repository.stableKey)
                    {
                        absences.repositories[repository.id] =
                            RepositoryRetentionPolicy.confirmedAbsence(
                                retaining: absences.repositories[repository.id], at: observedAt
                            ) ?? .unconfirmed
                    } else if absences.repositories[repository.id] == nil {
                        absences.repositories[repository.id] = .unconfirmed
                    }
                } else {
                    absences.repositories.removeValue(forKey: repository.id)
                }
            }
        }

    }

    private static func covered(_ path: URL, by root: URL) -> Bool {
        let candidate = path.standardizedFileURL.path
        return root.path == "/" || candidate == root.path || candidate.hasPrefix(root.path + "/")
    }

    private static func activeWorktrees(
        _ repository: Repo,
        absences: RepositoryTopologyAbsenceRecords
    ) -> [Worktree] {
        guard absences.repositories[repository.id] == nil else { return [] }
        return repository.worktrees.filter { absences.worktrees[$0.id] == nil }
    }

    private static func deltas(
        previous: RepositoryLifecycleInput,
        repositories: [Repo],
        absences: RepositoryTopologyAbsenceRecords
    ) -> [WorktreeTopologyDelta] {
        let oldByID = Dictionary(uniqueKeysWithValues: previous.repositories.map { ($0.id, $0) })
        return repositories.compactMap { repository in
            let oldActive = oldByID[repository.id].map { activeWorktrees($0, absences: previous.absenceRecords) } ?? []
            let newActive = activeWorktrees(repository, absences: absences)
            let oldIDs = Set(oldActive.map(\.id))
            let newIDs = Set(newActive.map(\.id))
            guard oldActive != newActive else { return nil }
            return WorktreeTopologyDelta(
                repoId: repository.id,
                addedWorktreeIds: newActive.map(\.id).filter { !oldIDs.contains($0) },
                removedWorktrees: oldActive.filter { !newIDs.contains($0.id) }.map {
                    RemovedWorktreeEntry(id: $0.id, path: $0.path)
                },
                preservedWorktreeIds: newActive.map(\.id).filter { oldIDs.contains($0) },
                didChange: true,
                traceId: nil
            )
        }
    }
}
