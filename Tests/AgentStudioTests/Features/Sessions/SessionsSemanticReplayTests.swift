import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioSessions

@Suite("Sessions semantic replay")
struct SessionsSemanticReplayTests {
    @Test("deliberate reports and exact acknowledgment ignore later server receipt time")
    func deliberateAndAcknowledgmentReplayUsesStableIntent() async throws {
        let fixture = try SessionsDatabaseFixture()
        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let paneId = try await prepareSemanticReplayPane(ingestion: ingestion)
            let deliberate = try await submitDeliberateReplays(
                ingestion: ingestion,
                paneId: paneId
            )
            #expect(deliberate.replayedNeedsYou == deliberate.firstNeedsYou)
            #expect(deliberate.replayedClear == deliberate.firstClear)
            #expect(deliberate.replayedDone == deliberate.firstDone)

            let acknowledgment = try await submitAcknowledgmentReplay(
                ingestion: ingestion,
                paneId: paneId
            )
            #expect(acknowledgment.replayed == acknowledgment.first)
            #expect(
                acknowledgment.first
                    == .messageAcknowledged(occurrenceId: acknowledgment.occurrenceId, changed: true)
            )

            let snapshot = try await ingestion.snapshot(makeSessionsSnapshotQuery(paneId: paneId))
            #expect(snapshot.currentAttention.isEmpty)
            #expect(snapshot.results.count == 1)
            #expect(snapshot.messages.count == 1)
            #expect(snapshot.messages.first?.disposition == .seen)
        }
    }
}

private struct DeliberateReplayOutcomes {
    let firstNeedsYou: SessionsMutationOutcome
    let replayedNeedsYou: SessionsMutationOutcome
    let firstClear: SessionsMutationOutcome
    let replayedClear: SessionsMutationOutcome
    let firstDone: SessionsMutationOutcome
    let replayedDone: SessionsMutationOutcome
}

private struct AcknowledgmentReplayOutcomes {
    let occurrenceId: UUID
    let first: SessionsMutationOutcome
    let replayed: SessionsMutationOutcome
}

private func prepareSemanticReplayPane(ingestion: SessionsIngestion) async throws -> UUID {
    let paneId = UUIDv7.generate()
    _ = try await ingestion.submit(
        correlationId: UUIDv7.generate(),
        mutation: .bind(
            makeQualifiedBindMutation(
                paneId: paneId,
                providerConversationId: "conversation-semantic-replay",
                sourceGenerationId: UUIDv7.generate(),
                reportedAt: 1
            )
        )
    )
    return paneId
}

private func submitDeliberateReplays(
    ingestion: SessionsIngestion,
    paneId: UUID
) async throws -> DeliberateReplayOutcomes {
    let needsYouCorrelationId = UUIDv7.generate()
    let firstNeedsYou = try await ingestion.submit(
        correlationId: needsYouCorrelationId,
        mutation: .deliberateNeedsYou(
            SessionsDeliberateNeedsYouMutation(
                paneId: paneId,
                explanation: "same help intent",
                reportedAt: Date(timeIntervalSince1970: 2)
            )
        )
    )
    let replayedNeedsYou = try await ingestion.submit(
        correlationId: needsYouCorrelationId,
        mutation: .deliberateNeedsYou(
            SessionsDeliberateNeedsYouMutation(
                paneId: paneId,
                explanation: "same help intent",
                reportedAt: Date(timeIntervalSince1970: 20)
            )
        )
    )
    let clearCorrelationId = UUIDv7.generate()
    let firstClear = try await ingestion.submit(
        correlationId: clearCorrelationId,
        mutation: .clearDeliberateNeedsYou(
            SessionsClearDeliberateNeedsYouMutation(
                paneId: paneId,
                clearedAt: Date(timeIntervalSince1970: 3)
            )
        )
    )
    let replayedClear = try await ingestion.submit(
        correlationId: clearCorrelationId,
        mutation: .clearDeliberateNeedsYou(
            SessionsClearDeliberateNeedsYouMutation(
                paneId: paneId,
                clearedAt: Date(timeIntervalSince1970: 30)
            )
        )
    )
    let doneCorrelationId = UUIDv7.generate()
    let firstDone = try await ingestion.submit(
        correlationId: doneCorrelationId,
        mutation: .deliberateDone(
            SessionsDeliberateDoneMutation(
                paneId: paneId,
                reportedAt: Date(timeIntervalSince1970: 4)
            )
        )
    )
    let replayedDone = try await ingestion.submit(
        correlationId: doneCorrelationId,
        mutation: .deliberateDone(
            SessionsDeliberateDoneMutation(
                paneId: paneId,
                reportedAt: Date(timeIntervalSince1970: 40)
            )
        )
    )
    return DeliberateReplayOutcomes(
        firstNeedsYou: firstNeedsYou,
        replayedNeedsYou: replayedNeedsYou,
        firstClear: firstClear,
        replayedClear: replayedClear,
        firstDone: firstDone,
        replayedDone: replayedDone
    )
}

private func submitAcknowledgmentReplay(
    ingestion: SessionsIngestion,
    paneId: UUID
) async throws -> AcknowledgmentReplayOutcomes {
    let messageOutcome = try await ingestion.submit(
        correlationId: UUIDv7.generate(),
        mutation: .message(
            SessionsMessageMutation(
                context: .currentPaneBinding(paneId: paneId),
                text: "acknowledge me",
                receivedAt: Date(timeIntervalSince1970: 5)
            )
        )
    )
    guard case .messageSaved(let occurrenceId, .attributed) = messageOutcome else {
        throw SessionsTestError.unexpectedOutcome("Expected attributed message")
    }
    let correlationId = UUIDv7.generate()
    let first = try await ingestion.submit(
        correlationId: correlationId,
        mutation: .acknowledgeMessage(
            SessionsMessageAcknowledgmentMutation(
                occurrenceId: occurrenceId,
                acknowledgedAt: Date(timeIntervalSince1970: 6)
            )
        )
    )
    let replayed = try await ingestion.submit(
        correlationId: correlationId,
        mutation: .acknowledgeMessage(
            SessionsMessageAcknowledgmentMutation(
                occurrenceId: occurrenceId,
                acknowledgedAt: Date(timeIntervalSince1970: 60)
            )
        )
    )
    return AcknowledgmentReplayOutcomes(
        occurrenceId: occurrenceId,
        first: first,
        replayed: replayed
    )
}
