import Foundation

@MainActor
enum RepositoryTopologyParticipantFactoryResult {
    typealias Participant = WorkspaceStateSnapshotPagerParticipant<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >

    case constructed([Participant])
    case rejected(
        participantID: WorkspacePersistenceSnapshotParticipantID,
        rejection: WorkspaceStateSnapshotParticipantRejection
    )
}

struct RepositoryTopologyPersistenceMutationReceipt: Equatable, Sendable {
    let revision: WorkspacePersistenceRevision
}

enum RepositoryTopologyPersistenceAdapterError: Error, Equatable {
    case participant(WorkspaceSnapshotPreparationRejection)
}

struct RepositoryTopologySnapshotCurrentReadDiagnostics: Equatable, Sendable {
    let repositoryLookupCount: UInt64
    let worktreeLookupCount: UInt64
    let watchedPathLookupCount: UInt64
}

@MainActor
final class RepositoryTopologyPersistenceAdapter {
    private let atom: RepositoryTopologyAtom
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let repositoryParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, CanonicalRepo>()
    private let worktreeParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, CanonicalWorktree>()
    private let watchedPathParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, WatchedPath>()
    private let unavailableRepositoryParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, UUID>()

    private var repositoryLookupCount: UInt64 = 0
    private var worktreeLookupCount: UInt64 = 0
    private var watchedPathLookupCount: UInt64 = 0

    init(atom: RepositoryTopologyAtom, revisionOwner: WorkspacePersistenceRevisionOwner) {
        self.atom = atom
        self.revisionOwner = revisionOwner
    }

    var currentReadDiagnostics: RepositoryTopologySnapshotCurrentReadDiagnostics {
        .init(
            repositoryLookupCount: repositoryLookupCount,
            worktreeLookupCount: worktreeLookupCount,
            watchedPathLookupCount: watchedPathLookupCount
        )
    }

    var preparationDiagnostics: [WorkspaceSnapshotPreparationDiagnostics] {
        [
            repositoryParticipant.preparationDiagnostics(),
            worktreeParticipant.preparationDiagnostics(),
            watchedPathParticipant.preparationDiagnostics(),
            unavailableRepositoryParticipant.preparationDiagnostics(),
        ]
    }

    func resetCurrentReadDiagnostics() {
        repositoryLookupCount = 0
        worktreeLookupCount = 0
        watchedPathLookupCount = 0
    }

    private func currentRepository(for id: UUID) -> CanonicalRepo? {
        repositoryLookupCount += 1
        return atom.repo(id).map(Self.canonical)
    }

    private func currentWorktree(for id: UUID) -> CanonicalWorktree? {
        worktreeLookupCount += 1
        return atom.worktree(id).map(Self.canonical)
    }

    private func currentWatchedPath(for id: UUID) -> WatchedPath? {
        watchedPathLookupCount += 1
        return atom.watchedPath(id)
    }

