import Foundation

extension RepositoryTopologyAtom {
    var snapshotCurrentReadDiagnostics: RepositoryTopologySnapshotCurrentReadDiagnostics {
        snapshotStorage.currentReadDiagnostics
    }

    var snapshotPreparationDiagnostics: [WorkspaceSnapshotPreparationDiagnostics] {
        snapshotStorage.preparationDiagnostics
    }

    func resetSnapshotCurrentReadDiagnostics() {
        snapshotStorage.resetCurrentReadDiagnostics()
    }

    func snapshotRepository(for id: UUID) -> CanonicalRepo? {
        snapshotStorage.repository(for: id)
    }

    func snapshotWorktree(for id: UUID) -> CanonicalWorktree? {
        snapshotStorage.worktree(for: id)
    }

    func snapshotWatchedPath(for id: UUID) -> WatchedPath? {
        snapshotStorage.watchedPath(for: id)
    }

    func makeSnapshotParticipants() -> [WorkspaceStateSnapshotPagerParticipant<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >]? {
        snapshotStorage.makeParticipants()
    }
}

enum RepositoryTopologyIdentityRejection: Error, Equatable {
    case duplicateRepositoryID(UUID)
    case duplicateWorktreeID(UUID)
    case duplicateWatchedPathID(UUID)
    case worktreeRepositoryMissing(worktreeID: UUID, repositoryID: UUID)
    case unavailableRepositoryMissing(UUID)
}

enum RepositoryTopologyHydrationResult: Equatable {
    case applied
    case rejected(RepositoryTopologyIdentityRejection)
}

enum RepositoryTopologyEntityMutation<Value: Identifiable & Sendable>: Sendable where Value.ID == UUID {
    case insert(Value)
    case update(Value)
    case remove(UUID)

    var id: UUID {
        switch self {
        case .insert(let value), .update(let value): value.id
        case .remove(let id): id
        }
    }
}

enum RepositoryTopologyEntityKind: Equatable, Sendable {
    case repository
    case worktree
    case watchedPath
}

enum RepositoryTopologyAvailabilityMutation: Sendable {
    case insert(UUID)
    case remove(UUID)

    var id: UUID {
        switch self {
        case .insert(let id), .remove(let id): id
        }
    }
}

struct RepositoryTopologyStagedMutationBatch: Sendable {
    let repositories: [RepositoryTopologyEntityMutation<CanonicalRepo>]
    let worktrees: [RepositoryTopologyEntityMutation<CanonicalWorktree>]
    let watchedPaths: [RepositoryTopologyEntityMutation<WatchedPath>]
    let unavailableRepositories: [RepositoryTopologyAvailabilityMutation]

    init(
        repositories: [RepositoryTopologyEntityMutation<CanonicalRepo>] = [],
        worktrees: [RepositoryTopologyEntityMutation<CanonicalWorktree>] = [],
        watchedPaths: [RepositoryTopologyEntityMutation<WatchedPath>] = [],
        unavailableRepositories: [RepositoryTopologyAvailabilityMutation] = []
    ) {
        self.repositories = repositories
        self.worktrees = worktrees
        self.watchedPaths = watchedPaths
        self.unavailableRepositories = unavailableRepositories
    }
}

enum RepositoryTopologyStagedMutationError: Error, Equatable {
    case duplicateRepositoryMutation(UUID)
    case duplicateWorktreeMutation(UUID)
    case duplicateWatchedPathMutation(UUID)
    case duplicateUnavailableRepositoryMutation(UUID)
    case entityInsertAlreadyExists(RepositoryTopologyEntityKind, UUID)
    case entityUpdateMissing(RepositoryTopologyEntityKind, UUID)
    case entityRemoveMissing(RepositoryTopologyEntityKind, UUID)
    case unavailableRepositoryInsertAlreadyExists(UUID)
    case unavailableRepositoryRemoveMissing(UUID)
    case repositoryRemovalMissingWorktreeTombstone(repositoryID: UUID, worktreeID: UUID)
    case repositoryRemovalMissingUnavailableTombstone(UUID)
    case identity(RepositoryTopologyIdentityRejection)
    case participant(WorkspaceSnapshotPreparationRejection)
}

struct RepositoryTopologyStagedMutationReceipt: Equatable, Sendable {
    let revision: WorkspacePersistenceRevision
}

