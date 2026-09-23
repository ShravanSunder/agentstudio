import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioSessions

@Suite("Sessions deliberate and provider precedence")
struct SessionsDeliberateProviderPrecedenceTests {
    @Test("reused provider request identity remains scoped by turn and subject in SQLite")
    func reusedProviderRequestIdentityUsesFullMatchingContext() async throws {
        let fixture = try SessionsDatabaseFixture()
        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceGenerationId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId,
                        providerConversationId: "conversation-reused-request",
                        sourceGenerationId: sourceGenerationId,
                        reportedAt: 1
                    )
                )
            )
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    providerEvidence(
                        paneId: paneId,
                        sourceGenerationId: sourceGenerationId,
                        turnId: "turn-current",
                        subject: .root,
                        kind: .activityStarted,
                        timestamp: 2
                    )
                )
            )
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    providerEvidence(
                        paneId: paneId,
                        sourceGenerationId: sourceGenerationId,
                        turnId: "turn-old",
                        subject: .root,
                        kind: .needsYouOpened(requestId: "reused-request", explanation: "old"),
                        timestamp: 3
                    )
                )
            )
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    providerEvidence(
                        paneId: paneId,
                        sourceGenerationId: sourceGenerationId,
                        turnId: "turn-current",
                        subject: .root,
                        kind: .needsYouOpened(requestId: "reused-request", explanation: "root"),
                        timestamp: 4
                    )
                )
            )
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    providerEvidence(
                        paneId: paneId,
                        sourceGenerationId: sourceGenerationId,
                        turnId: "turn-current",
                        subject: .subagent("child-1"),
                        kind: .needsYouOpened(requestId: "reused-request", explanation: "child"),
                        timestamp: 5
                    )
                )
            )
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    providerEvidence(
                        paneId: paneId,
                        sourceGenerationId: sourceGenerationId,
                        turnId: "turn-old",
                        subject: .root,
                        kind: .needsYouResolved(requestId: "reused-request"),
                        timestamp: 6
                    )
                )
            )

            let snapshot = try await ingestion.snapshot(makeSessionsSnapshotQuery(paneId: paneId))
            #expect(snapshot.state == .needsYou)
            #expect(snapshot.currentAttention.count == 2)
            #expect(Set(snapshot.currentAttention.map(\.subject)) == [.root, .subagent("child-1")])
            #expect(snapshot.currentAttention.allSatisfy { $0.turnId == "turn-current" })
        }
    }

    @Test("identifier-free reports share the current provider turn without outranking it")
    func deliberateReportsShareProviderTurnAndUpgradeOneResult() async throws {
        let fixture = try SessionsDatabaseFixture()
        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let context = try await prepareProviderRunningContext(ingestion: ingestion)
            let attentionSnapshot = try await recordDeliberateAttention(
                ingestion: ingestion,
                paneId: context.paneId
            )
            #expect(attentionSnapshot.state == .running)
            #expect(attentionSnapshot.stateOrigin == .reported)
            #expect(attentionSnapshot.currentAttention.count == 1)
            #expect(attentionSnapshot.currentAttention.first?.origin == .agentReported)

            let deliberateDoneSnapshot = try await clearAttentionAndRecordDeliberateDone(
                ingestion: ingestion,
                paneId: context.paneId
            )
            #expect(deliberateDoneSnapshot.state == .running)
            #expect(deliberateDoneSnapshot.stateOrigin == .reported)
            #expect(deliberateDoneSnapshot.results.count == 1)
            #expect(deliberateDoneSnapshot.results.first?.turnId == "turn-A")
            #expect(deliberateDoneSnapshot.results.first?.origin == .agentReported)

            let providerDoneSnapshot = try await recordProviderCompletion(
                ingestion: ingestion,
                context: context
            )
            #expect(providerDoneSnapshot.state == .done)
            #expect(providerDoneSnapshot.stateOrigin == .reported)
            #expect(providerDoneSnapshot.results.count == 1)
            #expect(providerDoneSnapshot.results.first?.turnId == "turn-A")
            #expect(providerDoneSnapshot.results.first?.origin == .reported)
        }
    }
}

