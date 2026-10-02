import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioTerminal

@Suite("Foreground observation repository")
struct ForegroundObservationRepositoryTests {
    @Test("a look carries the latest binding even after a launch sweep")
    func sweptBindingStillOwnsObservation() async throws {
        let fixture = try ForegroundRepositoryFixture()
        try await fixture.seedBinding(status: "ended")
        let observation = try fixture.observation(sequence: 1)
        #expect(try await fixture.repository.admit(observation) == .admitted)
        #expect(try await fixture.repository.load(paneId: fixture.paneId) == observation)
        #expect(
            try await fixture.repository.eligiblePanes().map(\.bindingGenerationId) == [fixture.bindingGenerationId])
    }

    @Test("a stale result after a rebind is refused inside admission")
    func staleBindingResultIsRejected() async throws {
        let fixture = try ForegroundRepositoryFixture()
        try await fixture.seedBinding()
        let stale = try fixture.observation(sequence: 1)
        try await fixture.replaceBinding()
        #expect(try await fixture.repository.admit(stale) == .bindingChanged)
        #expect(try await fixture.repository.load(paneId: fixture.paneId) == nil)
    }

    @Test("snapshot sequence, not finish order or identity difference, owns currentness")
    func olderSnapshotCannotOverwriteNewerResult() async throws {
        let fixture = try ForegroundRepositoryFixture()
        try await fixture.seedBinding()
        let newer = try fixture.observation(sequence: 2, program: .shell)
        #expect(try await fixture.repository.admit(newer) == .admitted)
        let older = try fixture.observation(sequence: 1, identity: foregroundTestIdentity(leaderPid: 4300))
        #expect(try await fixture.repository.admit(older) == .olderLook)
        #expect(try await fixture.repository.admit(newer) == .olderLook)
        #expect(try await fixture.repository.load(paneId: fixture.paneId) == newer)
    }

    @Test("a new observer launch supersedes older rows while sequence restarts")
    func newLaunchSupersedesPreviousLaunch() async throws {
        let fixture = try ForegroundRepositoryFixture()
        try await fixture.seedBinding()
        let previous = try fixture.observation(sequence: 100)
        #expect(try await fixture.repository.admit(previous) == .admitted)
        let nextLaunch = UUIDv7.generate()
        let nextRepository = SQLitePaneForegroundObservationRepository(
            access: TestForegroundSQLiteAccess(databaseQueue: fixture.database), observerLaunchId: nextLaunch)
        let current = try fixture.observation(sequence: 1, launchId: nextLaunch, program: .codex)
        #expect(try await nextRepository.admit(current) == .admitted)
        #expect(try await nextRepository.load(paneId: fixture.paneId) == current)
    }

    @Test("retirement rejects a result finishing late and removes the stored look")
    func retirementCannotBeUndoneByLateLook() async throws {
        let fixture = try ForegroundRepositoryFixture()
        try await fixture.seedBinding()
        let initial = try fixture.observation(sequence: 1)
        #expect(try await fixture.repository.admit(initial) == .admitted)
        let late = try fixture.observation(sequence: 2)
        try await fixture.repository.retire(paneId: fixture.paneId)
        #expect(try await fixture.repository.admit(late) == .retiredPane)
        #expect(try await fixture.repository.load(paneId: fixture.paneId) == nil)
    }

    @Test("the observation schema stores typed incarnation columns without argv or blobs")
    func observationSchemaIsTyped() async throws {
        let fixture = try ForegroundRepositoryFixture()
        let columns = try await fixture.database.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(terminal_pane_foreground_observation)").map { row in
                (name: row["name"] as String, type: row["type"] as String)
            }
        }
        let names = Set(columns.map(\.name))
        #expect(
            names
                == Set([
                    "pane_id", "zmx_session_id", "binding_generation_id", "program", "observer_launch_id", "sequence",
                    "observed_at",
                    "identity_version", "boot_id", "daemon_pid", "daemon_start_seconds", "daemon_start_microseconds",
                    "leader_pid", "leader_start_seconds", "leader_start_microseconds", "process_group_id",
                    "session_created_at",
                ]))
        #expect(columns.allSatisfy { ["TEXT", "INTEGER"].contains($0.type) })
    }

    @Test("invalid stored session identity is dropped instead of becoming evidence")
    func corruptedIdentityIsNoObservation() async throws {
        let fixture = try ForegroundRepositoryFixture()
        try await fixture.seedBinding()
        let initial = try fixture.observation(sequence: 1)
        #expect(try await fixture.repository.admit(initial) == .admitted)
        try await fixture.database.write { database in
            try database.execute(
                sql: "UPDATE terminal_pane_foreground_observation SET leader_start_microseconds = 1000000")
        }
        #expect(try await fixture.repository.load(paneId: fixture.paneId) == nil)
    }
}

