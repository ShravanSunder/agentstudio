import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioSessions

@Suite("Sessions provider occurrence replay")
struct SessionsOccurrenceReplayTests {
    @Test("bind occurrences retain their earliest outcome and reserve alias correlations")
    func bindOccurrencesRetainEarliestOutcome() async throws {
        let fixture = try SessionsDatabaseFixture()
        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceGenerationA = UUIDv7.generate()
            let occurrenceO1 = UUIDv7.generate()
            let bindO1 = makeQualifiedBindMutation(
                paneId: paneId,
                providerConversationId: "conversation-A",
                sourceGenerationId: sourceGenerationA,
                occurrenceId: occurrenceO1,
                reportedAt: 1
            )
            let firstOutcome = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(bindO1)
            )
            guard case .binding(.established(let bindingA)) = firstOutcome else {
                Issue.record("Expected O1 to establish A, got \(firstOutcome)")
                return
            }

            let aliasCorrelation = UUIDv7.generate()
            let aliasOutcome = try await ingestion.submit(
                correlationId: aliasCorrelation,
                mutation: .bind(bindO1)
            )
            #expect(aliasOutcome == firstOutcome)

            let occurrenceO2 = UUIDv7.generate()
            let bindO2 = makeQualifiedBindMutation(
                paneId: paneId,
                providerConversationId: "conversation-A",
                sourceGenerationId: sourceGenerationA,
                occurrenceId: occurrenceO2,
                reportedAt: 2
            )
            let repeatedOutcome = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(bindO2)
            )
            #expect(repeatedOutcome == .binding(.unchanged(bindingA)))

            let repeatedAliasCorrelation = UUIDv7.generate()
            let repeatedAliasOutcome = try await ingestion.submit(
                correlationId: repeatedAliasCorrelation,
                mutation: .bind(bindO2)
            )
            #expect(repeatedAliasOutcome == repeatedOutcome)

            let recordedOccurrences = try await loadOperationOccurrences(
                fixture.sqliteAccess,
                correlations: [aliasCorrelation, repeatedAliasCorrelation]
            )
            #expect(recordedOccurrences[aliasCorrelation] == occurrenceO1)
            #expect(recordedOccurrences[repeatedAliasCorrelation] == occurrenceO2)

            let beforeAliasConflict = try await ingestion.snapshot(
                makeSessionsSnapshotQuery(paneId: paneId)
            )
            await #expect(
                throws: SessionsRepositoryError.correlationConflict(repeatedAliasCorrelation)
            ) {
                try await ingestion.submit(
                    correlationId: repeatedAliasCorrelation,
                    mutation: .bind(
                        makeQualifiedBindMutation(
                            paneId: paneId,
                            providerConversationId: "conversation-A",
                            sourceGenerationId: sourceGenerationA,
                            occurrenceId: UUIDv7.generate(),
                            reportedAt: 3
                        )
                    )
                )
            }
            #expect(
                try await ingestion.snapshot(makeSessionsSnapshotQuery(paneId: paneId))
                    == beforeAliasConflict
            )

            let beforeOccurrenceConflict = try await occurrenceReplayState(
                fixture,
                paneId: paneId,
                sourceGenerationId: sourceGenerationA
            )
            await #expect(throws: SessionsRepositoryError.occurrenceConflict(occurrenceO1)) {
                try await ingestion.submit(
                    correlationId: UUIDv7.generate(),
                    mutation: .bind(
                        makeQualifiedBindMutation(
                            paneId: paneId,
                            providerConversationId: "conversation-conflict",
                            sourceGenerationId: UUIDv7.generate(),
                            occurrenceId: occurrenceO1,
                            reportedAt: 4
                        )
                    )
                )
            }
            let afterOccurrenceConflict = try await occurrenceReplayState(
                fixture,
                paneId: paneId,
                sourceGenerationId: sourceGenerationA
            )
            #expect(afterOccurrenceConflict == beforeOccurrenceConflict)
        }
    }

    @Test("evidence occurrence conflict rolls back before cursor and completion projection")
    func evidenceOccurrenceConflictIsAtomic() async throws {
        let fixture = try SessionsDatabaseFixture()
        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceGenerationId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId,
                        providerConversationId: "conversation-evidence",
                        sourceGenerationId: sourceGenerationId,
                        reportedAt: 1
                    )
                )
            )
            let occurrenceId = UUIDv7.generate()
            let evidence = SessionsEvidenceMutation(
                context: .sourceGeneration(
                    paneId: paneId,
                    sourceGenerationId: sourceGenerationId
                ),
                occurrenceId: occurrenceId,
                turnId: "turn-occurrence",
                subject: .root,
                kind: .activityStarted,
                origin: .reported,
                freshness: .live,
                occurredAt: Date(timeIntervalSince1970: 2),
                sourceCursor: "cursor-original"
            )
            let firstOutcome = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(evidence)
            )
            let aliasCorrelation = UUIDv7.generate()
            let aliasOutcome = try await ingestion.submit(
                correlationId: aliasCorrelation,
                mutation: .recordEvidence(evidence)
            )
            #expect(aliasOutcome == firstOutcome)
            #expect(
                try await loadOperationOccurrences(
                    fixture.sqliteAccess,
                    correlations: [aliasCorrelation]
                )[aliasCorrelation] == occurrenceId
            )

            let beforeConflict = try await occurrenceReplayState(
                fixture,
                paneId: paneId,
                sourceGenerationId: sourceGenerationId
            )
            await #expect(throws: SessionsRepositoryError.occurrenceConflict(occurrenceId)) {
                try await ingestion.submit(
                    correlationId: UUIDv7.generate(),
                    mutation: .recordEvidence(
                        SessionsEvidenceMutation(
                            context: evidence.context,
                            occurrenceId: occurrenceId,
                            turnId: evidence.turnId,
                            subject: evidence.subject,
                            kind: .completed,
                            origin: evidence.origin,
                            freshness: evidence.freshness,
                            occurredAt: Date(timeIntervalSince1970: 3),
                            sourceCursor: "cursor-conflict"
                        )
                    )
                )
            }
            let afterConflict = try await occurrenceReplayState(
                fixture,
                paneId: paneId,
                sourceGenerationId: sourceGenerationId
            )
            #expect(afterConflict == beforeConflict)
        }
    }

    @Test("evidence occurrence identity is global across panes")
    func evidenceOccurrenceIdentityIsGlobalAcrossPanes() async throws {
        let fixture = try SessionsDatabaseFixture()
        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let occurrenceId = UUIDv7.generate()
            let first = try await prepareOccurrenceEvidencePane(
                ingestion: ingestion,
                occurrenceId: occurrenceId,
                ordinal: 1
            )
            let second = try await prepareOccurrenceEvidencePane(
                ingestion: ingestion,
                occurrenceId: nil,
                ordinal: 2
            )
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(first.evidence)
            )

            let beforeConflict = try await occurrenceReplayState(
                fixture,
                paneId: second.paneId,
                sourceGenerationId: second.sourceGenerationId
            )
            await #expect(throws: SessionsRepositoryError.occurrenceConflict(occurrenceId)) {
                try await ingestion.submit(
                    correlationId: UUIDv7.generate(),
                    mutation: .recordEvidence(
                        SessionsEvidenceMutation(
                            context: second.evidence.context,
                            occurrenceId: occurrenceId,
                            turnId: second.evidence.turnId,
                            subject: second.evidence.subject,
                            kind: second.evidence.kind,
                            origin: second.evidence.origin,
                            freshness: second.evidence.freshness,
                            occurredAt: second.evidence.occurredAt,
                            sourceCursor: "cross-pane-conflict"
                        )
                    )
                )
            }
            let afterConflict = try await occurrenceReplayState(
                fixture,
                paneId: second.paneId,
                sourceGenerationId: second.sourceGenerationId
            )
            #expect(afterConflict == beforeConflict)
        }
    }

    @Test("bind and evidence occurrences use distinct typed namespaces")
    func bindAndEvidenceOccurrencesUseDistinctNamespaces() async throws {
        let fixture = try SessionsDatabaseFixture()
        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceGenerationId = UUIDv7.generate()
            let sharedOccurrenceId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId,
                        providerConversationId: "conversation-kind-namespace",
                        sourceGenerationId: sourceGenerationId,
                        occurrenceId: sharedOccurrenceId,
                        reportedAt: 1
                    )
                )
            )

            let evidenceOutcome = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    SessionsEvidenceMutation(
                        context: .sourceGeneration(
                            paneId: paneId,
                            sourceGenerationId: sourceGenerationId
                        ),
                        occurrenceId: sharedOccurrenceId,
                        turnId: "turn-kind-namespace",
                        subject: .root,
                        kind: .activityStarted,
                        origin: .reported,
                        freshness: .live,
                        occurredAt: Date(timeIntervalSince1970: 2),
                        sourceCursor: nil
                    )
                )
            )

            #expect(evidenceOutcome == .evidenceRecorded(occurrenceId: sharedOccurrenceId))
        }
    }

    @Test("repository rejects occurrence replay with mismatched scope or kind before reduction")
    func repositoryRejectsMismatchedOccurrenceMetadata() async throws {
        let fixture = try SessionsDatabaseFixture()
        let repository = fixture.makeRepository()
        let paneId = UUIDv7.generate()
        let occurrenceId = UUIDv7.generate()
        try await withSessionsIngestion(repository: repository) { ingestion in
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId,
                        providerConversationId: "conversation-metadata",
                        sourceGenerationId: UUIDv7.generate(),
                        occurrenceId: occurrenceId,
                        reportedAt: 1
                    )
                )
            )
        }
        let storedFingerprint = try await loadSemanticFingerprint(
            fixture.sqliteAccess,
            occurrenceId: occurrenceId
        )
        let metadataMismatches = [
            SessionsRepositoryOperation(
                correlationId: UUIDv7.generate(),
                operationScope: "pane:\(UUIDv7.generate().uuidString)",
                operationKind: SessionsProviderOccurrenceKind.bind.rawValue,
                semanticFingerprint: storedFingerprint,
                providerOccurrence: SessionsProviderOccurrenceIdentity(
                    kind: .bind,
                    occurrenceId: occurrenceId
                ),
                contextQuery: .pane(paneId),
                createdAt: Date(timeIntervalSince1970: 2)
            ),
            SessionsRepositoryOperation(
                correlationId: UUIDv7.generate(),
                operationScope: "pane:\(paneId.uuidString)",
                operationKind: SessionsProviderOccurrenceKind.evidence.rawValue,
                semanticFingerprint: storedFingerprint,
                providerOccurrence: SessionsProviderOccurrenceIdentity(
                    kind: .bind,
                    occurrenceId: occurrenceId
                ),
                contextQuery: .pane(paneId),
                createdAt: Date(timeIntervalSince1970: 2)
            ),
        ]

        for operation in metadataMismatches {
            await #expect(throws: SessionsRepositoryError.occurrenceConflict(occurrenceId)) {
                try await repository.apply(operation: operation) { _ in
                    Issue.record("Occurrence metadata mismatch reached reduction")
                    return SessionsRepositoryReduction(
                        outcome: .historical(occurrenceId: occurrenceId)
                    )
                }
            }
        }
    }

    @Test("concurrent and reopened bind replays return the earliest outcome")
    func concurrentAndReopenedBindReplayReturnsEarliestOutcome() async throws {
        let fixture = try SessionsFileDatabaseFixture()
        defer { fixture.removeFiles() }
        let paneId = UUIDv7.generate()
        let occurrenceId = UUIDv7.generate()
        let bind = makeQualifiedBindMutation(
            paneId: paneId,
            providerConversationId: "conversation-concurrent",
            sourceGenerationId: UUIDv7.generate(),
            occurrenceId: occurrenceId,
            reportedAt: 1
        )
        let earliestOutcome = try await withSessionsIngestion(
            repository: fixture.makeRepository()
        ) { ingestion in
            async let first = ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(bind)
            )
            async let second = ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(bind)
            )
            let outcomes = try await [first, second]
            #expect(outcomes[0] == outcomes[1])
            return outcomes[0]
        }

        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let reopenedOutcome = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(bind)
            )
            #expect(reopenedOutcome == earliestOutcome)
        }
    }
}

