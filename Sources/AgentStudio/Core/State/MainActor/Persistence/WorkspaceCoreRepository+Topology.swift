import Foundation
import GRDB

extension WorkspaceCoreRepository {
    struct RepositoryTopologyRecord: Equatable, Sendable {
        var watchedPaths: [WatchedPathRecord]
        var repos: [RepoRecord]
        var unavailableRepoIds: Set<UUID>
    }

    struct WatchedPathRecord: Equatable, Sendable {
        let id: UUID
        var path: URL
        let stableKey: String
        var addedAt: Date

        init(
            id: UUID,
            path: URL,
            stableKey: String? = nil,
            addedAt: Date
        ) {
            self.id = id
            self.path = path.standardizedFileURL
            self.stableKey = stableKey ?? StableKey.fromPath(path.standardizedFileURL)
            self.addedAt = addedAt
        }
    }

    struct RepoRecord: Equatable, Sendable {
        let id: UUID
        var name: String
        var repoPath: URL
        let stableKey: String
        var createdAt: Date
        var worktrees: [WorktreeRecord]
        var tags: [String]

        init(
            id: UUID,
            name: String,
            repoPath: URL,
            stableKey: String? = nil,
            createdAt: Date,
            worktrees: [WorktreeRecord],
            tags: [String] = []
        ) {
            self.id = id
            self.name = name
            self.repoPath = repoPath.standardizedFileURL
            self.stableKey = stableKey ?? StableKey.fromPath(repoPath.standardizedFileURL)
            self.createdAt = createdAt
            self.worktrees = worktrees
            self.tags = tags
        }
    }

    struct WorktreeRecord: Equatable, Sendable {
        let id: UUID
        let repoId: UUID
        var name: String
        var path: URL
        let stableKey: String
        var isMainWorktree: Bool
        var tags: [String]

        init(
            id: UUID,
            repoId: UUID,
            name: String,
            path: URL,
            stableKey: String? = nil,
            isMainWorktree: Bool,
            tags: [String] = []
        ) {
            self.id = id
            self.repoId = repoId
            self.name = name
            self.path = path.standardizedFileURL
            self.stableKey = stableKey ?? StableKey.fromPath(path.standardizedFileURL)
            self.isMainWorktree = isMainWorktree
            self.tags = tags
        }
    }

    func replaceRepositoryTopology(
        workspaceId: UUID,
        topology: RepositoryTopologyRecord
    ) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try validateTopology(topology, for: workspaceId)
            try replaceRepositoryTopologyRows(database, workspaceId: workspaceId, topology: topology)
        }
    }

    func fetchRepositoryTopology(workspaceId: UUID) throws -> RepositoryTopologyRecord {
        try databaseWriter.read { database in
            try requireWorkspaceExists(database, id: workspaceId)
            let watchedPaths = try fetchWatchedPathRecords(database, workspaceId: workspaceId)
            let repos = try fetchRepoRecords(database, workspaceId: workspaceId)
            let unavailableRepoIds = try fetchUnavailableRepoIds(database, workspaceId: workspaceId)
            return .init(
                watchedPaths: watchedPaths,
                repos: repos,
                unavailableRepoIds: unavailableRepoIds
            )
        }
    }

    func setUnavailableRepoIds(_ repoIds: Set<UUID>, workspaceId: UUID) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            for repoId in repoIds {
                try requireRepoExists(database, repoId: repoId, workspaceId: workspaceId)
            }
            try replaceUnavailableRepoRows(database, workspaceId: workspaceId, repoIds: repoIds)
        }
    }

    func reconcileRepoWorktrees(
        workspaceId: UUID,
        repoId: UUID,
        worktrees: [WorktreeRecord]
    ) throws {
        try databaseWriter.write { database in
            try requireWorkspaceExists(database, id: workspaceId)
            try requireRepoExists(database, repoId: repoId, workspaceId: workspaceId)
            try validateWorktrees(worktrees, repoId: repoId)
            try reconcileRepoWorktreeRows(
                database,
                workspaceId: workspaceId,
                repoId: repoId,
                worktrees: worktrees
            )
        }
    }
}