struct RepositoryTopologySnapshotCurrentReadDiagnostics: Equatable, Sendable {
    let repositoryLookupCount: UInt64
    let worktreeLookupCount: UInt64
    let watchedPathLookupCount: UInt64
    let unavailableRepositoryLookupCount: UInt64
}

@MainActor
final class RepositoryTopologySnapshotStorage {
    private let repositoryParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, CanonicalRepo>()
    private let worktreeParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, CanonicalWorktree>()
    private let watchedPathParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, WatchedPath>()
    private let unavailableRepositoryParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, UUID>()

    private var repositoriesByID: [UUID: CanonicalRepo] = [:]
    private var worktreesByID: [UUID: CanonicalWorktree] = [:]
    private var runtimeRepositoriesByID: [UUID: Repo] = [:]
    private var runtimeWorktreesByID: [UUID: Worktree] = [:]
    private var watchedPathsByID: [UUID: WatchedPath] = [:]
    private var unavailableRepositoryIDs: Set<UUID> = []
    private var orderedRepositoryIDs: [UUID] = []
    private var orderedWorktreeIDs: [UUID] = []
    private var orderedWatchedPathIDs: [UUID] = []
    private var repositoryLookupCount: UInt64 = 0
    private var worktreeLookupCount: UInt64 = 0
    private var watchedPathLookupCount: UInt64 = 0
    private var unavailableRepositoryLookupCount: UInt64 = 0

