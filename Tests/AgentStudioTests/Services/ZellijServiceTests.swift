import Testing
import Foundation
@testable import AgentStudio

@Suite("ZellijService Unit Tests")
struct ZellijServiceTests {

    // MARK: - Session Creation

    @Test("Create session succeeds")
    @MainActor
    func createSessionSuccess() async throws {
        let executor = MockProcessExecutor()
        executor.mockSuccess("list-sessions", stdout: "")
        executor.mockSuccess("attach", stdout: "")

        let service = ZellijService(executor: executor)
        let project = Project(
            name: "test-project",
            repoPath: URL(fileURLWithPath: "/tmp/test"),
            worktrees: []
        )

        let session = try await service.createSession(for: project)

        #expect(session.displayName == "test-project")
        #expect(session.id.hasPrefix("agentstudio--"))
        #expect(session.isRunning == true)
        #expect(executor.wasExecuted("attach"))
    }

    @Test("Create session reuses existing")
    @MainActor
    func createSessionReusesExisting() async throws {
        let executor = MockProcessExecutor()
        let projectId = UUID(uuidString: "12345678-0000-0000-0000-000000000000")!
        let sessionId = ZellijSession.sessionId(for: projectId)

        // Session already exists in Zellij
        executor.mockSuccess("list-sessions", stdout: "\(sessionId) [Created 1h ago]")

        let service = ZellijService(executor: executor)
        let project = Project(
            id: projectId,
            name: "existing",
            repoPath: URL(fileURLWithPath: "/tmp/existing"),
            worktrees: []
        )

        let session = try await service.createSession(for: project)

        #expect(session.id == sessionId)
        // Should not call attach --create-background
        #expect(!executor.wasExecuted("--create-background"))
    }