struct ForegroundRepositoryFixture: Sendable {
    let database: DatabaseQueue
    let repository: SQLitePaneForegroundObservationRepository
    let paneId = UUIDv7.generate()
    let sessionId = ZmxSessionID.generateUUIDv7()
    let bindingGenerationId = UUIDv7.generate()
    let launchId = UUIDv7.generate()

    init() throws {
        database = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "foreground-observation-proof")
        try WorkspaceLocalMigrations.migrate(database)
        let sessions = [paneId: sessionId]
        repository = SQLitePaneForegroundObservationRepository(
            access: TestForegroundSQLiteAccess(databaseQueue: database), observerLaunchId: launchId,
            paneSessions: { sessions })
    }

    func observation(
        sequence: UInt64, launchId: UUID? = nil, program: ForegroundProgram = .claudeCode, identity: Data? = nil
    ) throws -> PaneForegroundObservation {
        PaneForegroundObservation(
            paneId: paneId, zmxSessionId: sessionId, sessionIdentity: try identity ?? foregroundTestIdentity(),
            bindingGenerationId: bindingGenerationId, program: program, observerLaunchId: launchId ?? self.launchId,
            sequence: sequence, observedAt: Date(timeIntervalSince1970: 100)
        )
    }

    func seedBinding(status: String = "active") async throws {
        try await database.write { database in
            let conversationId = UUIDv7.generate().uuidString
            try database.execute(
                sql: "INSERT INTO sessions_conversation VALUES (?, 'claude-code', ?, 1, 1)",
                arguments: [conversationId, UUIDv7.generate().uuidString])
            try database.execute(
                sql: """
                    INSERT INTO sessions_operation(operation_scope,correlation_id,operation_kind,semantic_fingerprint,
                        outcome_kind,binding_generation_id,created_at)
                    VALUES ('proof',?,'bind','proof','bindingEstablished',?,1)
                    """, arguments: [UUIDv7.generate().uuidString, bindingGenerationId.uuidString])
            try database.execute(
                sql: """
                    INSERT INTO sessions_pane_binding(binding_generation_id,pane_id,conversation_id,source_generation_id,
                        origin,status,transition_occurrence_id,started_at,ended_at,committed_revision)
                    VALUES (?,?,?,?,'reported',?,?,1,?,?)
                    """,
                arguments: [
                    bindingGenerationId.uuidString, paneId.uuidString, conversationId, UUIDv7.generate().uuidString,
                    status, UUIDv7.generate().uuidString, status == "ended" ? 2 : nil, database.lastInsertedRowID,
                ]
            )
        }
    }

    func replaceBinding() async throws {
        try await database.write { database in
            let nextGeneration = UUIDv7.generate().uuidString
            try database.execute(
                sql: "UPDATE sessions_pane_binding SET status = 'ended', ended_at = 2 WHERE pane_id = ?",
                arguments: [paneId.uuidString])
            try database.execute(
                sql: """
                    INSERT INTO sessions_operation(operation_scope,correlation_id,operation_kind,semantic_fingerprint,
                        outcome_kind,outcome_entity_id,binding_generation_id,created_at)
                    VALUES ('proof',?,'bind','proof','bindingReplaced',?,?,1)
                    """, arguments: [UUIDv7.generate().uuidString, bindingGenerationId.uuidString, nextGeneration])
            try database.execute(
                sql: """
                    INSERT INTO sessions_pane_binding(binding_generation_id,pane_id,conversation_id,source_generation_id,
                        origin,status,transition_occurrence_id,started_at,ended_at,committed_revision)
                    SELECT ?,pane_id,conversation_id,?,'reported','active',?,1,NULL,?
                    FROM sessions_pane_binding WHERE binding_generation_id = ?
                    """,
                arguments: [
                    nextGeneration, UUIDv7.generate().uuidString, UUIDv7.generate().uuidString,
                    database.lastInsertedRowID, bindingGenerationId.uuidString,
                ])
        }
    }
}

struct TestForegroundSQLiteAccess: ForegroundObservationSQLiteAccess {
    let databaseQueue: DatabaseQueue
    func read<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        try await databaseQueue.read(operation)
    }
    func write<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        try await databaseQueue.write(operation)
    }
}