private struct OccurrenceEvidencePane {
    let paneId: UUID
    let sourceGenerationId: UUID
    let evidence: SessionsEvidenceMutation
}

private struct OccurrenceReplayState: Equatable {
    let snapshot: SessionsSnapshot
    let operationCount: Int
    let bindingCount: Int
    let sourceCount: Int
    let evidenceCount: Int
    let resultCount: Int
    let sourceCursor: String?
}

private func prepareOccurrenceEvidencePane(
    ingestion: SessionsIngestion,
    occurrenceId: UUID?,
    ordinal: Int
) async throws -> OccurrenceEvidencePane {
    let paneId = UUIDv7.generate()
    let sourceGenerationId = UUIDv7.generate()
    _ = try await ingestion.submit(
        correlationId: UUIDv7.generate(),
        mutation: .bind(
            makeQualifiedBindMutation(
                paneId: paneId,
                providerConversationId: "conversation-\(ordinal)",
                sourceGenerationId: sourceGenerationId,
                reportedAt: TimeInterval(ordinal)
            )
        )
    )
    return OccurrenceEvidencePane(
        paneId: paneId,
        sourceGenerationId: sourceGenerationId,
        evidence: SessionsEvidenceMutation(
            context: .sourceGeneration(
                paneId: paneId,
                sourceGenerationId: sourceGenerationId
            ),
            occurrenceId: occurrenceId ?? UUIDv7.generate(),
            turnId: "turn-\(ordinal)",
            subject: .root,
            kind: .activityStarted,
            origin: .reported,
            freshness: .live,
            occurredAt: Date(timeIntervalSince1970: TimeInterval(ordinal + 10)),
            sourceCursor: nil
        )
    )
}

