import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioSessions

@Suite("Sessions canonical replay")
struct SessionsCanonicalReplayTests {
    @Test("lifecycle source times are retained on the operation and future end time is absent")
    func lifecycleSourceTimeUsesOperationRow() async throws {
        let fixture = try CanonicalReplayFixture()
        defer { fixture.files.removeFiles() }
        try await withSessionsIngestion(repository: fixture.repository) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceId = UUIDv7.generate()
            let startCorrelation = UUIDv7.generate()
            var start = makeQualifiedBindMutation(
                paneId: paneId, providerConversationId: "lifecycle", sourceGenerationId: sourceId, reportedAt: 1000)
            start.sourceOccurredAt = Date(timeIntervalSince1970: 900)
            _ = try await ingestion.submit(correlationId: startCorrelation, mutation: .bind(start))
            let endCorrelation = UUIDv7.generate()
            var end = SessionsSourceEndMutation(
                paneId: paneId, sourceGenerationId: sourceId, endedAt: Date(timeIntervalSince1970: 1100))
            end.sourceOccurredAt = Date(timeIntervalSince1970: 1401)
            _ = try await ingestion.submit(correlationId: endCorrelation, mutation: .sourceEnded(end))
            let times = try await fixture.access.read { database in
                try [startCorrelation, endCorrelation].map { correlation in
                    try Double.fetchOne(
                        database, sql: "SELECT source_occurred_at FROM sessions_operation WHERE correlation_id = ?",
                        arguments: [correlation.uuidString])
                }
            }
            #expect(times == [900, nil])
        }
    }

    @Test("the latest ended binding remains current after the wall clock steps backward")
    func endedBindingUsesCommitOrder() async throws {
        let fixture = try CanonicalReplayFixture()
        defer { fixture.files.removeFiles() }
        try await withSessionsIngestion(repository: fixture.repository) { ingestion in
            let paneId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "older", sourceGenerationId: UUIDv7.generate(),
                        reportedAt: 200)))
            let newerSource = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "newer", sourceGenerationId: newerSource,
                        reportedAt: 100)))
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .sourceEnded(
                    .init(paneId: paneId, sourceGenerationId: newerSource, endedAt: Date(timeIntervalSince1970: 50))))
            #expect(
                try await ingestion.snapshot(makeSessionsSnapshotQuery(paneId: paneId)).currentBinding?
                    .providerConversationId == "newer")
        }
    }

    @Test("bind replay ignores later admission time and freshness after reopening SQLite")
    func bindReplayUsesCanonicalProviderIntent() async throws {
        let fixture = try CanonicalReplayFixture()
        defer { fixture.files.removeFiles() }
        let paneId = UUIDv7.generate()
        let sourceId = UUIDv7.generate()
        let occurrenceId = UUIDv7.generate()
        let first = try await withSessionsIngestion(repository: fixture.repository) { ingestion in
            try await ingestion.submitWithCommitDisposition(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "conversation-A", sourceGenerationId: sourceId,
                        occurrenceId: occurrenceId, reportedAt: 1)))
        }
        try await withSessionsIngestion(repository: fixture.files.makeRepository()) { ingestion in
            let replay = try await ingestion.submitWithCommitDisposition(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "conversation-A", sourceGenerationId: sourceId,
                        occurrenceId: occurrenceId, freshness: .historical, reportedAt: 500)))
            #expect(replay.disposition == .replayed)
            #expect(replay.outcome == first.outcome)
        }
    }

    @Test(
        "source UTC time is stored for display and excessive future times become absent",
        arguments: [200.0, 1200.0, 1300.0, 1301.0])
    func sourceTimeIsNotAdmissionTime(sourceTimestamp: Double) async throws {
        let fixture = try CanonicalReplayFixture()
        defer { fixture.files.removeFiles() }
        try await withSessionsIngestion(repository: fixture.repository) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "conversation", sourceGenerationId: sourceId,
                        reportedAt: 1)))
            let occurrenceId = UUIDv7.generate()
            let evidence = canonicalEvidence(paneId: paneId, sourceId: sourceId, occurrenceId: occurrenceId, at: 1000)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let value = try JSONDecoder().decode(CanonicalEvidenceJSON.self, from: encoder.encode(evidence))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let withSourceTime = try decoder.decode(
                SessionsEvidenceMutation.self, from: encoder.encode(value.addingSourceTime(sourceTimestamp)))
            _ = try await ingestion.submit(correlationId: UUIDv7.generate(), mutation: .recordEvidence(withSourceTime))
            let storedSourceTime = try await fixture.access.read { database in
                try Double.fetchOne(
                    database, sql: "SELECT source_occurred_at FROM sessions_evidence WHERE occurrence_id = ?",
                    arguments: [occurrenceId.uuidString])
            }
            #expect(storedSourceTime == (sourceTimestamp <= 1300 ? sourceTimestamp : nil))
        }
    }

    @Test(
        "arrival time, freshness and correlation never change provider intent",
        arguments: CanonicalReplayScenario.allCases)
    func replayAcrossAdmissionChanges(scenario: CanonicalReplayScenario) async throws {
        let fixture = try CanonicalReplayFixture()
        defer { fixture.files.removeFiles() }
        let paneId = UUIDv7.generate()
        let sourceId = UUIDv7.generate()
        let occurrenceId = UUIDv7.generate()
        let recorded = try await withSessionsIngestion(repository: fixture.repository) { ingestion in
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "conversation-A", sourceGenerationId: sourceId,
                        reportedAt: 1)))
            let first = try await ingestion.submitWithCommitDisposition(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    canonicalEvidence(paneId: paneId, sourceId: sourceId, occurrenceId: occurrenceId, at: 2)))
            if scenario == .replacement {
                _ = try await ingestion.submit(
                    correlationId: UUIDv7.generate(),
                    mutation: .bind(
                        makeQualifiedBindMutation(
                            paneId: paneId, providerConversationId: "conversation-B",
                            sourceGenerationId: UUIDv7.generate(), reportedAt: 3)))
            }
            return first
        }
        let before = try await fixture.effects()
        let repository = scenario == .restart ? try fixture.files.makeRepository() : fixture.repository
        try await withSessionsIngestion(repository: repository) { ingestion in
            let replay = try await ingestion.submitWithCommitDisposition(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    canonicalEvidence(
                        paneId: paneId, sourceId: sourceId, occurrenceId: occurrenceId,
                        freshness: scenario == .freshness ? .historical : .live, at: 200))
            )
            #expect(replay.disposition == .replayed)
            #expect(replay.outcome == recorded.outcome)
        }
        #expect(try await fixture.effects() == before)
    }

    @Test("the same correlation replays when only server arrival data changes")
    func correlationIgnoresArrivalData() async throws {
        let fixture = try CanonicalReplayFixture()
        defer { fixture.files.removeFiles() }
        try await withSessionsIngestion(repository: fixture.repository) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "conversation", sourceGenerationId: sourceId,
                        reportedAt: 1)))
            let correlationId = UUIDv7.generate()
            let occurrenceId = UUIDv7.generate()
            let first = try await ingestion.submitWithCommitDisposition(
                correlationId: correlationId,
                mutation: .recordEvidence(
                    canonicalEvidence(paneId: paneId, sourceId: sourceId, occurrenceId: occurrenceId, at: 2)))
            let replay = try await ingestion.submitWithCommitDisposition(
                correlationId: correlationId,
                mutation: .recordEvidence(
                    canonicalEvidence(
                        paneId: paneId, sourceId: sourceId, occurrenceId: occurrenceId, freshness: .late, at: 20)))
            #expect(replay.outcome == first.outcome)
            #expect(replay.disposition == .replayed)
        }
    }

    @Test("a changed provider intent still conflicts without committing an effect")
    func changedContentConflicts() async throws {
        let fixture = try CanonicalReplayFixture()
        defer { fixture.files.removeFiles() }
        try await withSessionsIngestion(repository: fixture.repository) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "conversation", sourceGenerationId: sourceId,
                        reportedAt: 1)))
            let occurrenceId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    canonicalEvidence(paneId: paneId, sourceId: sourceId, occurrenceId: occurrenceId, at: 2)))
            let before = try await fixture.effects()
            await #expect(throws: SessionsRepositoryError.occurrenceConflict(occurrenceId)) {
                try await ingestion.submit(
                    correlationId: UUIDv7.generate(),
                    mutation: .recordEvidence(
                        canonicalEvidence(
                            paneId: paneId, sourceId: sourceId, occurrenceId: occurrenceId,
                            intent: .init(kind: .completed), at: 3)))
            }
            #expect(try await fixture.effects() == before)
        }
    }

    @Test(
        "NULL fingerprint version replays by correlation or occurrence with no write and no activity",
        arguments: [false, true])
    func legacyReplayHasNoWrites(byOccurrence: Bool) async throws {
        let fixture = try CanonicalReplayFixture()
        defer { fixture.files.removeFiles() }
        try await withSessionsIngestion(repository: fixture.repository) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "conversation", sourceGenerationId: sourceId,
                        reportedAt: 1)))
            let correlationId = UUIDv7.generate()
            let occurrenceId = UUIDv7.generate()
            let first = try await ingestion.submitWithCommitDisposition(
                correlationId: correlationId,
                mutation: .recordEvidence(
                    canonicalEvidence(paneId: paneId, sourceId: sourceId, occurrenceId: occurrenceId, at: 2)))
            try await fixture.access.write { database in
                try database.execute(
                    sql:
                        "UPDATE sessions_operation SET fingerprint_version = NULL, semantic_fingerprint = 'old-whole-mutation' WHERE correlation_id = ?",
                    arguments: [correlationId.uuidString])
            }
            let before = try await fixture.allWrites()
            let replay = try await ingestion.submitWithCommitDisposition(
                correlationId: byOccurrence ? UUIDv7.generate() : correlationId,
                mutation: .recordEvidence(
                    canonicalEvidence(
                        paneId: paneId, sourceId: sourceId, occurrenceId: occurrenceId, intent: .init(kind: .completed),
                        freshness: .historical, at: 500))
            )
            #expect(replay.outcome == first.outcome)
            // PR A refreshes activity only for inserted. Replay must keep its contract.
            #expect(replay.disposition == .replayed)
            #expect(try await fixture.allWrites() == before)
        }
    }

    @Test("sequenced evidence follows admission revision across a wall-clock rollback")
    func durableAdmissionOrder() async throws {
        let fixture = try CanonicalReplayFixture()
        defer { fixture.files.removeFiles() }
        try await withSessionsIngestion(repository: fixture.repository) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "conversation", sourceGenerationId: sourceId,
                        reportedAt: 1)))
            let firstId = UUIDv7.generate()
            let secondId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    canonicalEvidence(
                        paneId: paneId, sourceId: sourceId, occurrenceId: firstId, intent: .init(turnId: "old-turn"),
                        at: 200)))
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    canonicalEvidence(
                        paneId: paneId, sourceId: sourceId, occurrenceId: secondId, intent: .init(turnId: "new-turn"),
                        at: 100)))
            let snapshot = try await ingestion.snapshot(makeSessionsSnapshotQuery(paneId: paneId))
            #expect(snapshot.historicalOccurrenceIds.contains(firstId))
            #expect(!snapshot.historicalOccurrenceIds.contains(secondId))
            let sequences = try await fixture.access.read { database in
                try Int64.fetchAll(
                    database, sql: "SELECT admission_sequence FROM sessions_evidence ORDER BY admission_sequence")
            }
            #expect(sequences.count == 2)
            let firstSequence = try #require(sequences.first)
            let lastSequence = try #require(sequences.last)
            #expect(firstSequence < lastSequence)
        }
    }

    @Test("legacy evidence sorts before sequenced evidence regardless of old wall time")
    func legacyEvidencePrecedesNewEvidence() async throws {
        let fixture = try CanonicalReplayFixture()
        defer { fixture.files.removeFiles() }
        try await withSessionsIngestion(repository: fixture.repository) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "conversation", sourceGenerationId: sourceId,
                        reportedAt: 1)))
            let oldId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    canonicalEvidence(
                        paneId: paneId, sourceId: sourceId, occurrenceId: oldId, intent: .init(turnId: "legacy-turn"),
                        at: 500)))
            try await fixture.access.write { database in
                try database.execute(
                    sql: "UPDATE sessions_evidence SET admission_sequence = NULL WHERE occurrence_id = ?",
                    arguments: [oldId.uuidString])
            }
            let newId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    canonicalEvidence(
                        paneId: paneId, sourceId: sourceId, occurrenceId: newId, intent: .init(turnId: "new-turn"),
                        at: 2)))
            let snapshot = try await ingestion.snapshot(makeSessionsSnapshotQuery(paneId: paneId))
            #expect(snapshot.historicalOccurrenceIds.contains(oldId))
            #expect(!snapshot.historicalOccurrenceIds.contains(newId))
        }
    }

    @Test("active sessionStart returns its binding and historical retired start never revives it")
    func sessionStartBindingAdmission() async throws {
        let fixture = try CanonicalReplayFixture()
        defer { fixture.files.removeFiles() }
        try await withSessionsIngestion(repository: fixture.repository) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceId = UUIDv7.generate()
            let first = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "conversation-A", sourceGenerationId: sourceId,
                        reportedAt: 1)))
            guard case .binding(.established(let binding)) = first else {
                throw SessionsTestError.unexpectedOutcome("Expected binding")
            }
            let active = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "conversation-A", sourceGenerationId: sourceId,
                        reportedAt: 2)))
            #expect(active == .binding(.unchanged(binding)))
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "conversation-B", sourceGenerationId: UUIDv7.generate(),
                        reportedAt: 3)))
            let historicalId = UUIDv7.generate()
            let historical = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "conversation-A", sourceGenerationId: UUIDv7.generate(),
                        occurrenceId: historicalId, freshness: .historical, reportedAt: 4)))
            #expect(historical == .historical(occurrenceId: historicalId))
            #expect(
                try await ingestion.snapshot(makeSessionsSnapshotQuery(paneId: paneId)).currentBinding?
                    .providerConversationId == "conversation-B")
        }
    }
}