func validateTopology(
    _ topology: WorkspaceCoreRepository.RepositoryTopologyRecord,
    for _: UUID
) throws {
    let repoIds = Set(topology.repos.map(\.id))
    try validateUniqueStableKeys(
        topology.watchedPaths.map(\.stableKey),
        duplicateError: WorkspaceCoreRepositoryError.duplicateWatchedPathStableKey
    )
    try validateUniqueIds(topology.repos.map(\.id), duplicateError: WorkspaceCoreRepositoryError.duplicateRepoId)
    try validateUniqueStableKeys(
        topology.repos.map(\.stableKey),
        duplicateError: WorkspaceCoreRepositoryError.duplicateRepoStableKey
    )
    try validateUniqueIds(
        topology.repos.flatMap(\.worktrees).map(\.id),
        duplicateError: WorkspaceCoreRepositoryError.duplicateWorktreeId
    )
    try validateUniqueStableKeys(
        topology.repos.flatMap(\.worktrees).map(\.stableKey),
        duplicateError: WorkspaceCoreRepositoryError.duplicateWorktreeStableKey
    )
    for repoId in topology.unavailableRepoIds where !repoIds.contains(repoId) {
        throw WorkspaceCoreRepositoryError.unavailableRepoNotInTopology(repoId)
    }
    for repo in topology.repos {
        try validateRepositoryTags(repo.tags)
        try validateWorktrees(repo.worktrees, repoId: repo.id)
    }
}

private func validateWorktrees(
    _ worktrees: [WorkspaceCoreRepository.WorktreeRecord],
    repoId: UUID
) throws {
    for worktree in worktrees where worktree.repoId != repoId {
        throw WorkspaceCoreRepositoryError.worktreeRepoMismatch(
            worktreeId: worktree.id,
            expectedRepoId: repoId,
            actualRepoId: worktree.repoId
        )
    }
    for worktree in worktrees {
        try validateRepositoryTags(worktree.tags)
    }
    try validateUniqueIds(worktrees.map(\.id), duplicateError: WorkspaceCoreRepositoryError.duplicateWorktreeId)
    try validateUniqueStableKeys(
        worktrees.map(\.stableKey),
        duplicateError: WorkspaceCoreRepositoryError.duplicateWorktreeStableKey
    )
}

func validateRepositoryTags(_ tags: [String]) throws {
    var seenTags = Set<String>()
    for tag in tags {
        guard isValidRepositoryTag(tag) else {
            throw WorkspaceCoreRepositoryError.invalidRepositoryTag(tag)
        }
        guard seenTags.insert(tag).inserted else {
            throw WorkspaceCoreRepositoryError.duplicateRepositoryTag(tag)
        }
    }
}

private func isValidRepositoryTag(_ tag: String) -> Bool {
    RepositoryTagValidation.isValid(tag)
}

private func validateUniqueIds(
    _ ids: [UUID],
    duplicateError: (UUID) -> WorkspaceCoreRepositoryError
) throws {
    var seenIds = Set<UUID>()
    for id in ids where !seenIds.insert(id).inserted {
        throw duplicateError(id)
    }
}

private func validateUniqueStableKeys(
    _ stableKeys: [String],
    duplicateError: (String) -> WorkspaceCoreRepositoryError
) throws {
    var seenStableKeys = Set<String>()
    for stableKey in stableKeys where !seenStableKeys.insert(stableKey).inserted {
        throw duplicateError(stableKey)
    }
}

private func fetchWatchedPathRecords(
    _ database: Database,
    workspaceId: UUID
) throws -> [WorkspaceCoreRepository.WatchedPathRecord] {
    let rows = try Row.fetchAll(
        database,
        sql: """
            SELECT id, path, stable_key, added_at
            FROM watched_path
            WHERE workspace_id = ?
            ORDER BY added_at ASC, id ASC
            """,
        arguments: [workspaceId.uuidString]
    )
    return try rows.map(decodeWatchedPathRecord)
}

private func fetchRepoRecords(
    _ database: Database,
    workspaceId: UUID
) throws -> [WorkspaceCoreRepository.RepoRecord] {
    let rows = try Row.fetchAll(
        database,
        sql: """
            SELECT id, name, repo_path, stable_key, created_at
            FROM repo
            WHERE workspace_id = ?
            ORDER BY created_at ASC, id ASC
            """,
        arguments: [workspaceId.uuidString]
    )
    return try rows.map { row in
        let repo = try decodeRepoRecord(row, worktrees: [])
        let worktrees = try fetchWorktreeRecords(database, workspaceId: workspaceId, repoId: repo.id)
        let tags = try fetchRepoTags(database, workspaceId: workspaceId, repoId: repo.id)
        return .init(
            id: repo.id,
            name: repo.name,
            repoPath: repo.repoPath,
            stableKey: repo.stableKey,
            createdAt: repo.createdAt,
            worktrees: worktrees,
            tags: tags
        )
    }
}

private func fetchWorktreeRecords(
    _ database: Database,
    workspaceId: UUID,
    repoId: UUID
) throws -> [WorkspaceCoreRepository.WorktreeRecord] {
    let rows = try Row.fetchAll(
        database,
        sql: """
            SELECT id, repo_id, name, path, stable_key, is_main_worktree
            FROM worktree
            WHERE workspace_id = ?
            AND repo_id = ?
            ORDER BY is_main_worktree DESC, name ASC, id ASC
            """,
        arguments: [
            workspaceId.uuidString,
            repoId.uuidString,
        ]
    )
    return try rows.map { row in
        let worktree = try decodeWorktreeRecord(row)
        let tags = try fetchWorktreeTags(database, workspaceId: workspaceId, worktreeId: worktree.id)
        return .init(
            id: worktree.id,
            repoId: worktree.repoId,
            name: worktree.name,
            path: worktree.path,
            stableKey: worktree.stableKey,
            isMainWorktree: worktree.isMainWorktree,
            tags: tags
        )
    }
}

