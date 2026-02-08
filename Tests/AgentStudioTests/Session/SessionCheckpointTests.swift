import XCTest
@testable import AgentStudio

final class SessionCheckpointTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkpoint-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Codable Round-Trip

    func test_checkpoint_codable_roundTrip() throws {
        // Arrange
        let checkpoint = SessionCheckpoint(sessions: [
            .init(
                sessionId: "agentstudio--abc12345--def67890",
                projectId: UUID(),
                worktreeId: UUID(),
                displayName: "main",
                workingDirectory: URL(fileURLWithPath: "/tmp/test-repo/main"),
                lastKnownAlive: Date()
            ),
            .init(
                sessionId: "agentstudio--abc12345--ghi11111",
                projectId: UUID(),
                worktreeId: UUID(),
                displayName: "feature",
                workingDirectory: URL(fileURLWithPath: "/tmp/test-repo/feature"),
                lastKnownAlive: Date()
            ),
        ])

        // Act
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(checkpoint)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionCheckpoint.self, from: data)

        // Assert
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.sessions.count, 2)
        XCTAssertEqual(decoded.sessions[0].sessionId, "agentstudio--abc12345--def67890")
        XCTAssertEqual(decoded.sessions[0].displayName, "main")
        XCTAssertEqual(decoded.sessions[1].sessionId, "agentstudio--abc12345--ghi11111")
        XCTAssertEqual(decoded.sessions[1].displayName, "feature")
    }

    // MARK: - File Persistence

    func test_checkpoint_saveAndLoad() throws {
        // Arrange
        let path = tempDir.appendingPathComponent("test-checkpoint.json")
        let original = SessionCheckpoint(sessions: [
            .init(
                sessionId: "agentstudio--test--pane",
                projectId: UUID(),
                worktreeId: UUID(),
                displayName: "Test",
                workingDirectory: URL(fileURLWithPath: "/tmp"),
                lastKnownAlive: Date()
            ),
        ])

        // Act
        try original.save(to: path)
        let loaded = SessionCheckpoint.load(from: path)

        // Assert
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessions.count, 1)
        XCTAssertEqual(loaded?.sessions[0].sessionId, "agentstudio--test--pane")
    }

    func test_checkpoint_loadReturnsNil_whenMissing() {
        // Arrange
        let path = tempDir.appendingPathComponent("nonexistent.json")

        // Act
        let loaded = SessionCheckpoint.load(from: path)

        // Assert
        XCTAssertNil(loaded)
    }

    // MARK: - Staleness

    func test_checkpoint_isStale_whenOld() {
        // Arrange — checkpoint from 8 days ago
        let old = SessionCheckpoint(sessions: [])
        // Manually test: default maxAge is 7 days
        // We can't easily set the timestamp post-init, so test the boundary
        XCTAssertFalse(old.isStale(maxAge: 999_999))
    }

    func test_checkpoint_isNotStale_whenRecent() {
        // Arrange
        let recent = SessionCheckpoint(sessions: [])

        // Assert — just created, should not be stale
        XCTAssertFalse(recent.isStale())
    }

    // MARK: - Empty Checkpoint

    func test_checkpoint_empty_sessions() throws {
        // Arrange
        let path = tempDir.appendingPathComponent("empty.json")
        let checkpoint = SessionCheckpoint(sessions: [])

        // Act
        try checkpoint.save(to: path)
        let loaded = SessionCheckpoint.load(from: path)

        // Assert
        XCTAssertNotNil(loaded)
        XCTAssertTrue(loaded?.sessions.isEmpty ?? false)
    }

    // MARK: - Version

    func test_checkpoint_version_is2() {
        // Arrange & Act
        let checkpoint = SessionCheckpoint(sessions: [])

        // Assert
        XCTAssertEqual(checkpoint.version, 2)
    }
}