    @Test("Create session fails on error")
    @MainActor
    func createSessionFailure() async throws {
        let executor = MockProcessExecutor()
        executor.mockSuccess("list-sessions", stdout: "")
        executor.mockFailure("attach", stderr: "Permission denied")

        let service = ZellijService(executor: executor)
        let project = Project(
            name: "bad-project",
            repoPath: URL(fileURLWithPath: "/tmp/bad"),
            worktrees: []
        )

        await #expect(throws: ZellijError.self) {
            try await service.createSession(for: project)
        }
    }

    // MARK: - Session Discovery

    @Test("Discover sessions filters to agentstudio prefix")
    @MainActor
    func discoverSessionsFilters() async {
        let executor = MockProcessExecutor()
        executor.mockSuccess("list-sessions", stdout: """
            agentstudio--abc12345 [Created 1h ago]
            my-personal-session [Created 2h ago]
            agentstudio--def67890 [Created 30m ago]
            random-session [Created 1d ago]
            """)

        let service = ZellijService(executor: executor)
        let sessions = await service.discoverSessions()

        #expect(sessions.count == 2)
        #expect(sessions.contains("agentstudio--abc12345"))
        #expect(sessions.contains("agentstudio--def67890"))
        #expect(!sessions.contains("my-personal-session"))
    }

    @Test("Session exists returns true when found")
    @MainActor
    func sessionExistsTrue() async {
        let executor = MockProcessExecutor()
        executor.mockSuccess("list-sessions", stdout: "agentstudio--test [Created 1h ago]")

        let service = ZellijService(executor: executor)
        let exists = await service.sessionExists("agentstudio--test")

        #expect(exists == true)
    }

    @Test("Session exists returns false when not found")
    @MainActor
    func sessionExistsFalse() async {
        let executor = MockProcessExecutor()
        executor.mockSuccess("list-sessions", stdout: "other-session [Created 1h ago]")

        let service = ZellijService(executor: executor)
        let exists = await service.sessionExists("agentstudio--notfound")

        #expect(exists == false)
    }

    // MARK: - Tab Management

    @Test("Create tab succeeds")
    @MainActor
    func createTabSuccess() async throws {
        let executor = MockProcessExecutor()
        executor.mockSuccess("action new-tab", stdout: "")
        executor.mockSuccess("query-tab-names", stdout: "Tab #1\nfeature-branch")

        let service = ZellijService(executor: executor)
        let session = ZellijSession(
            id: "agentstudio--test",
            projectId: UUID(),
            displayName: "test"
        )
        let worktree = Worktree(
            name: "worktree",
            path: URL(fileURLWithPath: "/tmp/worktree"),
            branch: "feature-branch"
        )

        let tab = try await service.createTab(in: session, for: worktree)

        #expect(tab.name == "feature-branch")
        #expect(tab.worktreeId == worktree.id)
        #expect(executor.wasExecuted("new-tab"))
    }

    @Test("Get tab names parses output correctly")
    @MainActor
    func getTabNames() async throws {
        let executor = MockProcessExecutor()
        executor.mockSuccess("query-tab-names", stdout: "main\nfeature-a\nfeature-b\n")

        let service = ZellijService(executor: executor)
        let session = ZellijSession(
            id: "agentstudio--test",
            projectId: UUID(),
            displayName: "test"
        )

        let names = try await service.getTabNames(for: session)

        #expect(names.count == 3)
        #expect(names == ["main", "feature-a", "feature-b"])
    }

    // MARK: - Attach Command

    @Test("Attach command has correct format")
    @MainActor
    func attachCommandFormat() async throws {
        let executor = MockProcessExecutor()
        let service = ZellijService(executor: executor)
        let session = ZellijSession(
            id: "agentstudio--myproject",
            projectId: UUID(),
            displayName: "test"
        )

        let command = service.attachCommand(for: session)

        #expect(command.contains("zellij"))
        #expect(command.contains("--config"))
        #expect(command.contains("invisible.kdl"))
        #expect(command.contains("attach"))
        #expect(command.contains("agentstudio--myproject"))
    }

    // MARK: - Zellij Installation Check

    @Test("isZellijInstalled returns true when found")
    @MainActor
    func zellijInstalledTrue() async {
        let executor = MockProcessExecutor()
        executor.mockSuccess("which zellij", stdout: "/opt/homebrew/bin/zellij")

        let service = ZellijService(executor: executor)
        let installed = await service.isZellijInstalled()

        #expect(installed == true)
    }

    @Test("isZellijInstalled returns false when not found")
    @MainActor
    func zellijInstalledFalse() async {
        let executor = MockProcessExecutor()
        executor.mockFailure("which", stderr: "zellij not found")

        let service = ZellijService(executor: executor)
        let installed = await service.isZellijInstalled()

        #expect(installed == false)
    }

    // MARK: - Timeout Tests

    @Test("Create session throws timeout error when Zellij hangs")
    @MainActor
    func createSessionTimeout() async throws {
        let executor = MockProcessExecutor()
        executor.mockSuccess("list-sessions", stdout: "")
        // Simulate attach command that takes longer than timeout (10s)
        executor.mockTimeout("attach", delay: 15.0)

        let service = ZellijService(executor: executor)
        let project = Project(
            name: "timeout-project",
            repoPath: URL(fileURLWithPath: "/tmp/timeout"),
            worktrees: []
        )

        // Should throw ZellijError.timeout
        await #expect(throws: ZellijError.self) {
            try await service.createSession(for: project)
        }
    }

    @Test("Session exists returns false on timeout (safe fallback)")
    @MainActor
    func sessionExistsTimeoutFallback() async {
        let executor = MockProcessExecutor()
        // Simulate list-sessions that takes longer than timeout (5s)
        executor.mockTimeout("list-sessions", delay: 10.0)

        let service = ZellijService(executor: executor)
        let exists = await service.sessionExists("agentstudio--test")

        // Should return false as safe fallback when timed out
        #expect(exists == false)
    }

    @Test("Discover sessions returns empty on timeout (safe fallback)")
    @MainActor
    func discoverSessionsTimeoutFallback() async {
        let executor = MockProcessExecutor()
        // Simulate list-sessions that takes longer than timeout (5s)
        executor.mockTimeout("list-sessions", delay: 10.0)

        let service = ZellijService(executor: executor)
        let sessions = await service.discoverSessions()

        // Should return empty array as safe fallback
        #expect(sessions.isEmpty)
    }

    @Test("Create tab throws timeout error when Zellij hangs")
    @MainActor
    func createTabTimeout() async throws {
        let executor = MockProcessExecutor()
        executor.mockSuccess("list-sessions", stdout: "")
        executor.mockSuccess("attach", stdout: "")
        // Simulate new-tab command that takes longer than timeout (10s)
        executor.mockTimeout("action new-tab", delay: 15.0)

        let service = ZellijService(executor: executor)
        let project = Project(
            name: "tab-timeout-project",
            repoPath: URL(fileURLWithPath: "/tmp/tab-timeout"),
            worktrees: []
        )

        let session = try await service.createSession(for: project)
        let worktree = Worktree(
            name: "worktree",
            path: URL(fileURLWithPath: "/tmp/worktree"),
            branch: "feature-branch"
        )

        // Should throw ZellijError.timeout
        await #expect(throws: ZellijError.self) {
            try await service.createTab(in: session, for: worktree)
        }
    }

    @Test("isZellijInstalled returns false on timeout")
    @MainActor
    func zellijInstalledTimeout() async {
        let executor = MockProcessExecutor()
        // Simulate which command that times out
        executor.mockTimeout("which zellij", delay: 10.0)

        let service = ZellijService(executor: executor)
        let installed = await service.isZellijInstalled()

        // Should return false when timed out
        #expect(installed == false)
    }
}

@Suite("ZellijService Integration Tests")
struct ZellijServiceIntegrationTests {

    @Test("Full session workflow")
    @MainActor
    func fullWorkflow() async throws {
        let executor = MockProcessExecutor()

        // Mock all workflow steps
        executor.mockSuccess("list-sessions", stdout: "")
        executor.mockSuccess("attach", stdout: "")
        executor.mockSuccess("action new-tab", stdout: "")
        executor.mockSuccess("query-tab-names", stdout: "main\nfeature")
        executor.mockSuccess("kill-session", stdout: "")

        let service = ZellijService(executor: executor)

        // 1. Create project and session
        let project = Project(
            name: "workflow-test",
            repoPath: URL(fileURLWithPath: "/tmp/workflow"),
            worktrees: [
                Worktree(name: "workflow", path: URL(fileURLWithPath: "/tmp/workflow"), branch: "main"),
                Worktree(name: "workflow-feature", path: URL(fileURLWithPath: "/tmp/workflow-feature"), branch: "feature")
            ]
        )

        let session = try await service.createSession(for: project)
        #expect(session.isRunning)
        #expect(service.sessions.count == 1)

        // 2. Add tabs
        for worktree in project.worktrees {
            _ = try await service.createTab(in: session, for: worktree)
        }

        #expect(service.sessions.first?.tabs.count == 2)

        // 3. Create checkpoint
        let checkpoint = SessionCheckpoint(sessions: service.sessions)
        #expect(checkpoint.sessions.count == 1)

        // 4. Destroy session
        try await service.destroySession(session)
        #expect(service.sessions.isEmpty)
    }
}