    func makeParticipants(
        membershipLimits: WorkspaceStateSnapshotMembershipLimits
    ) -> RepositoryTopologyParticipantFactoryResult {
        typealias Participant = RepositoryTopologyParticipantFactoryResult.Participant
        let constructions = [
            Participant.typed(
                participantID: .repositories,
                keyedParticipant: repositoryParticipant,
                membershipLimits: membershipLimits,
                orderedBaseKeys: { [atom] in atom.repositoryIdsInOrder },
                currentValue: { [self] id in currentRepository(for: id).map { .value($0) } ?? .absent },
                projection: .init(
                    itemIDForKey: { .repository($0) },
                    projectItem: { _, value in
                        .init(item: .repository(value), estimatedByteCount: Self.estimatedByteCount(value))
                    }
                )
            ),
            Participant.typed(
                participantID: .worktrees,
                keyedParticipant: worktreeParticipant,
                membershipLimits: membershipLimits,
                orderedBaseKeys: { [atom] in atom.worktreeIdsInOrder },
                currentValue: { [self] id in currentWorktree(for: id).map { .value($0) } ?? .absent },
                projection: .init(
                    itemIDForKey: { .worktree($0) },
                    projectItem: { _, value in
                        .init(item: .worktree(value), estimatedByteCount: Self.estimatedByteCount(value))
                    }
                )
            ),
            Participant.typed(
                participantID: .watchedPaths,
                keyedParticipant: watchedPathParticipant,
                membershipLimits: membershipLimits,
                orderedBaseKeys: { [atom] in atom.watchedPathIdsInOrder },
                currentValue: { [self] id in currentWatchedPath(for: id).map { .value($0) } ?? .absent },
                projection: .init(
                    itemIDForKey: { .watchedPath($0) },
                    projectItem: { _, value in
                        .init(item: .watchedPath(value), estimatedByteCount: Self.estimatedByteCount(value))
                    }
                )
            ),
            Participant.typed(
                participantID: .unavailableRepositories,
                keyedParticipant: unavailableRepositoryParticipant,
                membershipLimits: membershipLimits,
                orderedBaseKeys: { [atom] in
                    atom.repositoryIdsInOrder.filter { atom.isRepoUnavailable($0) }
                },
                currentValue: { [atom] id in atom.isRepoUnavailable(id) ? .value(id) : .absent },
                projection: .init(
                    itemIDForKey: { .unavailableRepository($0) },
                    projectItem: { _, value in .init(item: .unavailableRepository(value), estimatedByteCount: 16) }
                )
            ),
        ]
        let participantIDs: [WorkspacePersistenceSnapshotParticipantID] = [
            .repositories, .worktrees, .watchedPaths, .unavailableRepositories,
        ]
        var participants: [Participant] = []
        for (participantID, construction) in zip(participantIDs, constructions) {
            switch construction {
            case .constructed(let participant): participants.append(participant)
            case .rejected(let rejection):
                return .rejected(participantID: participantID, rejection: rejection)
            }
        }
        return .constructed(participants)
    }

    func registerInitialReplacement(
        token _: borrowing WorkspaceTopologyPreinstallToken,
        _ replacement: RepositoryTopologyReplacement,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) -> WorkspaceParticipantRegistration {
        revisionOwner.registerPreparedParticipantMutation(
            participant: self,
            preparation: preparation,
            apply: { [atom, revisionOwner = self.revisionOwner] in
                precondition(
                    revisionOwner.validateActiveCommit(preparation.transaction) == .active,
                    "repository topology initial replacement requires its exact active transaction"
                )
                atom.replaceTopology(replacement)
            },
            cancel: {}
        )
    }

