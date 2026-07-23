import Foundation
import GRDB

func replaceRepositoryTopologyRows(
    _ database: Database,
    topology: WorkspaceCoreRepository.RepositoryTopologyRecord
) throws {
    let incomingWorktrees = topology.repos.flatMap(\.worktrees)
    try preflightIncomingWorktreeIdentity(database, worktrees: incomingWorktrees)
    try replaceUnavailableRepoRows(database, repoIds: [])
    try replaceWatchedPathRows(database, watchedPaths: topology.watchedPaths)
    try reconcileRepoRows(database, repos: topology.repos)
    try reconcileWorktreeRows(
        database,
        repoId: nil,
        worktrees: incomingWorktrees
    )
    try replaceRepoTagRows(database, repos: topology.repos)
    try replaceUnavailableRepoRows(database, repoIds: topology.unavailableRepoIds)
}

func replaceUnavailableRepoRows(
    _ database: Database,
    repoIds: Set<UUID>
) throws {
    try database.execute(sql: "DELETE FROM unavailable_repo")
    for repoId in repoIds.sorted(by: { $0.uuidString < $1.uuidString }) {
        try insertUnavailableRepo(database, repoId: repoId)
    }
}

func reconcileRepoWorktreeRows(
    _ database: Database,
    repoId: UUID,
    worktrees: [WorkspaceCoreRepository.WorktreeRecord]
) throws {
    try preflightIncomingWorktreeStableKeys(
        database,
        repoId: repoId,
        worktrees: worktrees
    )
    try reconcileWorktreeRows(
        database,
        repoId: repoId,
        worktrees: worktrees
    )
}

private func replaceWatchedPathRows(
    _ database: Database,
    watchedPaths: [WorkspaceCoreRepository.WatchedPathRecord]
) throws {
    try database.execute(sql: "DELETE FROM watched_path")
    for watchedPath in watchedPaths {
        try insertWatchedPath(database, watchedPath: watchedPath)
    }
}

private func reconcileRepoRows(
    _ database: Database,
    repos: [WorkspaceCoreRepository.RepoRecord]
) throws {
    let retainedRepoIds = Set(repos.map(\.id))
    try stageRetainedRepoStableKeys(database, repoIds: retainedRepoIds)
    try deleteReposNotIn(database, retainedRepoIds: retainedRepoIds)
    for repo in repos {
        try upsertRepo(database, repo: repo)
    }
}

private func preflightIncomingWorktreeIdentity(
    _ database: Database,
    worktrees: [WorkspaceCoreRepository.WorktreeRecord]
) throws {
    for worktree in worktrees {
        guard let currentIdentity = try fetchWorktreeIdentity(database, worktreeId: worktree.id) else {
            continue
        }
        guard currentIdentity.repoId == worktree.repoId else {
            throw WorkspaceCoreRepositoryError.worktreeRepoMismatch(
                worktreeId: worktree.id,
                expectedRepoId: worktree.repoId,
                actualRepoId: currentIdentity.repoId
            )
        }
    }
}

private func preflightIncomingWorktreeStableKeys(
    _ database: Database,
    repoId: UUID,
    worktrees: [WorkspaceCoreRepository.WorktreeRecord]
) throws {
    let stableKeys = Set(worktrees.map(\.stableKey))
    guard !stableKeys.isEmpty else { return }
    guard
        let collidingStableKey = try String.fetchOne(
            database,
            sql: """
                SELECT stable_key
                FROM worktree
                WHERE repo_id != ?
                AND stable_key IN (\(placeholders(count: stableKeys.count)))
                ORDER BY stable_key ASC
                LIMIT 1
                """,
            arguments: StatementArguments([repoId.uuidString] + stableKeys.sorted())
        )
    else {
        return
    }
    throw WorkspaceCoreRepositoryError.duplicateWorktreeStableKey(collidingStableKey)
}

private func reconcileWorktreeRows(
    _ database: Database,
    repoId: UUID?,
    worktrees: [WorkspaceCoreRepository.WorktreeRecord]
) throws {
    let retainedWorktreeIds = Set(worktrees.map(\.id))
    try stageRetainedWorktreeStableKeys(
        database,
        repoId: repoId,
        worktreeIds: retainedWorktreeIds
    )
    try deleteWorktreesNotIn(
        database,
        repoId: repoId,
        retainedWorktreeIds: retainedWorktreeIds
    )
    for worktree in worktrees {
        try upsertWorktree(database, worktree: worktree)
    }
}

