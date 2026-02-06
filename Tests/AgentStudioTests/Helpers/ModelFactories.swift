import Foundation
@testable import AgentStudio

// MARK: - Worktree Factory

func makeWorktree(
    id: UUID = UUID(),
    name: String = "feature-branch",
    path: String = "/tmp/test-repo/feature-branch",
    branch: String = "feature-branch",
    agent: AgentType? = nil,
    status: WorktreeStatus = .idle,
    isOpen: Bool = false,
    lastOpened: Date? = nil
) -> Worktree {
    Worktree(
        id: id,
        name: name,
        path: URL(fileURLWithPath: path),
        branch: branch,
        agent: agent,
        status: status,
        isOpen: isOpen,
        lastOpened: lastOpened
    )
}

// MARK: - Project Factory

func makeProject(
    id: UUID = UUID(),
    name: String = "test-project",
    repoPath: String = "/tmp/test-repo",
    worktrees: [Worktree] = [],
    createdAt: Date = Date(timeIntervalSince1970: 1_000_000),
    updatedAt: Date = Date(timeIntervalSince1970: 1_000_000)
) -> Project {
    Project(
        id: id,
        name: name,
        repoPath: URL(fileURLWithPath: repoPath),
        worktrees: worktrees,
        createdAt: createdAt,
        updatedAt: updatedAt
    )
}

// MARK: - OpenTab Factory

func makeOpenTab(
    id: UUID = UUID(),
    worktreeId: UUID = UUID(),
    projectId: UUID = UUID(),
    order: Int = 0,
    splitTreeData: Data? = nil,
    activePaneId: UUID? = nil
) -> OpenTab {
    OpenTab(
        id: id,
        worktreeId: worktreeId,
        projectId: projectId,
        order: order,
        splitTreeData: splitTreeData,
        activePaneId: activePaneId
    )
}

// MARK: - SurfaceMetadata Factory

func makeSurfaceMetadata(
    workingDirectory: String? = "/tmp/test-dir",
    command: String? = nil,
    title: String = "Terminal",
    worktreeId: UUID? = nil,
    projectId: UUID? = nil
) -> SurfaceMetadata {
    SurfaceMetadata(
        workingDirectory: workingDirectory.map { URL(fileURLWithPath: $0) },
        command: command,
        title: title,
        worktreeId: worktreeId,
        projectId: projectId
    )
}
