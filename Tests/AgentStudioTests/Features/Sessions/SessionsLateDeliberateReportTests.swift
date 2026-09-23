import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioSessions

/// A deliberate report the CLI spooled while the app was down arrives after
/// launch preparation has ended the generation it was written against. These
/// cases pin what the reducer may do with it: keep it as history, and never let
/// it move the live projection.
@Suite("Late deliberate reports")
struct SessionsLateDeliberateReportTests {
    @Test("a late needs-you after an ended binding is history and leaves the pane state unknown")
    func lateNeedsYouAfterEndedBindingIsHistory() async throws {
        // Arrange
        let fixture = try SessionsDatabaseFixture()
        let repository = fixture.makeRepository()
        try await withSessionsIngestion(repository: repository) { ingestion in
            let paneId = UUIDv7.generate()
            _ = try await bindThenEndGeneration(ingestion: ingestion, paneId: paneId)

            // Act
            let outcome = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .deliberateNeedsYou(
                    SessionsDeliberateNeedsYouMutation(
                        paneId: paneId,
                        explanation: "approve the plan",
                        freshness: .late,
                        reportedAt: Date(timeIntervalSince1970: 10)
                    )
                )
            )

            // Assert
            guard case .historical(let occurrenceId) = outcome else {
                throw SessionsTestError.unexpectedOutcome("\(outcome)")
            }
            let snapshot = try await repository.snapshot(makeSessionsSnapshotQuery(paneId: paneId))
            #expect(snapshot.state == .unknown)
            #expect(snapshot.stateOrigin == nil)
            #expect(snapshot.currentAttention.isEmpty)
            #expect(snapshot.historicalOccurrenceIds.contains(occurrenceId))
        }
    }

    @Test("a late done after an ended binding becomes a historical result and leaves state unknown")
    func lateDoneAfterEndedBindingIsHistoricalResult() async throws {
        // Arrange
        let fixture = try SessionsDatabaseFixture()
        let repository = fixture.makeRepository()
        try await withSessionsIngestion(repository: repository) { ingestion in
            let paneId = UUIDv7.generate()
            let bindingGenerationId = try await bindThenEndGeneration(
                ingestion: ingestion, paneId: paneId)

            // Act
            let outcome = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .deliberateDone(
                    SessionsDeliberateDoneMutation(
                        paneId: paneId,
                        freshness: .late,
                        reportedAt: Date(timeIntervalSince1970: 10)
                    )
                )
            )

            // Assert
            guard case .historical(let occurrenceId) = outcome else {
                throw SessionsTestError.unexpectedOutcome("\(outcome)")
            }
            let snapshot = try await repository.snapshot(makeSessionsSnapshotQuery(paneId: paneId))
            #expect(snapshot.state == .unknown)
            #expect(snapshot.stateOrigin == nil)
            #expect(snapshot.results.count == 1)
            #expect(snapshot.results.first?.freshness == .late)
            #expect(snapshot.results.first?.origin == .agentReported)
            #expect(snapshot.results.first?.bindingGenerationId == bindingGenerationId)
            #expect(snapshot.historicalOccurrenceIds.contains(occurrenceId))
        }
    }

    @Test("a late report admitted before a new session start cannot raise the new generation's state")
    func lateReportDoesNotDisturbALaterGeneration() async throws {
        // Arrange
        let fixture = try SessionsDatabaseFixture()
        let repository = fixture.makeRepository()
        try await withSessionsIngestion(repository: repository) { ingestion in
            let paneId = UUIDv7.generate()
            _ = try await bindThenEndGeneration(ingestion: ingestion, paneId: paneId)
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .deliberateNeedsYou(
                    SessionsDeliberateNeedsYouMutation(
                        paneId: paneId, explanation: "stale ask", freshness: .late,
                        reportedAt: Date(timeIntervalSince1970: 10)))
            )

            // Act
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId,
                        providerConversationId: "conversation-after-relaunch",
                        sourceGenerationId: UUIDv7.generate(),
                        reportedAt: 20
                    )
                )
            )

            // Assert
            let snapshot = try await repository.snapshot(makeSessionsSnapshotQuery(paneId: paneId))
            #expect(snapshot.currentBinding?.status == .active)
            #expect(snapshot.state == .unknown)
            #expect(snapshot.currentAttention.isEmpty)
            #expect(snapshot.staleAttention.isEmpty)
        }
    }

    @Test(
        "a late deliberate report on a pane that never bound keeps the live refusal",
        arguments: [true, false]
    )
    func lateDeliberateReportWithoutAnyBindingIsRefused(isNeedsYou: Bool) async throws {
        // Arrange
        let fixture = try SessionsDatabaseFixture()
        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let paneId = UUIDv7.generate()
            let mutation: SessionsMutation =
                isNeedsYou
                ? .deliberateNeedsYou(
                    SessionsDeliberateNeedsYouMutation(
                        paneId: paneId, explanation: "never bound", freshness: .late,
                        reportedAt: Date(timeIntervalSince1970: 10)))
                : .deliberateDone(
                    SessionsDeliberateDoneMutation(
                        paneId: paneId, freshness: .late,
                        reportedAt: Date(timeIntervalSince1970: 10)))

            // Act / Assert
            await #expect(throws: SessionsRepositoryError.bindingRequired(paneId)) {
                _ = try await ingestion.submit(correlationId: UUIDv7.generate(), mutation: mutation)
            }
        }
    }

    @Test("a live deliberate report still refuses once the binding has ended")
    func liveDeliberateReportStillRequiresAnActiveBinding() async throws {
        // Arrange
        let fixture = try SessionsDatabaseFixture()
        try await withSessionsIngestion(repository: fixture.makeRepository()) { ingestion in
            let paneId = UUIDv7.generate()
            _ = try await bindThenEndGeneration(ingestion: ingestion, paneId: paneId)

            // Act / Assert
            await #expect(throws: SessionsRepositoryError.bindingRequired(paneId)) {
                _ = try await ingestion.submit(
                    correlationId: UUIDv7.generate(),
                    mutation: .deliberateDone(
                        SessionsDeliberateDoneMutation(
                            paneId: paneId, reportedAt: Date(timeIntervalSince1970: 10)))
                )
            }
        }
    }

    /// Binds the pane, then ends that generation exactly as an app relaunch
    /// does, and returns the generation the late report has to find.
    private func bindThenEndGeneration(
        ingestion: SessionsIngestion,
        paneId: UUID
    ) async throws -> UUID {
        let bindOutcome = try await ingestion.submit(
            correlationId: UUIDv7.generate(),
            mutation: .bind(
                makeQualifiedBindMutation(
                    paneId: paneId,
                    providerConversationId: "conversation-late-deliberate",
                    sourceGenerationId: UUIDv7.generate(),
                    reportedAt: 1
                )
            )
        )
        guard case .binding(.established(let binding)) = bindOutcome else {
            throw SessionsTestError.unexpectedOutcome("\(bindOutcome)")
        }
        _ = try await ingestion.prepareForLaunch(at: Date(timeIntervalSince1970: 5))
        return binding.bindingGenerationId
    }
}
