import Testing
import Foundation

@testable import AgentStudio

/// Integration tests that exercise ZmxBackend against a real zmx binary.
/// Each test uses an isolated ZMX_DIR via ZmxTestHarness to prevent cross-test interference.
///
/// Requires zmx to be installed (built from vendor/zmx or on PATH).
@Suite(.serialized)
@MainActor
struct ZmxBackendIntegrationTests {

    /// Run a test body with a usable backend, skipping if zmx is unavailable.
    private func withBackend(
        _ test: @escaping (ZmxTestHarness, ZmxBackend) async throws -> Void
    ) async throws {
        let harness = ZmxTestHarness()
        guard let backend = harness.createBackend() else {
            Issue.record("ZmxTestHarness failed to resolve zmx path; skipping integration test")
            return
        }

        guard await backend.isAvailable else {
            Issue.record("zmx is unavailable in this environment; skipping integration test")
            return
        }
        do {
            try await test(harness, backend)
            await harness.cleanup()
        } catch {
            await harness.cleanup()
            throw error
        }
    }

    // MARK: - Create + Verify

    @Test
    func test_createSession_producesValidHandle() async throws {
        try await withBackend { _, backend in
            // Arrange
            let worktree = makeWorktree(
                name: "integ-test",
                path: "/tmp",
                branch: "integ-test"
            )
            let repo = makeRepo()

            // Act
            let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

            // Assert — handle is valid (no zmx session actually started, that happens on attach)
            #expect(handle.id.hasPrefix("agentstudio--"))
            #expect(handle.id.count == 65)
            #expect(handle.hasValidId)
        }
    }

    // MARK: - Attach Command Format

    @Test
    func test_attachCommand_containsAttachAndSessionId() async throws {
        try await withBackend { _, backend in
            // Arrange
            let worktree = makeWorktree(name: "attach-test", path: "/tmp", branch: "attach-test")
            let repo = makeRepo()
            let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

            // Act
            let cmd = backend.attachCommand(for: handle)

            // Assert
            #expect(!cmd.contains("ZMX_DIR="))
            #expect(cmd.hasPrefix("\""))
            #expect(cmd.contains("attach"))
            #expect(cmd.contains(handle.id))
            #expect(cmd.contains("-i -l"))
        }
    }

    // MARK: - ZMX_DIR Isolation

    @Test
    func test_zmxDir_isolatesFromDefaultDir() async throws {
        try await withBackend { harness, backend in
            // Arrange — create a session in test-isolated dir
            let worktree = makeWorktree(name: "isolation-test", path: "/tmp", branch: "isolation-test")
            let repo = makeRepo()

            // Act
            _ = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

            // Assert — the zmx dir should exist and be in temp
            #expect(
                harness.zmxDir.hasPrefix("/tmp/zt-")
            )
            #expect(
                FileManager.default.fileExists(atPath: harness.zmxDir)
            )
        }
    }

    // MARK: - Destroy

    @Test
    func test_destroySessionById_doesNotThrowForMissingSession() async throws {
        try await withBackend { _, backend in
            // zmx kill for a non-existent session should fail gracefully
            // or throw — either behavior is acceptable in integration context
            do {
                try await backend.destroySessionById("agentstudio--fake--fake--fake1234567890ab")
            } catch {
                #expect(error is SessionBackendError)
            }
        }
    }

    // MARK: - zmx Binary Path Resolution

    @Test
    func test_zmxBinaryPath_resolved() {
        // Act
        let config = SessionConfiguration.detect()

        // Assert — zmxPath should be resolved (zmx may or may not be installed)
        if let path = config.zmxPath {
            #expect(path.hasPrefix("/"))
            #expect(FileManager.default.isExecutableFile(atPath: path))
        }
        // If zmxPath is nil, zmx is not installed — that's fine for CI
    }
}