    var currentReadDiagnostics: RepositoryTopologySnapshotCurrentReadDiagnostics {
        .init(
            repositoryLookupCount: repositoryLookupCount,
            worktreeLookupCount: worktreeLookupCount,
            watchedPathLookupCount: watchedPathLookupCount,
            unavailableRepositoryLookupCount: unavailableRepositoryLookupCount
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

    var allWorktreeIDs: Set<UUID> {
        Set(runtimeWorktreesByID.keys)
    }

    func resetCurrentReadDiagnostics() {
        repositoryLookupCount = 0
        worktreeLookupCount = 0
        watchedPathLookupCount = 0
        unavailableRepositoryLookupCount = 0
    }

    func repository(for id: UUID) -> CanonicalRepo? {
        repositoryLookupCount += 1
        return repositoriesByID[id]
    }

    func runtimeRepository(for id: UUID) -> Repo? {
        runtimeRepositoriesByID[id]
    }

    func runtimeWorktree(for id: UUID) -> Worktree? {
        runtimeWorktreesByID[id]
    }

    func worktree(for id: UUID) -> CanonicalWorktree? {
        worktreeLookupCount += 1
        return worktreesByID[id]
    }

    func watchedPath(for id: UUID) -> WatchedPath? {
        watchedPathLookupCount += 1
        return watchedPathsByID[id]
    }

    func isUnavailable(_ id: UUID) -> Bool {
        unavailableRepositoryLookupCount += 1
        return unavailableRepositoryIDs.contains(id)
    }

    func validate(
        repositories: [Repo],
        watchedPaths: [WatchedPath],
        unavailableRepositoryIDs: Set<UUID>
    ) -> RepositoryTopologyIdentityRejection? {
        var repositoryIDs = Set<UUID>()
        var worktreeIDs = Set<UUID>()
        var watchedPathIDs = Set<UUID>()
        for repository in repositories {
            guard repositoryIDs.insert(repository.id).inserted else {
                return .duplicateRepositoryID(repository.id)
            }
            for worktree in repository.worktrees {
                guard worktreeIDs.insert(worktree.id).inserted else {
                    return .duplicateWorktreeID(worktree.id)
                }
                guard worktree.repoId == repository.id else {
                    return .worktreeRepositoryMissing(worktreeID: worktree.id, repositoryID: worktree.repoId)
                }
            }
        }
        for watchedPath in watchedPaths where !watchedPathIDs.insert(watchedPath.id).inserted {
            return .duplicateWatchedPathID(watchedPath.id)
        }
        if let missingID = unavailableRepositoryIDs.first(where: { !repositoryIDs.contains($0) }) {
            return .unavailableRepositoryMissing(missingID)
        }
        return nil
    }

    func synchronize(
        repositories: [Repo],
        watchedPaths: [WatchedPath],
        unavailableRepositoryIDs: Set<UUID>
    ) {
        precondition(
            validate(
                repositories: repositories,
                watchedPaths: watchedPaths,
                unavailableRepositoryIDs: unavailableRepositoryIDs
            ) == nil,
            "repository topology identity must be validated before snapshot index construction"
        )
        orderedRepositoryIDs = repositories.map(\.id)
        orderedWorktreeIDs = repositories.flatMap(\.worktrees).map(\.id)
        orderedWatchedPathIDs = watchedPaths.map(\.id)
        repositoriesByID = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, Self.canonical($0)) })
        worktreesByID = Dictionary(
            uniqueKeysWithValues: repositories.flatMap(\.worktrees).map { ($0.id, Self.canonical($0)) }
        )
        watchedPathsByID = Dictionary(uniqueKeysWithValues: watchedPaths.map { ($0.id, $0) })
        runtimeRepositoriesByID = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
        runtimeWorktreesByID = Dictionary(
            uniqueKeysWithValues: repositories.flatMap(\.worktrees).map { ($0.id, $0) }
        )
        self.unavailableRepositoryIDs = unavailableRepositoryIDs
    }

    func makeParticipants() -> [WorkspaceStateSnapshotPagerParticipant<
        WorkspacePersistenceSnapshotParticipantID, WorkspacePersistenceSnapshotItem
    >]? {
        typealias Participant = WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >
        let limits = WorkspaceStateSnapshotMembershipLimits(maximumKeyCount: .max, maximumRawKeyBytes: .max)
        let constructions = [
            Participant.typed(
                participantID: .repositories,
                keyedParticipant: repositoryParticipant,
                membershipLimits: limits,
                orderedBaseKeys: { [self] in orderedRepositoryIDs },
                currentValue: { [self] id -> WorkspaceStateSnapshotStoredValue<CanonicalRepo> in
                    repositoriesByID[id].map { .value($0) } ?? .absent
                },
                projection: WorkspaceStateSnapshotItemProjection(
                    itemIDForKey: { .repository($0) },
                    projectItem: { _, value in
                        .init(
                            item: .repository(value),
                            estimatedByteCount: Self.estimatedSnapshotByteCount(value)
                        )
                    }
                )
            ),
            Participant.typed(
                participantID: .worktrees,
                keyedParticipant: worktreeParticipant,
                membershipLimits: limits,
                orderedBaseKeys: { [self] in orderedWorktreeIDs },
                currentValue: { [self] id -> WorkspaceStateSnapshotStoredValue<CanonicalWorktree> in
                    worktreesByID[id].map { .value($0) } ?? .absent
                },
                projection: WorkspaceStateSnapshotItemProjection(
                    itemIDForKey: { .worktree($0) },
                    projectItem: { _, value in
                        .init(
                            item: .worktree(value),
                            estimatedByteCount: Self.estimatedSnapshotByteCount(value)
                        )
                    }
                )
            ),
            Participant.typed(
                participantID: .watchedPaths,
                keyedParticipant: watchedPathParticipant,
                membershipLimits: limits,
                orderedBaseKeys: { [self] in orderedWatchedPathIDs },
                currentValue: { [self] id -> WorkspaceStateSnapshotStoredValue<WatchedPath> in
                    watchedPathsByID[id].map { .value($0) } ?? .absent
                },
                projection: WorkspaceStateSnapshotItemProjection(
                    itemIDForKey: { .watchedPath($0) },
                    projectItem: { _, value in
                        .init(
                            item: .watchedPath(value),
                            estimatedByteCount: Self.estimatedSnapshotByteCount(value)
                        )
                    }
                )
            ),
            Participant.typed(
                participantID: .unavailableRepositories,
                keyedParticipant: unavailableRepositoryParticipant,
                membershipLimits: limits,
                orderedBaseKeys: { [self] in orderedRepositoryIDs.filter(unavailableRepositoryIDs.contains) },
                currentValue: { [self] id -> WorkspaceStateSnapshotStoredValue<UUID> in
                    unavailableRepositoryIDs.contains(id) ? .value(id) : .absent
                },
                projection: WorkspaceStateSnapshotItemProjection(
                    itemIDForKey: { .unavailableRepository($0) },
                    projectItem: { _, value in .init(item: .unavailableRepository(value), estimatedByteCount: 16) }
                )
            ),
        ]
        let participants: [Participant] = constructions.compactMap {
            guard case .constructed(let participant) = $0 else { return nil }
            return participant
        }
        return participants.count == constructions.count ? participants : nil
    }

    func prepare(
        _ batch: RepositoryTopologyStagedMutationBatch,
        preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws {
        try validate(batch)

        let participantBatches: [WorkspaceStateSnapshotParticipantPreparationResult] = [
            repositoryParticipant.prepare(
                Self.snapshotMutations(batch.repositories, current: repositoriesByID), for: preparation,
                revisionOwner: revisionOwner),
            worktreeParticipant.prepare(
                Self.snapshotMutations(batch.worktrees, current: worktreesByID), for: preparation,
                revisionOwner: revisionOwner),
            watchedPathParticipant.prepare(
                Self.snapshotMutations(batch.watchedPaths, current: watchedPathsByID), for: preparation,
                revisionOwner: revisionOwner),
            unavailableRepositoryParticipant.prepare(
                batch.unavailableRepositories.map { mutation in
                    switch mutation {
                    case .insert(let id): .insert(.init(key: id, rawKeyByteCount: 16))
                    case .remove(let id): .remove(.init(key: id, currentValue: .value(id)))
                    }
                },
                for: preparation,
                revisionOwner: revisionOwner
            ),
        ]
        if case .rejected(let rejection) = participantBatches.first(where: {
            if case .rejected = $0 { true } else { false }
        }) {
            throw RepositoryTopologyStagedMutationError.participant(rejection)
        }
    }

    func validate(_ batch: RepositoryTopologyStagedMutationBatch) throws {
        try Self.requireUnique(
            batch.repositories, error: RepositoryTopologyStagedMutationError.duplicateRepositoryMutation)
        try Self.requireUnique(batch.worktrees, error: RepositoryTopologyStagedMutationError.duplicateWorktreeMutation)
        try Self.requireUnique(
            batch.watchedPaths, error: RepositoryTopologyStagedMutationError.duplicateWatchedPathMutation)
        try Self.requireUnique(
            batch.unavailableRepositories,
            error: RepositoryTopologyStagedMutationError.duplicateUnavailableRepositoryMutation)
        try Self.validateEntityMutations(
            batch.repositories,
            current: repositoriesByID,
            entityKind: .repository
        )
        try Self.validateEntityMutations(
            batch.worktrees,
            current: worktreesByID,
            entityKind: .worktree
        )
        try Self.validateEntityMutations(
            batch.watchedPaths,
            current: watchedPathsByID,
            entityKind: .watchedPath
        )
        try validateAvailabilityMutations(batch.unavailableRepositories)

        var projectedRepositoryIDs = Set(repositoriesByID.keys)
        for mutation in batch.repositories {
            switch mutation {
            case .insert(let repository): projectedRepositoryIDs.insert(repository.id)
            case .update:
                break
            case .remove(let id): projectedRepositoryIDs.remove(id)
            }
        }
        for mutation in batch.worktrees {
            let worktree: CanonicalWorktree
            switch mutation {
            case .insert(let inserted), .update(let inserted): worktree = inserted
            case .remove: continue
            }
            guard projectedRepositoryIDs.contains(worktree.repoId) else {
                throw RepositoryTopologyStagedMutationError.identity(
                    .worktreeRepositoryMissing(worktreeID: worktree.id, repositoryID: worktree.repoId)
                )
            }
        }
        for mutation in batch.unavailableRepositories {
            guard case .insert(let id) = mutation else { continue }
            guard projectedRepositoryIDs.contains(id) else {
                throw RepositoryTopologyStagedMutationError.identity(.unavailableRepositoryMissing(id))
            }
        }
        let worktreeRemovalIDs = Set(
            batch.worktrees.compactMap { mutation -> UUID? in
                guard case .remove(let id) = mutation else { return nil }
                return id
            })
        let unavailableRemovalIDs = Set(
            batch.unavailableRepositories.compactMap { mutation -> UUID? in
                guard case .remove(let id) = mutation else { return nil }
                return id
            })
        for mutation in batch.repositories {
            guard case .remove(let repositoryID) = mutation else { continue }
            for worktree in worktreesByID.values where worktree.repoId == repositoryID {
                guard worktreeRemovalIDs.contains(worktree.id) else {
                    throw RepositoryTopologyStagedMutationError.repositoryRemovalMissingWorktreeTombstone(
                        repositoryID: repositoryID,
                        worktreeID: worktree.id
                    )
                }
            }
            if unavailableRepositoryIDs.contains(repositoryID),
                !unavailableRemovalIDs.contains(repositoryID)
            {
                throw RepositoryTopologyStagedMutationError.repositoryRemovalMissingUnavailableTombstone(
                    repositoryID
                )
            }
        }
    }

    func apply(
        _ batch: RepositoryTopologyStagedMutationBatch,
        repositories: inout [Repo],
        watchedPaths: inout [WatchedPath],
        unavailableRepositoryIDs: inout Set<UUID>
    ) {
        for mutation in batch.repositories {
            switch mutation {
            case .insert(let canonical), .update(let canonical):
                if let index = repositories.firstIndex(where: { $0.id == canonical.id }) {
                    repositories[index].name = canonical.name
                    repositories[index].repoPath = canonical.repoPath
                    repositories[index].createdAt = canonical.createdAt
                    repositories[index].tags = canonical.tags
                } else {
                    repositories.append(
                        Repo(
                            id: canonical.id,
                            name: canonical.name,
                            repoPath: canonical.repoPath,
                            createdAt: canonical.createdAt,
                            tags: canonical.tags
                        )
                    )
                }
            case .remove(let id):
                repositories.removeAll { $0.id == id }
                unavailableRepositoryIDs.remove(id)
            }
        }
        for mutation in batch.worktrees {
            apply(mutation, repositories: &repositories)
        }
        for mutation in batch.watchedPaths {
            switch mutation {
            case .insert(let watchedPath), .update(let watchedPath):
                if let index = watchedPaths.firstIndex(where: { $0.id == watchedPath.id }) {
                    watchedPaths[index] = watchedPath
                } else {
                    watchedPaths.append(watchedPath)
                }
            case .remove(let id): watchedPaths.removeAll { $0.id == id }
            }
        }
        for mutation in batch.unavailableRepositories {
            switch mutation {
            case .insert(let id): unavailableRepositoryIDs.insert(id)
            case .remove(let id): unavailableRepositoryIDs.remove(id)
            }
        }
        synchronize(
            repositories: repositories,
            watchedPaths: watchedPaths,
            unavailableRepositoryIDs: unavailableRepositoryIDs
        )
    }

    private func apply(
        _ mutation: RepositoryTopologyEntityMutation<CanonicalWorktree>,
        repositories: inout [Repo]
    ) {
        switch mutation {
        case .insert(let canonical), .update(let canonical):
            for repositoryIndex in repositories.indices {
                let repositoryID = repositories[repositoryIndex].id
                repositories[repositoryIndex].worktrees.removeAll {
                    $0.id == canonical.id && repositoryID != canonical.repoId
                }
            }
            guard let repositoryIndex = repositories.firstIndex(where: { $0.id == canonical.repoId }) else {
                preconditionFailure("validated topology mutation lost worktree repository")
            }
            let runtime = Worktree(
                id: canonical.id,
                repoId: canonical.repoId,
                name: canonical.name,
                path: canonical.path,
                isMainWorktree: canonical.isMainWorktree,
                tags: canonical.tags
            )
            if let worktreeIndex = repositories[repositoryIndex].worktrees.firstIndex(where: { $0.id == canonical.id })
            {
                repositories[repositoryIndex].worktrees[worktreeIndex] = runtime
            } else {
                repositories[repositoryIndex].worktrees.append(runtime)
            }
        case .remove(let id):
            for repositoryIndex in repositories.indices {
                repositories[repositoryIndex].worktrees.removeAll { $0.id == id }
            }
        }
    }

    private static func requireUnique<Mutation>(
        _ mutations: [Mutation],
        id: (Mutation) -> UUID,
        error: (UUID) -> RepositoryTopologyStagedMutationError
    ) throws {
        var ids = Set<UUID>()
        for mutation in mutations {
            let mutationID = id(mutation)
            guard ids.insert(mutationID).inserted else { throw error(mutationID) }
        }
    }

    private static func requireUnique<Value>(
        _ mutations: [RepositoryTopologyEntityMutation<Value>],
        error: (UUID) -> RepositoryTopologyStagedMutationError
    ) throws where Value: Identifiable & Sendable, Value.ID == UUID {
        try requireUnique(mutations, id: \.id, error: error)
    }

    private static func validateEntityMutations<Value>(
        _ mutations: [RepositoryTopologyEntityMutation<Value>],
        current: [UUID: Value],
        entityKind: RepositoryTopologyEntityKind
    ) throws where Value: Identifiable & Sendable, Value.ID == UUID {
        for mutation in mutations {
            switch mutation {
            case .insert(let value):
                guard current[value.id] == nil else {
                    throw RepositoryTopologyStagedMutationError.entityInsertAlreadyExists(
                        entityKind,
                        value.id
                    )
                }
            case .update(let value):
                guard current[value.id] != nil else {
                    throw RepositoryTopologyStagedMutationError.entityUpdateMissing(
                        entityKind,
                        value.id
                    )
                }
            case .remove(let id):
                guard current[id] != nil else {
                    throw RepositoryTopologyStagedMutationError.entityRemoveMissing(entityKind, id)
                }
            }
        }
    }

    private func validateAvailabilityMutations(
        _ mutations: [RepositoryTopologyAvailabilityMutation]
    ) throws {
        for mutation in mutations {
            switch mutation {
            case .insert(let id):
                guard !unavailableRepositoryIDs.contains(id) else {
                    throw RepositoryTopologyStagedMutationError.unavailableRepositoryInsertAlreadyExists(id)
                }
            case .remove(let id):
                guard unavailableRepositoryIDs.contains(id) else {
                    throw RepositoryTopologyStagedMutationError.unavailableRepositoryRemoveMissing(id)
                }
            }
        }
    }

    private static func requireUnique(
        _ mutations: [RepositoryTopologyAvailabilityMutation],
        error: (UUID) -> RepositoryTopologyStagedMutationError
    ) throws {
        try requireUnique(mutations, id: \.id, error: error)
    }

    private static func snapshotMutations<Value>(
        _ mutations: [RepositoryTopologyEntityMutation<Value>],
        current: [UUID: Value]
    ) -> [WorkspaceStateSnapshotParticipantMutation<UUID, Value>]
    where Value: Identifiable & Sendable, Value.ID == UUID {
        mutations.map { mutation in
            switch mutation {
            case .insert(let value):
                .insert(.init(key: value.id, rawKeyByteCount: 16))
            case .update(let value):
                .replaceValue(
                    key: value.id,
                    currentValue: current[value.id].map { .value($0) } ?? .absent
                )
            case .remove(let id):
                .remove(.init(key: id, currentValue: current[id].map { .value($0) } ?? .absent))
            }
        }
    }

    private static func estimatedSnapshotByteCount(_ repository: CanonicalRepo) -> Int {
        16 + MemoryLayout<Date>.size + repository.name.utf8.count + repository.repoPath.path.utf8.count
            + estimatedTagByteCount(repository.tags)
    }

    private static func estimatedSnapshotByteCount(_ worktree: CanonicalWorktree) -> Int {
        32 + 1 + worktree.name.utf8.count + worktree.path.path.utf8.count
            + estimatedTagByteCount(worktree.tags)
    }

    private static func estimatedSnapshotByteCount(_ watchedPath: WatchedPath) -> Int {
        16 + MemoryLayout<Date>.size + watchedPath.path.path.utf8.count
    }

    private static func estimatedTagByteCount(_ tags: [String]) -> Int {
        tags.reduce(0) { byteCount, tag in
            byteCount + MemoryLayout<Int>.size + tag.utf8.count
        }
    }

    private static func canonical(_ repository: Repo) -> CanonicalRepo {
        CanonicalRepo(
            id: repository.id,
            name: repository.name,
            repoPath: repository.repoPath,
            createdAt: repository.createdAt,
            tags: repository.tags
        )
    }

    private static func canonical(_ worktree: Worktree) -> CanonicalWorktree {
        CanonicalWorktree(
            id: worktree.id,
            repoId: worktree.repoId,
            name: worktree.name,
            path: worktree.path,
            isMainWorktree: worktree.isMainWorktree,
            tags: worktree.tags
        )
    }
}
