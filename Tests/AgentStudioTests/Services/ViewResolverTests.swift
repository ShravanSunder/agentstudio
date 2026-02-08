import XCTest
@testable import AgentStudio

@MainActor
final class ViewResolverTests: XCTestCase {

    // MARK: - Worktree View

    func test_resolveWorktreeView_matchingSessions() {
        let worktreeId = UUID()
        let repoId = UUID()
        let sessions = [
            TerminalSession(source: .worktree(worktreeId: worktreeId, repoId: repoId), title: "S1"),
            TerminalSession(source: .worktree(worktreeId: worktreeId, repoId: repoId), title: "S2"),
            TerminalSession(source: .floating(workingDirectory: nil, title: nil), title: "Other"),
        ]
        let worktree = Worktree(name: "feature", path: URL(fileURLWithPath: "/tmp/ft"), branch: "feature")

        let view = ViewResolver.resolveWorktreeView(
            worktreeId: worktreeId,
            sessions: sessions,
            worktree: worktree
        )

        XCTAssertEqual(view.kind, .worktree(worktreeId: worktreeId))
        XCTAssertEqual(view.name, "feature")
        XCTAssertEqual(view.tabs.count, 2)
        XCTAssertEqual(view.tabs[0].sessionIds, [sessions[0].id])
        XCTAssertEqual(view.tabs[1].sessionIds, [sessions[1].id])
    }

    func test_resolveWorktreeView_noMatchingSessions() {
        let worktreeId = UUID()
        let sessions = [
            TerminalSession(source: .floating(workingDirectory: nil, title: nil), title: "Other"),
        ]

        let view = ViewResolver.resolveWorktreeView(
            worktreeId: worktreeId,
            sessions: sessions,
            worktree: nil
        )

        XCTAssertEqual(view.kind, .worktree(worktreeId: worktreeId))
        XCTAssertEqual(view.name, "Worktree")
        XCTAssertTrue(view.tabs.isEmpty)
    }

    // MARK: - Dynamic View: byRepo

    func test_resolveDynamic_byRepo() {
        let repoId = UUID()
        let wt1 = Worktree(name: "main", path: URL(fileURLWithPath: "/tmp/main"), branch: "main")
        let wt2 = Worktree(name: "dev", path: URL(fileURLWithPath: "/tmp/dev"), branch: "dev")
        let repo = Repo(
            id: repoId,
            name: "my-repo",
            repoPath: URL(fileURLWithPath: "/tmp/repo"),
            worktrees: [wt1, wt2]
        )
        let sessions = [
            TerminalSession(source: .worktree(worktreeId: wt1.id, repoId: repoId), title: "S1"),
            TerminalSession(source: .worktree(worktreeId: wt2.id, repoId: repoId), title: "S2"),
            TerminalSession(source: .worktree(worktreeId: UUID(), repoId: UUID()), title: "Other"),
        ]

        let view = ViewResolver.resolveDynamic(
            rule: .byRepo(repoId: repoId),
            sessions: sessions,
            repos: [repo]
        )

        XCTAssertEqual(view.kind, .dynamic(rule: .byRepo(repoId: repoId)))
        XCTAssertEqual(view.name, "my-repo")
        XCTAssertEqual(view.tabs.count, 2)
    }

    func test_resolveDynamic_byRepo_unknownRepo() {
        let sessions = [
            TerminalSession(source: .floating(workingDirectory: nil, title: nil), title: "S1"),
        ]

        let view = ViewResolver.resolveDynamic(
            rule: .byRepo(repoId: UUID()),
            sessions: sessions,
            repos: []
        )

        XCTAssertEqual(view.name, "Repo")
        XCTAssertTrue(view.tabs.isEmpty)
    }

    // MARK: - Dynamic View: byAgent

    func test_resolveDynamic_byAgent() {
        let sessions = [
            TerminalSession(source: .floating(workingDirectory: nil, title: nil), title: "Claude1", agent: .claude),
            TerminalSession(source: .floating(workingDirectory: nil, title: nil), title: "Claude2", agent: .claude),
            TerminalSession(source: .floating(workingDirectory: nil, title: nil), title: "Codex1", agent: .codex),
            TerminalSession(source: .floating(workingDirectory: nil, title: nil), title: "NoAgent"),
        ]

        let view = ViewResolver.resolveDynamic(
            rule: .byAgent(.claude),
            sessions: sessions,
            repos: []
        )

        XCTAssertEqual(view.kind, .dynamic(rule: .byAgent(.claude)))
        XCTAssertEqual(view.tabs.count, 2)
        XCTAssertEqual(view.tabs[0].sessionIds, [sessions[0].id])
        XCTAssertEqual(view.tabs[1].sessionIds, [sessions[1].id])
    }

    func test_resolveDynamic_byAgent_noMatches() {
        let sessions = [
            TerminalSession(source: .floating(workingDirectory: nil, title: nil), title: "NoAgent"),
        ]

        let view = ViewResolver.resolveDynamic(
            rule: .byAgent(.claude),
            sessions: sessions,
            repos: []
        )

        XCTAssertTrue(view.tabs.isEmpty)
    }

    // MARK: - Dynamic View: custom

    func test_resolveDynamic_custom_returnsAllSessions() {
        let sessions = [
            TerminalSession(source: .floating(workingDirectory: nil, title: nil), title: "S1"),
            TerminalSession(source: .floating(workingDirectory: nil, title: nil), title: "S2"),
        ]

        let view = ViewResolver.resolveDynamic(
            rule: .custom(name: "all"),
            sessions: sessions,
            repos: []
        )

        XCTAssertEqual(view.kind, .dynamic(rule: .custom(name: "all")))
        XCTAssertEqual(view.name, "all")
        XCTAssertEqual(view.tabs.count, 2)
    }

    // MARK: - Active Tab

    func test_resolvedView_activeTabId_isFirst() {
        let worktreeId = UUID()
        let sessions = [
            TerminalSession(source: .worktree(worktreeId: worktreeId, repoId: UUID()), title: "S1"),
            TerminalSession(source: .worktree(worktreeId: worktreeId, repoId: UUID()), title: "S2"),
        ]

        let view = ViewResolver.resolveWorktreeView(
            worktreeId: worktreeId,
            sessions: sessions,
            worktree: nil
        )

        XCTAssertEqual(view.activeTabId, view.tabs.first?.id)
    }

    func test_resolvedView_emptyTabs_noActiveTab() {
        let view = ViewResolver.resolveWorktreeView(
            worktreeId: UUID(),
            sessions: [],
            worktree: nil
        )

        XCTAssertNil(view.activeTabId)
    }
}