private func fetchRepoTags(_ database: Database, workspaceId: UUID, repoId: UUID) throws -> [String] {
    try String.fetchAll(
        database,
        sql: """
            SELECT tag
            FROM repo_tag
            WHERE workspace_id = ?
            AND repo_id = ?
            ORDER BY tag ASC
            """,
        arguments: [workspaceId.uuidString, repoId.uuidString]
    )
}

private func fetchWorktreeTags(_ database: Database, workspaceId: UUID, worktreeId: UUID) throws -> [String] {
    try String.fetchAll(
        database,
        sql: """
            SELECT tag
            FROM worktree_tag
            WHERE workspace_id = ?
            AND worktree_id = ?
            ORDER BY tag ASC
            """,
        arguments: [workspaceId.uuidString, worktreeId.uuidString]
    )
}

private func fetchUnavailableRepoIds(_ database: Database, workspaceId: UUID) throws -> Set<UUID> {
    let idStrings = try String.fetchAll(
        database,
        sql: """
            SELECT repo_id
            FROM unavailable_repo
            WHERE workspace_id = ?
            ORDER BY repo_id ASC
            """,
        arguments: [workspaceId.uuidString]
    )
    return try Set(
        idStrings.map { idString in
            guard let id = UUID(uuidString: idString) else {
                throw WorkspaceCoreRepositoryError.malformedRepoId(idString)
            }
            return id
        })
}

private func decodeWatchedPathRecord(_ row: Row) throws -> WorkspaceCoreRepository.WatchedPathRecord {
    let idString: String = row["id"]
    guard let id = UUID(uuidString: idString) else {
        throw WorkspaceCoreRepositoryError.malformedWatchedPathId(idString)
    }
    let path: String = row["path"]
    let stableKey: String = row["stable_key"]
    let addedAt: Double = row["added_at"]
    return .init(
        id: id,
        path: URL(fileURLWithPath: path),
        stableKey: stableKey,
        addedAt: Date(timeIntervalSince1970: addedAt)
    )
}

private func decodeRepoRecord(
    _ row: Row,
    worktrees: [WorkspaceCoreRepository.WorktreeRecord]
) throws -> WorkspaceCoreRepository.RepoRecord {
    let idString: String = row["id"]
    guard let id = UUID(uuidString: idString) else {
        throw WorkspaceCoreRepositoryError.malformedRepoId(idString)
    }
    let name: String = row["name"]
    let repoPath: String = row["repo_path"]
    let stableKey: String = row["stable_key"]
    let createdAt: Double = row["created_at"]
    return .init(
        id: id,
        name: name,
        repoPath: URL(fileURLWithPath: repoPath),
        stableKey: stableKey,
        createdAt: Date(timeIntervalSince1970: createdAt),
        worktrees: worktrees
    )
}

private func decodeWorktreeRecord(_ row: Row) throws -> WorkspaceCoreRepository.WorktreeRecord {
    let idString: String = row["id"]
    guard let id = UUID(uuidString: idString) else {
        throw WorkspaceCoreRepositoryError.malformedWorktreeId(idString)
    }
    let repoIdString: String = row["repo_id"]
    guard let repoId = UUID(uuidString: repoIdString) else {
        throw WorkspaceCoreRepositoryError.malformedRepoId(repoIdString)
    }
    let name: String = row["name"]
    let path: String = row["path"]
    let stableKey: String = row["stable_key"]
    let isMainWorktree: Int = row["is_main_worktree"]
    return .init(
        id: id,
        repoId: repoId,
        name: name,
        path: URL(fileURLWithPath: path),
        stableKey: stableKey,
        isMainWorktree: isMainWorktree != 0
    )
}

func requireRepoExists(
    _ database: Database,
    repoId: UUID,
    workspaceId: UUID
) throws {
    guard try repoExists(database, repoId: repoId, workspaceId: workspaceId) else {
        throw WorkspaceCoreRepositoryError.repoNotFoundInWorkspace(repoId, workspaceId)
    }
}

private func repoExists(_ database: Database, repoId: UUID, workspaceId: UUID) throws -> Bool {
    let matchingCount = try Int.fetchOne(
        database,
        sql: """
            SELECT count(*)
            FROM repo
            WHERE id = ?
            AND workspace_id = ?
            """,
        arguments: [
            repoId.uuidString,
            workspaceId.uuidString,
        ]
    )
    return matchingCount == 1
}