private func replaceRepoTagRows(
    _ database: Database,
    repos: [WorkspaceCoreRepository.RepoRecord]
) throws {
    try database.execute(sql: "DELETE FROM repo_tag")
    for repo in repos {
        for tag in repo.tags.sorted() {
            try insertRepoTag(database, repoId: repo.id, tag: tag)
        }
    }
}

private func stageRetainedRepoStableKeys(
    _ database: Database,
    repoIds: Set<UUID>
) throws {
    for repoId in repoIds {
        try database.execute(
            sql: """
                UPDATE repo
                SET stable_key = ?
                WHERE id = ?
                """,
            arguments: [
                temporaryStableKey(prefix: "repo", id: repoId),
                repoId.uuidString,
            ]
        )
    }
}

private func stageRetainedWorktreeStableKeys(
    _ database: Database,
    repoId: UUID?,
    worktreeIds: Set<UUID>
) throws {
    for worktreeId in worktreeIds {
        var arguments = [
            temporaryStableKey(prefix: "worktree", id: worktreeId)
        ]
        if let repoId {
            arguments.append(repoId.uuidString)
        }
        arguments.append(worktreeId.uuidString)
        try database.execute(
            sql: """
                UPDATE worktree
                SET stable_key = ?
                WHERE \(requiredRepoPredicate(repoId))
                id = ?
                """,
            arguments: StatementArguments(arguments)
        )
    }
}

private func deleteReposNotIn(
    _ database: Database,
    retainedRepoIds: Set<UUID>
) throws {
    if retainedRepoIds.isEmpty {
        try database.execute(sql: "DELETE FROM repo")
        return
    }

    try database.execute(
        sql: """
            DELETE FROM repo
            WHERE id NOT IN (\(placeholders(count: retainedRepoIds.count)))
            """,
        arguments: StatementArguments(retainedRepoIds.sortedByUUIDString().map(\.uuidString))
    )
}

private func deleteWorktreesNotIn(
    _ database: Database,
    repoId: UUID?,
    retainedWorktreeIds: Set<UUID>
) throws {
    if retainedWorktreeIds.isEmpty {
        try database.execute(
            sql: """
                DELETE FROM worktree
                \(optionalWhereRepoPredicate(repoId))
                """,
            arguments: repoScopedArguments(repoId: repoId)
        )
        return
    }

    try database.execute(
        sql: """
            DELETE FROM worktree
            WHERE \(requiredRepoPredicate(repoId))
            id NOT IN (\(placeholders(count: retainedWorktreeIds.count)))
            """,
        arguments: repoScopedArguments(
            repoId: repoId,
            extraIds: retainedWorktreeIds.sortedByUUIDString()
        )
    )
}

private func upsertRepo(
    _ database: Database,
    repo: WorkspaceCoreRepository.RepoRecord
) throws {
    if try repoIdExists(database, repoId: repo.id) {
        try updateRepo(database, repo: repo)
    } else {
        try insertRepo(database, repo: repo)
    }
}

private func upsertWorktree(
    _ database: Database,
    worktree: WorkspaceCoreRepository.WorktreeRecord
) throws {
    if let currentIdentity = try fetchWorktreeIdentity(database, worktreeId: worktree.id) {
        guard currentIdentity.repoId == worktree.repoId else {
            throw WorkspaceCoreRepositoryError.worktreeRepoMismatch(
                worktreeId: worktree.id,
                expectedRepoId: worktree.repoId,
                actualRepoId: currentIdentity.repoId
            )
        }
        try updateWorktree(database, worktree: worktree)
    } else {
        try insertWorktree(database, worktree: worktree)
    }
}

private func insertWatchedPath(
    _ database: Database,
    watchedPath: WorkspaceCoreRepository.WatchedPathRecord
) throws {
    try database.execute(
        sql: """
            INSERT INTO watched_path(id, path, stable_key, added_at)
            VALUES (?, ?, ?, ?)
            """,
        arguments: [
            watchedPath.id.uuidString,
            watchedPath.path.path,
            watchedPath.stableKey,
            watchedPath.addedAt.timeIntervalSince1970,
        ]
    )
}

