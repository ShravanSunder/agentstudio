import Foundation
import GRDB

func replaceRepositoryTopologyRows(
    _ database: Database,
    workspaceId: UUID,
    topology: WorkspaceCoreRepository.RepositoryTopologyRecord
) throws {
    let incomingWorktrees = topology.repos.flatMap(\.worktrees)
    try preflightIncomingWorktreeOwnership(
        database,
        workspaceId: workspaceId,
        worktrees: incomingWorktrees
    )
    try replaceUnavailableRepoRows(database, workspaceId: workspaceId, repoIds: [])
    try replaceWatchedPathRows(database, workspaceId: workspaceId, watchedPaths: topology.watchedPaths)
    try reconcileRepoRows(database, workspaceId: workspaceId, repos: topology.repos)
    try reconcileWorktreeRows(
        database,
        workspaceId: workspaceId,
        repoId: nil,
        worktrees: incomingWorktrees
    )
    try replaceUnavailableRepoRows(
        database,
        workspaceId: workspaceId,
        repoIds: topology.unavailableRepoIds
    )
}

func replaceUnavailableRepoRows(
    _ database: Database,
    workspaceId: UUID,
    repoIds: Set<UUID>
) throws {
    try database.execute(
        sql: """
            DELETE FROM unavailable_repo
            WHERE workspace_id = ?
            """,
        arguments: [workspaceId.uuidString]
    )
    for repoId in repoIds.sorted(by: { $0.uuidString < $1.uuidString }) {
        try insertUnavailableRepo(database, workspaceId: workspaceId, repoId: repoId)
    }
}

func reconcileRepoWorktreeRows(
    _ database: Database,
    workspaceId: UUID,
    repoId: UUID,
    worktrees: [WorkspaceCoreRepository.WorktreeRecord]
) throws {
    try reconcileWorktreeRows(
        database,
        workspaceId: workspaceId,
        repoId: repoId,
        worktrees: worktrees
    )
}

private func replaceWatchedPathRows(
    _ database: Database,
    workspaceId: UUID,
    watchedPaths: [WorkspaceCoreRepository.WatchedPathRecord]
) throws {
    try database.execute(
        sql: """
            DELETE FROM watched_path
            WHERE workspace_id = ?
            """,
        arguments: [workspaceId.uuidString]
    )
    for watchedPath in watchedPaths {
        try insertWatchedPath(database, workspaceId: workspaceId, watchedPath: watchedPath)
    }
}

private func reconcileRepoRows(
    _ database: Database,
    workspaceId: UUID,
    repos: [WorkspaceCoreRepository.RepoRecord]
) throws {
    let retainedRepoIds = Set(repos.map(\.id))
    try stageRetainedRepoStableKeys(database, workspaceId: workspaceId, repoIds: retainedRepoIds)
    try deleteReposNotIn(database, workspaceId: workspaceId, retainedRepoIds: retainedRepoIds)
    for repo in repos {
        try upsertRepo(database, workspaceId: workspaceId, repo: repo)
    }
}

