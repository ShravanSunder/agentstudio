import XCTest

@testable import AgentStudio

/// Integration tests that exercise ZmxBackend against a real zmx binary.
/// Each test uses an isolated ZMX_DIR via ZmxTestHarness to prevent cross-test interference.
///
/// Requires zmx to be installed (built from vendor/zmx or on PATH).
final class ZmxBackendIntegrationTests: XCTestCase {
    private var harness: ZmxTestHarness!
    private var backend: ZmxBackend!

    override func setUp() async throws {
        try await super.setUp()
        harness = ZmxTestHarness()

        // Skip if zmx is not available
        guard let zmxBackend = harness.createBackend() else {
            throw XCTSkip("zmx not available on this system")
        }
        backend = zmxBackend

        guard await backend.isAvailable else {
            throw XCTSkip("zmx binary not executable")
        }
    }

    override func tearDown() async throws {
        await harness.cleanup()
        try await super.tearDown()
    }

    // MARK: - Create + Verify

    func test_createSession_producesValidHandle() async throws {
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
        XCTAssertTrue(handle.id.hasPrefix("agentstudio--"))
        XCTAssertEqual(handle.id.count, 65)
        XCTAssertTrue(handle.hasValidId)
    }

    // MARK: - Attach Command Format

    func test_attachCommand_containsZmxDirAndAttach() async throws {
        // Arrange
        let worktree = makeWorktree(name: "attach-test", path: "/tmp", branch: "attach-test")
        let repo = makeRepo()
        let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

        // Act
        let cmd = backend.attachCommand(for: handle)

        // Assert
        XCTAssertTrue(cmd.hasPrefix("/usr/bin/env ZMX_DIR="), "Command must start with /usr/bin/env ZMX_DIR=")
        XCTAssertTrue(cmd.contains("attach"), "Command must contain 'attach' subcommand")
        XCTAssertTrue(cmd.contains(handle.id), "Command must contain the session ID")
        XCTAssertTrue(cmd.contains("-i -l"), "Command must contain shell login flags")
    }

    // MARK: - ZMX_DIR Isolation

    func test_zmxDir_isolatesFromDefaultDir() async throws {
        // Arrange — create a session in test-isolated dir
        let worktree = makeWorktree(name: "isolation-test", path: "/tmp", branch: "isolation-test")
        let repo = makeRepo()

        // Act
        _ = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

        // Assert — the zmx dir should exist and be in temp
        XCTAssertTrue(
            harness.zmxDir.hasPrefix("/tmp/zt-"),
            "zmxDir should be a temp directory, not the default ~/.agentstudio/zmx"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: harness.zmxDir),
            "zmxDir should have been created by createPaneSession"
        )
    }

    // MARK: - Destroy

    func test_destroySessionById_doesNotThrowForMissingSession() async throws {
        // zmx kill for a non-existent session should fail gracefully
        // or throw — either behavior is acceptable in integration context
        do {
            try await backend.destroySessionById("agentstudio--fake--fake--fake1234567890ab")
            // If it succeeds (e.g. zmx kill returns 0 for missing), that's fine
        } catch {
            // Expected — zmx kill for a non-existent session returns non-zero
            XCTAssertTrue(error is SessionBackendError)
        }
    }

    // MARK: - zmx Binary Path Resolution

    func test_zmxBinaryPath_resolved() {
        // Act
        let config = SessionConfiguration.detect()

        // Assert — zmxPath should be resolved (zmx may or may not be installed)
        if let path = config.zmxPath {
            XCTAssertTrue(
                path.hasPrefix("/"),
                "zmxPath should be an absolute path, got: \(path)"
            )
            XCTAssertTrue(
                FileManager.default.isExecutableFile(atPath: path),
                "zmxPath should point to an executable, got: \(path)"
            )
        }
        // If zmxPath is nil, zmx is not installed — that's fine for CI
    }
}
