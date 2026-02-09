import Foundation
@testable import AgentStudio

// MARK: - Worktree Factory

func makeWorktree(
    id: UUID = UUID(),
    name: String = "feature-branch",
    path: String = "/tmp/test-repo/feature-branch",
    branch: String = "feature-branch",
    agent: AgentType? = nil,
    status: WorktreeStatus = .idle
) -> Worktree {
    Worktree(
        id: id,
        name: name,
        path: URL(fileURLWithPath: path),
        branch: branch,
        agent: agent,
        status: status
    )
}

// MARK: - Repo Factory

func makeRepo(
    id: UUID = UUID(),
    name: String = "test-repo",
    repoPath: String = "/tmp/test-repo",
    worktrees: [Worktree] = [],
    createdAt: Date = Date(timeIntervalSince1970: 1_000_000),
    updatedAt: Date = Date(timeIntervalSince1970: 1_000_000)
) -> Repo {
    Repo(
        id: id,
        name: name,
        repoPath: URL(fileURLWithPath: repoPath),
        worktrees: worktrees,
        createdAt: createdAt,
        updatedAt: updatedAt
    )
}

// MARK: - SurfaceMetadata Factory

func makeSurfaceMetadata(
    workingDirectory: String? = "/tmp/test-dir",
    command: String? = nil,
    title: String = "Terminal",
    worktreeId: UUID? = nil,
    repoId: UUID? = nil,
    sessionId: UUID? = nil
) -> SurfaceMetadata {
    SurfaceMetadata(
        workingDirectory: workingDirectory.map { URL(fileURLWithPath: $0) },
        command: command,
        title: title,
        worktreeId: worktreeId,
        repoId: repoId,
        sessionId: sessionId
    )
}

// MARK: - PaneSessionHandle Factory

func makePaneSessionHandle(
    id: String = "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--a1b2c3d4e5f6a7b8",
    paneId: UUID = UUID(),
    projectId: UUID = UUID(),
    worktreeId: UUID = UUID(),
    repoPath: String = "/tmp/test-repo",
    worktreePath: String = "/tmp/test-repo/feature-branch",
    displayName: String = "test",
    workingDirectory: String = "/tmp/test-repo/feature-branch"
) -> PaneSessionHandle {
    PaneSessionHandle(
        id: id,
        paneId: paneId,
        projectId: projectId,
        worktreeId: worktreeId,
        repoPath: URL(fileURLWithPath: repoPath),
        worktreePath: URL(fileURLWithPath: worktreePath),
        displayName: displayName,
        workingDirectory: URL(fileURLWithPath: workingDirectory)
    )
}