private func loadOperationOccurrences(
    _ sqliteAccess: TestSessionsSQLiteAccess,
    correlations: [UUID]
) async throws -> [UUID: UUID] {
    try await sqliteAccess.read { database in
        var occurrences: [UUID: UUID] = [:]
        for correlation in correlations {
            if let rawOccurrence = try String.fetchOne(
                database,
                sql: "SELECT outcome_occurrence_id FROM sessions_operation WHERE correlation_id = ?",
                arguments: [correlation.uuidString]
            ), let occurrence = UUID(uuidString: rawOccurrence) {
                occurrences[correlation] = occurrence
            }
        }
        return occurrences
    }
}

private func loadSemanticFingerprint(
    _ sqliteAccess: TestSessionsSQLiteAccess,
    occurrenceId: UUID
) async throws -> String {
    try await sqliteAccess.read { database in
        try #require(
            try String.fetchOne(
                database,
                sql: """
                    SELECT semantic_fingerprint FROM sessions_operation
                    WHERE operation_kind = 'bind' AND outcome_occurrence_id = ?
                    ORDER BY commit_revision ASC
                    LIMIT 1
                    """,
                arguments: [occurrenceId.uuidString]
            )
        )
    }
}

private func occurrenceReplayState(
    _ fixture: SessionsDatabaseFixture,
    paneId: UUID,
    sourceGenerationId: UUID
) async throws -> OccurrenceReplayState {
    let snapshot = try await fixture.makeRepository().snapshot(
        makeSessionsSnapshotQuery(paneId: paneId)
    )
    return try await fixture.sqliteAccess.read { database in
        func count(_ table: String) throws -> Int {
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
        }
        return try OccurrenceReplayState(
            snapshot: snapshot,
            operationCount: count("sessions_operation"),
            bindingCount: count("sessions_pane_binding"),
            sourceCount: count("sessions_source"),
            evidenceCount: count("sessions_evidence"),
            resultCount: count("sessions_result"),
            sourceCursor: String.fetchOne(
                database,
                sql: "SELECT last_cursor FROM sessions_source WHERE source_generation_id = ?",
                arguments: [sourceGenerationId.uuidString]
            )
        )
    }
}