private func preflightIncomingWorktreeOwnership(
    _ database: Database,
    workspaceId: UUID,
    worktrees: [WorkspaceCoreRepository.WorktreeRecord]
) throws {
    for worktree in worktrees {
        guard let currentIdentity = try fetchWorktreeIdentity(database, worktreeId: worktree.id) else {
            continue
        }
        guard currentIdentity.workspaceId == workspaceId else {
            throw WorkspaceCoreRepositoryError.repoNotFoundInWorkspace(worktree.repoId, workspaceId)
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

private func reconcileWorktreeRows(
    _ database: Database,
    workspaceId: UUID,
    repoId: UUID?,
    worktrees: [WorkspaceCoreRepository.WorktreeRecord]
) throws {
    let retainedWorktreeIds = Set(worktrees.map(\.id))
    try stageRetainedWorktreeStableKeys(
        database,
        workspaceId: workspaceId,
        repoId: repoId,
        worktreeIds: retainedWorktreeIds
    )
    try deleteWorktreesNotIn(
        database,
        workspaceId: workspaceId,
        repoId: repoId,
        retainedWorktreeIds: retainedWorktreeIds
    )
    for worktree in worktrees {
        try upsertWorktree(database, workspaceId: workspaceId, worktree: worktree)
    }
}

private func stageRetainedRepoStableKeys(
    _ database: Database,
    workspaceId: UUID,
    repoIds: Set<UUID>
) throws {
    for repoId in repoIds {
        try database.execute(
            sql: """
                UPDATE repo
                SET stable_key = ?
                WHERE workspace_id = ?
                AND id = ?
                """,
            arguments: [
                temporaryStableKey(prefix: "repo", id: repoId),
                workspaceId.uuidString,
                repoId.uuidString,
            ]
        )
    }
}

private func stageRetainedWorktreeStableKeys(
    _ database: Database,
    workspaceId: UUID,
    repoId: UUID?,
    worktreeIds: Set<UUID>
) throws {
    for worktreeId in worktreeIds {
        let repoFilter = repoId == nil ? "" : "AND repo_id = ?"
        var arguments = [
            temporaryStableKey(prefix: "worktree", id: worktreeId),
            workspaceId.uuidString,
        ]
        if let repoId {
            arguments.append(repoId.uuidString)
        }
        arguments.append(worktreeId.uuidString)
        try database.execute(
            sql: """
                UPDATE worktree
                SET stable_key = ?
                WHERE workspace_id = ?
                \(repoFilter)
                AND id = ?
                """,
            arguments: StatementArguments(arguments)
        )
    }
}

private func deleteReposNotIn(
    _ database: Database,
    workspaceId: UUID,
    retainedRepoIds: Set<UUID>
) throws {
    if retainedRepoIds.isEmpty {
        try database.execute(
            sql: """
                DELETE FROM repo
                WHERE workspace_id = ?
                """,
            arguments: [workspaceId.uuidString]
        )
        return
    }

    try database.execute(
        sql: """
            DELETE FROM repo
            WHERE workspace_id = ?
            AND id NOT IN (\(placeholders(count: retainedRepoIds.count)))
            """,
        arguments: StatementArguments(
            [workspaceId.uuidString] + retainedRepoIds.sortedByUUIDString().map(\.uuidString)
        )
    )
}

private func deleteWorktreesNotIn(
    _ database: Database,
    workspaceId: UUID,
    repoId: UUID?,
    retainedWorktreeIds: Set<UUID>
) throws {
    if retainedWorktreeIds.isEmpty {
        try database.execute(
            sql: """
                DELETE FROM worktree
                WHERE workspace_id = ?
                \(repoPredicate(repoId))
                """,
            arguments: repoScopedArguments(workspaceId: workspaceId, repoId: repoId)
        )
        return
    }

    try database.execute(
        sql: """
            DELETE FROM worktree
            WHERE workspace_id = ?
            \(repoPredicate(repoId))
            AND id NOT IN (\(placeholders(count: retainedWorktreeIds.count)))
            """,
        arguments: repoScopedArguments(
            workspaceId: workspaceId,
            repoId: repoId,
            extraIds: retainedWorktreeIds.sortedByUUIDString()
        )
    )
}

private func upsertRepo(
    _ database: Database,
    workspaceId: UUID,
    repo: WorkspaceCoreRepository.RepoRecord
) throws {
    if try repoIdExists(database, repoId: repo.id) {
        try requireRepoExists(database, repoId: repo.id, workspaceId: workspaceId)
        try updateRepo(database, workspaceId: workspaceId, repo: repo)
    } else {
        try insertRepo(database, workspaceId: workspaceId, repo: repo)
    }
}

private func upsertWorktree(
    _ database: Database,
    workspaceId: UUID,
    worktree: WorkspaceCoreRepository.WorktreeRecord
) throws {
    if let currentIdentity = try fetchWorktreeIdentity(database, worktreeId: worktree.id) {
        guard currentIdentity.workspaceId == workspaceId else {
            throw WorkspaceCoreRepositoryError.repoNotFoundInWorkspace(worktree.repoId, workspaceId)
        }
        guard currentIdentity.repoId == worktree.repoId else {
            throw WorkspaceCoreRepositoryError.worktreeRepoMismatch(
                worktreeId: worktree.id,
                expectedRepoId: worktree.repoId,
                actualRepoId: currentIdentity.repoId
            )
        }
        try updateWorktree(database, workspaceId: workspaceId, worktree: worktree)
    } else {
        try insertWorktree(database, workspaceId: workspaceId, worktree: worktree)
    }
}

private func insertWatchedPath(
    _ database: Database,
    workspaceId: UUID,
    watchedPath: WorkspaceCoreRepository.WatchedPathRecord
) throws {
    try database.execute(
        sql: """
            INSERT INTO watched_path(id, workspace_id, path, stable_key, added_at)
            VALUES (?, ?, ?, ?, ?)
            """,
        arguments: [
            watchedPath.id.uuidString,
            workspaceId.uuidString,
            watchedPath.path.path,
            watchedPath.stableKey,
            watchedPath.addedAt.timeIntervalSince1970,
        ]
    )
}

private func insertRepo(
    _ database: Database,
    workspaceId: UUID,
    repo: WorkspaceCoreRepository.RepoRecord
) throws {
    try database.execute(
        sql: """
            INSERT INTO repo(id, workspace_id, name, repo_path, stable_key, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
        arguments: StatementArguments(repoArguments(workspaceId: workspaceId, repo: repo))
    )
}

private func updateRepo(
    _ database: Database,
    workspaceId: UUID,
    repo: WorkspaceCoreRepository.RepoRecord
) throws {
    try database.execute(
        sql: """
            UPDATE repo
            SET name = ?, repo_path = ?, stable_key = ?, created_at = ?
            WHERE workspace_id = ?
            AND id = ?
            """,
        arguments: [
            repo.name,
            repo.repoPath.path,
            repo.stableKey,
            repo.createdAt.timeIntervalSince1970,
            workspaceId.uuidString,
            repo.id.uuidString,
        ]
    )
}

private func insertWorktree(
    _ database: Database,
    workspaceId: UUID,
    worktree: WorkspaceCoreRepository.WorktreeRecord
) throws {
    try database.execute(
        sql: """
            INSERT INTO worktree(id, workspace_id, repo_id, name, path, stable_key, is_main_worktree)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: StatementArguments(worktreeArguments(workspaceId: workspaceId, worktree: worktree))
    )
}

private func updateWorktree(
    _ database: Database,
    workspaceId: UUID,
    worktree: WorkspaceCoreRepository.WorktreeRecord
) throws {
    try database.execute(
        sql: """
            UPDATE worktree
            SET name = ?, path = ?, stable_key = ?, is_main_worktree = ?
            WHERE workspace_id = ?
            AND repo_id = ?
            AND id = ?
            """,
        arguments: [
            worktree.name,
            worktree.path.path,
            worktree.stableKey,
            worktree.isMainWorktree ? 1 : 0,
            workspaceId.uuidString,
            worktree.repoId.uuidString,
            worktree.id.uuidString,
        ]
    )
}

private func insertUnavailableRepo(
    _ database: Database,
    workspaceId: UUID,
    repoId: UUID
) throws {
    try database.execute(
        sql: """
            INSERT INTO unavailable_repo(workspace_id, repo_id)
            VALUES (?, ?)
            """,
        arguments: [
            workspaceId.uuidString,
            repoId.uuidString,
        ]
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
                SELECT workspace_id, repo_id
                FROM worktree
                WHERE id = ?
                """,
            arguments: [worktreeId.uuidString]
        )
    else {
        return nil
    }
    let workspaceIdString: String = row["workspace_id"]
    let repoIdString: String = row["repo_id"]
    guard let workspaceId = UUID(uuidString: workspaceIdString) else {
        throw WorkspaceCoreRepositoryError.malformedWorkspaceId(workspaceIdString)
    }
    guard let repoId = UUID(uuidString: repoIdString) else {
        throw WorkspaceCoreRepositoryError.malformedRepoId(repoIdString)
    }
    return .init(workspaceId: workspaceId, repoId: repoId)
}

private func repoArguments(
    workspaceId: UUID,
    repo: WorkspaceCoreRepository.RepoRecord
) -> [any DatabaseValueConvertible] {
    [
        repo.id.uuidString,
        workspaceId.uuidString,
        repo.name,
        repo.repoPath.path,
        repo.stableKey,
        repo.createdAt.timeIntervalSince1970,
    ]
}

private func worktreeArguments(
    workspaceId: UUID,
    worktree: WorkspaceCoreRepository.WorktreeRecord
) -> [any DatabaseValueConvertible] {
    [
        worktree.id.uuidString,
        workspaceId.uuidString,
        worktree.repoId.uuidString,
        worktree.name,
        worktree.path.path,
        worktree.stableKey,
        worktree.isMainWorktree ? 1 : 0,
    ]
}

private func repoScopedArguments(
    workspaceId: UUID,
    repoId: UUID?,
    extraIds: [UUID] = []
) -> StatementArguments {
    var values = [workspaceId.uuidString]
    if let repoId {
        values.append(repoId.uuidString)
    }
    values.append(contentsOf: extraIds.map(\.uuidString))
    return StatementArguments(values)
}

private func repoPredicate(_ repoId: UUID?) -> String {
    repoId == nil ? "" : "AND repo_id = ?"
}

private func temporaryStableKey(prefix: String, id: UUID) -> String {
    "__agentstudio_reconcile_\(prefix)_\(id.uuidString)__"
}

private func placeholders(count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ", ")
}

private struct WorktreeIdentity {
    let workspaceId: UUID
    let repoId: UUID
}

extension Set where Element == UUID {
    fileprivate func sortedByUUIDString() -> [UUID] {
        sorted { $0.uuidString < $1.uuidString }
    }
}