private struct ProviderRunningContext {
    let paneId: UUID
    let sourceGenerationId: UUID
}

private func prepareProviderRunningContext(
    ingestion: SessionsIngestion
) async throws -> ProviderRunningContext {
    let context = ProviderRunningContext(
        paneId: UUIDv7.generate(),
        sourceGenerationId: UUIDv7.generate()
    )
    _ = try await ingestion.submit(
        correlationId: UUIDv7.generate(),
        mutation: .bind(
            makeQualifiedBindMutation(
                paneId: context.paneId,
                providerConversationId: "conversation-provider-precedence",
                sourceGenerationId: context.sourceGenerationId,
                reportedAt: 1
            )
        )
    )
    _ = try await ingestion.submit(
        correlationId: UUIDv7.generate(),
        mutation: .recordEvidence(
            providerEvidence(
                paneId: context.paneId,
                sourceGenerationId: context.sourceGenerationId,
                turnId: "turn-A",
                subject: .root,
                kind: .activityStarted,
                timestamp: 2
            )
        )
    )
    return context
}

private func recordDeliberateAttention(
    ingestion: SessionsIngestion,
    paneId: UUID
) async throws -> SessionsSnapshot {
    _ = try await ingestion.submit(
        correlationId: UUIDv7.generate(),
        mutation: .deliberateNeedsYou(
            SessionsDeliberateNeedsYouMutation(
                paneId: paneId,
                explanation: "Need owner input",
                reportedAt: Date(timeIntervalSince1970: 3)
            )
        )
    )
    return try await ingestion.snapshot(makeSessionsSnapshotQuery(paneId: paneId))
}

private func clearAttentionAndRecordDeliberateDone(
    ingestion: SessionsIngestion,
    paneId: UUID
) async throws -> SessionsSnapshot {
    _ = try await ingestion.submit(
        correlationId: UUIDv7.generate(),
        mutation: .clearDeliberateNeedsYou(
            SessionsClearDeliberateNeedsYouMutation(
                paneId: paneId,
                clearedAt: Date(timeIntervalSince1970: 4)
            )
        )
    )
    _ = try await ingestion.submit(
        correlationId: UUIDv7.generate(),
        mutation: .deliberateDone(
            SessionsDeliberateDoneMutation(
                paneId: paneId,
                reportedAt: Date(timeIntervalSince1970: 5)
            )
        )
    )
    return try await ingestion.snapshot(makeSessionsSnapshotQuery(paneId: paneId))
}

private func recordProviderCompletion(
    ingestion: SessionsIngestion,
    context: ProviderRunningContext
) async throws -> SessionsSnapshot {
    _ = try await ingestion.submit(
        correlationId: UUIDv7.generate(),
        mutation: .recordEvidence(
            providerEvidence(
                paneId: context.paneId,
                sourceGenerationId: context.sourceGenerationId,
                turnId: "turn-A",
                subject: .root,
                kind: .completed,
                timestamp: 6
            )
        )
    )
    return try await ingestion.snapshot(makeSessionsSnapshotQuery(paneId: context.paneId))
}

private func providerEvidence(
    paneId: UUID,
    sourceGenerationId: UUID,
    turnId: String,
    subject: SessionsEvidenceSubject,
    kind: SessionsEvidenceKind,
    timestamp: TimeInterval
) -> SessionsEvidenceMutation {
    SessionsEvidenceMutation(
        context: .sourceGeneration(
            paneId: paneId,
            sourceGenerationId: sourceGenerationId
        ),
        occurrenceId: UUIDv7.generate(),
        turnId: turnId,
        subject: subject,
        kind: kind,
        origin: .reported,
        freshness: .live,
        occurredAt: Date(timeIntervalSince1970: timestamp),
        sourceCursor: "cursor-\(timestamp)"
    )
}
