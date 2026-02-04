import Testing
import Foundation
@testable import AgentStudio

@Suite("ZellijSession Model Tests")
struct ZellijSessionTests {

    @Test("Session ID generation is deterministic")
    func sessionIdDeterministic() {
        let uuid = UUID(uuidString: "12345678-90ab-cdef-1234-567890abcdef")!

        let id1 = ZellijSession.sessionId(for: uuid)
        let id2 = ZellijSession.sessionId(for: uuid)

        #expect(id1 == id2)
        #expect(id1 == "agentstudio--12345678")
    }

    @Test("Session ID uses lowercase")
    func sessionIdLowercase() {
        let uuid = UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000000")!
        let id = ZellijSession.sessionId(for: uuid)

        #expect(id == "agentstudio--abcdef12")
    }

    @Test("Session ID has correct prefix")
    func sessionIdPrefix() {
        let uuid = UUID()
        let id = ZellijSession.sessionId(for: uuid)

        #expect(id.hasPrefix("agentstudio--"))
        #expect(id.count == "agentstudio--".count + 8)
    }

    @Test("Session encodes and decodes correctly")
    func sessionCodable() throws {
        let session = ZellijSession(
            id: "agentstudio--test1234",
            projectId: UUID(),
            displayName: "Test Project",
            tabs: [
                ZellijTab(
                    id: 1,
                    name: "main",
                    worktreeId: UUID(),
                    workingDirectory: URL(fileURLWithPath: "/tmp/test")
                )
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ZellijSession.self, from: data)

        #expect(decoded.id == session.id)
        #expect(decoded.displayName == session.displayName)
        #expect(decoded.tabs.count == 1)
        #expect(decoded.tabs.first?.name == "main")
    }

    @Test("Session initializes with correct defaults")
    func sessionDefaults() {
        let session = ZellijSession(
            id: "test",
            projectId: UUID(),
            displayName: "Test"
        )

        #expect(session.isRunning == true)
        #expect(session.tabs.isEmpty)
    }
}

@Suite("ZellijTab Model Tests")
struct ZellijTabTests {

    @Test("Tab encodes and decodes correctly")
    func tabCodable() throws {
        let tab = ZellijTab(
            id: 1,
            name: "feature-branch",
            worktreeId: UUID(),
            workingDirectory: URL(fileURLWithPath: "/tmp/worktree"),
            restoreCommand: "claude"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(tab)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ZellijTab.self, from: data)

        #expect(decoded.id == tab.id)
        #expect(decoded.name == "feature-branch")
        #expect(decoded.restoreCommand == "claude")
    }

    @Test("Tab restoreCommand is optional")
    func tabOptionalRestoreCommand() {
        let tab = ZellijTab(
            id: 1,
            name: "main",
            worktreeId: UUID(),
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        #expect(tab.restoreCommand == nil)
    }
}

@Suite("SessionCheckpoint Model Tests")
struct SessionCheckpointTests {

    @Test("Checkpoint version is set correctly")
    func checkpointVersion() {
        let checkpoint = SessionCheckpoint(sessions: [])
        #expect(checkpoint.version == 1)
    }

    @Test("Checkpoint timestamp is recent")
    func checkpointTimestamp() {
        let before = Date()
        let checkpoint = SessionCheckpoint(sessions: [])
        let after = Date()

        #expect(checkpoint.timestamp >= before)
        #expect(checkpoint.timestamp <= after)
    }

    @Test("Checkpoint converts sessions correctly")
    func checkpointConversion() {
        let session = ZellijSession(
            id: "agentstudio--test",
            projectId: UUID(),
            displayName: "Test",
            tabs: [
                ZellijTab(id: 1, name: "main", worktreeId: UUID(), workingDirectory: URL(fileURLWithPath: "/tmp"))
            ]
        )

        let checkpoint = SessionCheckpoint(sessions: [session])

        #expect(checkpoint.sessions.count == 1)
        #expect(checkpoint.sessions.first?.id == "agentstudio--test")
        #expect(checkpoint.sessions.first?.tabs.count == 1)
    }

    @Test("Checkpoint encodes and decodes correctly")
    func checkpointCodable() throws {
        let session = ZellijSession(
            id: "agentstudio--test",
            projectId: UUID(),
            displayName: "Test"
        )
        let checkpoint = SessionCheckpoint(sessions: [session])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(checkpoint)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionCheckpoint.self, from: data)

        #expect(decoded.version == checkpoint.version)
        #expect(decoded.sessions.count == 1)
    }
}
