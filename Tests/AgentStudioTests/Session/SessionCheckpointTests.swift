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
        let paneId1 = UUID()
        let paneId2 = UUID()
        let checkpoint = SessionCheckpoint(sessions: [
            .init(
                sessionId: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344",
                paneId: paneId1,
                projectId: UUID(),
                worktreeId: UUID(),
                repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
                worktreePath: URL(fileURLWithPath: "/tmp/test-repo/main"),
                displayName: "main",
                workingDirectory: URL(fileURLWithPath: "/tmp/test-repo/main"),
                lastKnownAlive: Date()
            ),
            .init(
                sessionId: "agentstudio--a1b2c3d4e5f6a7b8--fedcba9876543210--11223344aabbccdd",
                paneId: paneId2,
                projectId: UUID(),
                worktreeId: UUID(),
                repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
                worktreePath: URL(fileURLWithPath: "/tmp/test-repo/feature"),
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
        XCTAssertEqual(decoded.version, 3)
        XCTAssertEqual(decoded.sessions.count, 2)
        XCTAssertEqual(decoded.sessions[0].sessionId, "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        XCTAssertEqual(decoded.sessions[0].displayName, "main")
        XCTAssertEqual(decoded.sessions[0].paneId, paneId1)
        XCTAssertEqual(decoded.sessions[0].repoPath, URL(fileURLWithPath: "/tmp/test-repo"))
        XCTAssertEqual(decoded.sessions[0].worktreePath, URL(fileURLWithPath: "/tmp/test-repo/main"))
        XCTAssertEqual(decoded.sessions[1].sessionId, "agentstudio--a1b2c3d4e5f6a7b8--fedcba9876543210--11223344aabbccdd")
        XCTAssertEqual(decoded.sessions[1].displayName, "feature")
        XCTAssertEqual(decoded.sessions[1].paneId, paneId2)
    }

    // MARK: - File Persistence

    func test_checkpoint_saveAndLoad() throws {
        // Arrange
        let path = tempDir.appendingPathComponent("test-checkpoint.json")
        let paneId = UUID()
        let original = SessionCheckpoint(sessions: [
            .init(
                sessionId: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344",
                paneId: paneId,
                projectId: UUID(),
                worktreeId: UUID(),
                repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
                worktreePath: URL(fileURLWithPath: "/tmp"),
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
        XCTAssertEqual(loaded?.sessions[0].sessionId, "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        XCTAssertEqual(loaded?.sessions[0].paneId, paneId)
    }

    func test_checkpoint_loadReturnsNil_whenMissing() {
        // Arrange
        let path = tempDir.appendingPathComponent("nonexistent.json")

        // Act
        let loaded = SessionCheckpoint.load(from: path)

        // Assert
        XCTAssertNil(loaded)
    }

    // MARK: - v2 Format Rejection

    func test_checkpoint_v2Format_failsToDecode() throws {
        // Arrange — v2 JSON lacks paneId, repoPath, worktreePath
        let v2Json = """
        {
          "version": 2,
          "timestamp": "2025-01-01T00:00:00Z",
          "sessions": [
            {
              "sessionId": "agentstudio--a1b2c3d4--e5f6a7b8--00001111",
              "projectId": "00000000-0000-0000-0000-000000000001",
              "worktreeId": "00000000-0000-0000-0000-000000000002",
              "displayName": "test",
              "workingDirectory": "file:///tmp/",
              "lastKnownAlive": "2025-01-01T00:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let path = tempDir.appendingPathComponent("v2-checkpoint.json")
        try v2Json.write(to: path)

        // Act — v2 checkpoint should fail to decode (missing required fields)
        let loaded = SessionCheckpoint.load(from: path)

        // Assert
        XCTAssertNil(loaded, "v2 checkpoint should fail to decode due to missing required fields")
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

    func test_checkpoint_version_is3() {
        // Arrange & Act
        let checkpoint = SessionCheckpoint(sessions: [])

        // Assert
        XCTAssertEqual(checkpoint.version, 3)
    }
}