enum CanonicalReplayScenario: String, CaseIterable, Sendable {
    case restart
    case replacement
    case freshness
}

private struct CanonicalReplayFixture: Sendable {
    let files: SessionsFileDatabaseFixture
    let access: TestSessionsSQLiteAccess
    let repository: SessionsRepository

    init() throws {
        files = try SessionsFileDatabaseFixture()
        let queue = try DatabaseQueue(path: files.databaseURL.path)
        try WorkspaceLocalMigrations.migrate(queue)
        access = TestSessionsSQLiteAccess(databaseQueue: queue)
        repository = SessionsRepository(sqliteAccess: access)
    }

    func effects() async throws -> [Int] {
        try await access.read { database in
            try [
                "sessions_evidence", "sessions_pane_binding", "sessions_source", "sessions_attention",
                "sessions_result",
            ].map {
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \($0)") ?? 0
            }
        }
    }

    func allWrites() async throws -> Int64 {
        try await access.read { database in
            try Int64.fetchOne(database, sql: "SELECT total_changes()") ?? 0
        }
    }
}

private func canonicalEvidence(
    paneId: UUID,
    sourceId: UUID,
    occurrenceId: UUID,
    intent: CanonicalEvidenceIntent = .init(),
    freshness: SessionsEvidenceFreshness = .live,
    at timestamp: TimeInterval
) -> SessionsEvidenceMutation {
    SessionsEvidenceMutation(
        context: .sourceGeneration(paneId: paneId, sourceGenerationId: sourceId), occurrenceId: occurrenceId,
        turnId: intent.turnId, subject: .root, kind: intent.kind, origin: .reported, freshness: freshness,
        occurredAt: Date(timeIntervalSince1970: timestamp), sourceCursor: nil)
}

private struct CanonicalEvidenceIntent: Sendable {
    var turnId: String = "turn"
    var kind: SessionsEvidenceKind = .activityStarted
}

/// Mirrors the existing evidence envelope only to add the new source field at
/// its real Codable boundary; decoding still uses the production mutation type.
private struct CanonicalEvidenceJSON: Codable {
    let context: SessionsReportContext
    let occurrenceId: UUID
    let turnId: String?
    let subject: SessionsEvidenceSubject
    let kind: SessionsEvidenceKind
    let origin: SessionsEvidenceOrigin
    let freshness: SessionsEvidenceFreshness
    let occurredAt: Double
    let sourceCursor: String?
    var sourceOccurredAt: Double?

    func addingSourceTime(_ timestamp: Double) -> Self {
        var copy = self
        copy.sourceOccurredAt = timestamp
        return copy
    }
}
