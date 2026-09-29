import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioSessions

@Suite("Sessions commit disposition")
struct SessionsIngestionCommitDispositionTests {
    @Test("a first committed provider occurrence is inserted; correlation and occurrence replays are not")
    func firstCommitAndReplays() async throws {
        let fixture = try SessionsDatabaseFixture()
        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let paneId = UUIDv7.generate()
            let sourceGenerationId = UUIDv7.generate()
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId,
                        providerConversationId: "activity-conversation",
                        sourceGenerationId: sourceGenerationId,
                        reportedAt: 1
                    )
                )
            )
            let mutation = SessionsMutation.recordEvidence(
                SessionsEvidenceMutation(
                    context: .sourceGeneration(paneId: paneId, sourceGenerationId: sourceGenerationId),
                    occurrenceId: UUIDv7.generate(),
                    turnId: "activity-turn",
                    subject: .root,
                    kind: .activityStarted,
                    origin: .reported,
                    freshness: .live,
                    occurredAt: Date(timeIntervalSince1970: 2),
                    sourceCursor: nil
                )
            )
            let correlationId = UUIDv7.generate()

            let first = try await ingestion.submitWithCommitDisposition(
                correlationId: correlationId, mutation: mutation
            )
            let replay = try await ingestion.submitWithCommitDisposition(
                correlationId: correlationId, mutation: mutation
            )
            let alias = try await ingestion.submitWithCommitDisposition(
                correlationId: UUIDv7.generate(), mutation: mutation
            )

            #expect(first.disposition == .inserted)
            #expect(replay.disposition == .replayed)
            #expect(alias.disposition == .replayed)
            #expect(first.outcome == replay.outcome)
            #expect(first.outcome == alias.outcome)
        }
    }
}
