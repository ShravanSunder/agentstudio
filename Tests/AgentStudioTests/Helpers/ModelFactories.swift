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

// MARK: - Pane Factory

func makePane(
    id: UUID = UUIDv7.generate(),
    source: TerminalSource = .floating(workingDirectory: nil, title: nil),
    title: String = "Terminal",
    agent: AgentType? = nil,
    provider: SessionProvider = .zmx,
    lifetime: SessionLifetime = .persistent,
    residency: SessionResidency = .active
) -> Pane {
    Pane(
        id: id,
        content: .terminal(TerminalState(provider: provider, lifetime: lifetime)),
        metadata: PaneMetadata(source: source, title: title, agentType: agent),
        residency: residency
    )
}

// MARK: - Tab Factory (multi-pane)

func makeTab(paneIds: [UUID], activePaneId: UUID? = nil) -> Tab {
    guard let first = paneIds.first else {
        fatalError("Need at least one pane ID")
    }
    if paneIds.count == 1 {
        return Tab(paneId: first)
    }
    // Build layout by inserting subsequent panes
    var layout = Layout(paneId: first)
    for i in 1..<paneIds.count {
        layout = layout.inserting(
            paneId: paneIds[i],
            at: paneIds[i - 1],
            direction: .horizontal,
            position: .after
        )
    }
    let arrangement = PaneArrangement(
        name: "Default",
        isDefault: true,
        layout: layout,
        visiblePaneIds: Set(paneIds)
    )
    return Tab(
        panes: paneIds,
        arrangements: [arrangement],
        activeArrangementId: arrangement.id,
        activePaneId: activePaneId ?? first
    )
}

// MARK: - SurfaceMetadata Factory

func makeSurfaceMetadata(
    workingDirectory: String? = "/tmp/test-dir",
    command: String? = nil,
    title: String = "Terminal",
    worktreeId: UUID? = nil,
    repoId: UUID? = nil,
    paneId: UUID? = nil
) -> SurfaceMetadata {
    SurfaceMetadata(
        workingDirectory: workingDirectory.map { URL(fileURLWithPath: $0) },
        command: command,
        title: title,
        worktreeId: worktreeId,
        repoId: repoId,
        paneId: paneId
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