private func insertRepo(
    _ database: Database,
    repo: WorkspaceCoreRepository.RepoRecord
) throws {
    try database.execute(
        sql: """
            INSERT INTO repo(id, name, repo_path, stable_key, created_at, is_favorite, note)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: StatementArguments(repoArguments(repo: repo))
    )
}

private func updateRepo(
    _ database: Database,
    repo: WorkspaceCoreRepository.RepoRecord
) throws {
    try database.execute(
        sql: """
            UPDATE repo
            SET name = ?, repo_path = ?, stable_key = ?, created_at = ?, is_favorite = ?, note = ?
            WHERE id = ?
            """,
        arguments: [
            repo.name,
            repo.repoPath.path,
            repo.stableKey,
            repo.createdAt.timeIntervalSince1970,
            repo.isFavorite ? 1 : 0,
            repo.note,
            repo.id.uuidString,
        ]
    )
}

private func insertWorktree(
    _ database: Database,
    worktree: WorkspaceCoreRepository.WorktreeRecord
) throws {
    try database.execute(
        sql: """
            INSERT INTO worktree(id, repo_id, name, path, stable_key, is_main_worktree, note)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: StatementArguments(worktreeArguments(worktree: worktree))
    )
}

private func updateWorktree(
    _ database: Database,
    worktree: WorkspaceCoreRepository.WorktreeRecord
) throws {
    try database.execute(
        sql: """
            UPDATE worktree
            SET name = ?, path = ?, stable_key = ?, is_main_worktree = ?, note = ?
            WHERE repo_id = ?
            AND id = ?
            """,
        arguments: [
            worktree.name,
            worktree.path.path,
            worktree.stableKey,
            worktree.isMainWorktree ? 1 : 0,
            worktree.note,
            worktree.repoId.uuidString,
            worktree.id.uuidString,
        ]
    )
}

private func insertUnavailableRepo(
    _ database: Database,
    repoId: UUID
) throws {
    try database.execute(
        sql: """
            INSERT INTO unavailable_repo(repo_id)
            VALUES (?)
            """,
        arguments: [repoId.uuidString]
    )
}

private func insertRepoTag(
    _ database: Database,
    repoId: UUID,
    tag: String
) throws {
    try database.execute(
        sql: """
            INSERT INTO repo_tag(repo_id, tag)
            VALUES (?, ?)
            """,
        arguments: [repoId.uuidString, tag]
    )
}

private func repoIdExists(_ database: Database, repoId: UUID) throws -> Bool {
    let matchingCount = try Int.fetchOne(
        database,
        sql: """
            SELECT count(*)
            FROM repo
            WHERE id = ?
            """,
        arguments: [repoId.uuidString]
    )
    return matchingCount == 1
}

private func fetchWorktreeIdentity(
    _ database: Database,
    worktreeId: UUID
) throws -> WorktreeIdentity? {
    guard
        let row = try Row.fetchOne(
            database,
            sql: """
                SELECT repo_id
                FROM worktree
                WHERE id = ?
                """,
            arguments: [worktreeId.uuidString]
        )
    else {
        return nil
    }
    let repoIdString: String = row["repo_id"]
    guard let repoId = UUID(uuidString: repoIdString) else {
        throw WorkspaceCoreRepositoryError.malformedRepoId(repoIdString)
    }
    return .init(repoId: repoId)
}

private func repoArguments(
    repo: WorkspaceCoreRepository.RepoRecord
) -> [any DatabaseValueConvertible] {
    [
        repo.id.uuidString,
        repo.name,
        repo.repoPath.path,
        repo.stableKey,
        repo.createdAt.timeIntervalSince1970,
        repo.isFavorite ? 1 : 0,
        repo.note,
    ]
}

private func worktreeArguments(
    worktree: WorkspaceCoreRepository.WorktreeRecord
) -> [any DatabaseValueConvertible] {
    [
        worktree.id.uuidString,
        worktree.repoId.uuidString,
        worktree.name,
        worktree.path.path,
        worktree.stableKey,
        worktree.isMainWorktree ? 1 : 0,
        worktree.note,
    ]
}

private func repoScopedArguments(
    repoId: UUID?,
    extraIds: [UUID] = []
) -> StatementArguments {
    var values: [String] = []
    if let repoId {
        values.append(repoId.uuidString)
    }
    values.append(contentsOf: extraIds.map(\.uuidString))
    return StatementArguments(values)
}

private func optionalWhereRepoPredicate(_ repoId: UUID?) -> String {
    repoId == nil ? "" : "WHERE repo_id = ?"
}

private func requiredRepoPredicate(_ repoId: UUID?) -> String {
    repoId == nil ? "" : "repo_id = ? AND "
}

private func temporaryStableKey(prefix: String, id: UUID) -> String {
    "__agentstudio_reconcile_\(prefix)_\(id.uuidString)__"
}

private func placeholders(count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ", ")
}

private struct WorktreeIdentity {
    let repoId: UUID
}

extension Set where Element == UUID {
    fileprivate func sortedByUUIDString() -> [UUID] {
        sorted { $0.uuidString < $1.uuidString }
    }
}