    func prepareReplacement(
        _ replacement: RepositoryTopologyReplacement,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistencePreparedMutation<RepositoryTopologyPersistenceMutationReceipt> {
        let current = Self.projection(
            repositories: atom.repos,
            watchedPaths: atom.watchedPaths,
            unavailableRepositoryIDs: atom.unavailableRepoIds
        )
        let target = Self.projection(of: replacement)
        let preparationResults = [
            repositoryParticipant.prepare(
                Self.mutations(current: current.repositoriesByID, target: target.repositoriesByID),
                for: preparation,
                revisionOwner: revisionOwner
            ),
            worktreeParticipant.prepare(
                Self.mutations(current: current.worktreesByID, target: target.worktreesByID),
                for: preparation,
                revisionOwner: revisionOwner
            ),
            watchedPathParticipant.prepare(
                Self.mutations(current: current.watchedPathsByID, target: target.watchedPathsByID),
                for: preparation,
                revisionOwner: revisionOwner
            ),
            unavailableRepositoryParticipant.prepare(
                Self.membershipMutations(
                    current: current.unavailableRepositoryIDs,
                    target: target.unavailableRepositoryIDs
                ),
                for: preparation,
                revisionOwner: revisionOwner
            ),
        ]
        if case .rejected(let rejection) = preparationResults.first(where: {
            if case .rejected = $0 { true } else { false }
        }) {
            throw RepositoryTopologyPersistenceAdapterError.participant(rejection)
        }
        return preparation.commit { [self] in
            atom.replaceTopology(replacement)
            return .init(revision: preparation.transaction.proposedRevision)
        }
    }

    private static func projection(
        repositories: [Repo],
        watchedPaths: [WatchedPath],
        unavailableRepositoryIDs: Set<UUID>
    ) -> TopologyProjection {
        .init(
            repositoriesByID: Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, canonical($0)) }),
            worktreesByID: Dictionary(
                uniqueKeysWithValues: repositories.flatMap(\.worktrees).map { ($0.id, canonical($0)) }
            ),
            watchedPathsByID: Dictionary(uniqueKeysWithValues: watchedPaths.map { ($0.id, $0) }),
            unavailableRepositoryIDs: unavailableRepositoryIDs
        )
    }

    private static func projection(of replacement: RepositoryTopologyReplacement) -> TopologyProjection {
        projection(
            repositories: replacement.repositories,
            watchedPaths: replacement.watchedPaths,
            unavailableRepositoryIDs: replacement.unavailableRepositoryIDs
        )
    }

    private static func mutations<Value: Identifiable & Equatable & Sendable>(
        current: [UUID: Value],
        target: [UUID: Value]
    ) -> [WorkspaceStateSnapshotParticipantMutation<UUID, Value>] where Value.ID == UUID {
        let removals: [WorkspaceStateSnapshotParticipantMutation<UUID, Value>] = current.compactMap { element in
            let (id, currentValue) = element
            guard target[id] == nil else { return nil }
            return .remove(.init(key: id, currentValue: .value(currentValue)))
        }
        let replacements: [WorkspaceStateSnapshotParticipantMutation<UUID, Value>] = target.values.compactMap { value in
            replacementMutation(value, current: current[value.id])
        }
        return removals + replacements
    }

    private static func replacementMutation<Value: Identifiable & Equatable & Sendable>(
        _ value: Value,
        current: Value?
    ) -> WorkspaceStateSnapshotParticipantMutation<UUID, Value>? where Value.ID == UUID {
        guard let current else {
            return .insert(.init(key: value.id, rawKeyByteCount: 16))
        }
        guard current != value else { return nil }
        return .replaceValue(key: value.id, currentValue: .value(current))
    }

    private static func membershipMutations(
        current: Set<UUID>,
        target: Set<UUID>
    ) -> [WorkspaceStateSnapshotParticipantMutation<UUID, UUID>] {
        current.subtracting(target).map { .remove(.init(key: $0, currentValue: .value($0))) }
            + target.subtracting(current).map { .insert(.init(key: $0, rawKeyByteCount: 16)) }
    }

    private static func estimatedByteCount(_ repository: CanonicalRepo) -> Int {
        16 + MemoryLayout<Date>.size + repository.name.utf8.count + repository.repoPath.path.utf8.count
            + estimatedTagByteCount(repository.tags)
    }

    private static func estimatedByteCount(_ worktree: CanonicalWorktree) -> Int {
        33 + worktree.name.utf8.count + worktree.path.path.utf8.count + estimatedTagByteCount(worktree.tags)
    }

    private static func estimatedByteCount(_ watchedPath: WatchedPath) -> Int {
        16 + MemoryLayout<Date>.size + watchedPath.path.path.utf8.count
    }

    private static func estimatedTagByteCount(_ tags: [String]) -> Int {
        tags.reduce(0) { $0 + MemoryLayout<Int>.size + $1.utf8.count }
    }

    private static func canonical(_ repository: Repo) -> CanonicalRepo {
        .init(
            id: repository.id,
            name: repository.name,
            repoPath: repository.repoPath,
            createdAt: repository.createdAt,
            tags: repository.tags
        )
    }

    private static func canonical(_ worktree: Worktree) -> CanonicalWorktree {
        .init(
            id: worktree.id,
            repoId: worktree.repoId,
            name: worktree.name,
            path: worktree.path,
            isMainWorktree: worktree.isMainWorktree,
            tags: worktree.tags
        )
    }
}

private struct TopologyProjection {
    let repositoriesByID: [UUID: CanonicalRepo]
    let worktreesByID: [UUID: CanonicalWorktree]
    let watchedPathsByID: [UUID: WatchedPath]
    let unavailableRepositoryIDs: Set<UUID>
}
