import AgentStudioInfrastructure
import Foundation
import GRDB
import Synchronization
import Testing

@testable import AgentStudioCore
@testable import AgentStudioSessions

@Suite("Sessions provider end fact")
struct SessionsProviderEndFactTests {
    @Test("a reported end persists its time, closed reason and exact display text")
    func reportedEndPersistsFact() async throws {
        let fixture = try SessionsDatabaseFixture()
        let repository = fixture.makeRepository()
        let paneId = UUIDv7.generate()
        let sourceGenerationId = UUIDv7.generate()
        let endedAt = Date(timeIntervalSince1970: 3)
        let rawReason = "future reason with private text\n第二行"

        try await withSessionsIngestion(repository: repository) { ingestion in
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "end-fact",
                        sourceGenerationId: sourceGenerationId, reportedAt: 1
                    ))
            )

            let outcome = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .sourceEnded(
                    SessionsSourceEndMutation(
                        paneId: paneId, sourceGenerationId: sourceGenerationId, endedAt: endedAt,
                        providerEndReason: .unrecognized, providerEndReasonText: rawReason
                    ))
            )

            #expect(outcome == .sourceEnded(sourceGenerationId: sourceGenerationId))
        }

        let binding = try #require(
            try await repository.bindingForProviderConversation(
                paneId: paneId, providerIdentifier: "qualified-test-provider", providerConversationId: "end-fact"
            ))
        #expect(binding.providerEndedAt == endedAt)
        #expect(binding.providerEndReason == .unrecognized)
        #expect(binding.providerEndReasonText == rawReason)
        #expect(binding.status == .ended)
        let stored = try await storedEndFact(fixture: fixture, bindingGenerationId: binding.bindingGenerationId)
        #expect(stored.reason == "unrecognized")
        #expect(stored.text == rawReason)
        #expect(stored.time != nil)
    }

    @Test("a provider end after a launch sweep records the fact and preserves the sweep time")
    func reportedEndAfterSweepIsNotDiscarded() async throws {
        let fixture = try SessionsDatabaseFixture()
        let repository = fixture.makeRepository()
        let paneId = UUIDv7.generate()
        let sourceGenerationId = UUIDv7.generate()
        let sweptAt = Date(timeIntervalSince1970: 2)
        let providerEndedAt = Date(timeIntervalSince1970: 3)

        try await withSessionsIngestion(repository: repository) { ingestion in
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "swept-end",
                        sourceGenerationId: sourceGenerationId, reportedAt: 1
                    ))
            )
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(), mutation: .prepareForLaunch(sweptAt)
            )
            let swept = try #require(
                try await repository.bindingForProviderConversation(
                    paneId: paneId, providerIdentifier: "qualified-test-provider",
                    providerConversationId: "swept-end"
                ))
            #expect(swept.status == .ended)
            #expect(swept.endedAt == sweptAt)
            #expect(swept.providerEndedAt == nil)
            #expect(swept.providerEndReason == nil)

            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .sourceEnded(
                    SessionsSourceEndMutation(
                        paneId: paneId, sourceGenerationId: sourceGenerationId, endedAt: providerEndedAt,
                        providerEndReason: .personExit, providerEndReasonText: "exit"
                    ))
            )
        }

        let binding = try #require(
            try await repository.bindingForProviderConversation(
                paneId: paneId, providerIdentifier: "qualified-test-provider", providerConversationId: "swept-end"
            ))
        #expect(binding.status == .ended)
        #expect(binding.endedAt == sweptAt)
        #expect(binding.providerEndedAt == providerEndedAt)
        #expect(binding.providerEndReason == .personExit)
        #expect(binding.providerEndReasonText == "exit")
        let stored = try await storedEndFact(fixture: fixture, bindingGenerationId: binding.bindingGenerationId)
        #expect(stored.reason == "personExit")
        #expect(stored.text == "exit")
        #expect(stored.time != nil)
    }

    @Test("later sweeps preserve a reported end with no supplied reason")
    func laterSweepPreservesProviderEnd() async throws {
        let fixture = try SessionsDatabaseFixture()
        let repository = fixture.makeRepository()
        let paneId = UUIDv7.generate()
        let sourceGenerationId = UUIDv7.generate()
        let endedAt = Date(timeIntervalSince1970: 2)

        try await withSessionsIngestion(repository: repository) { ingestion in
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "no-end-reason",
                        sourceGenerationId: sourceGenerationId, reportedAt: 1
                    ))
            )
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .sourceEnded(
                    SessionsSourceEndMutation(
                        paneId: paneId, sourceGenerationId: sourceGenerationId, endedAt: endedAt,
                        providerEndReason: .notGiven, providerEndReasonText: nil
                    ))
            )
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(), mutation: .prepareForLaunch(Date(timeIntervalSince1970: 3))
            )
        }

        let binding = try #require(
            try await repository.bindingForProviderConversation(
                paneId: paneId, providerIdentifier: "qualified-test-provider",
                providerConversationId: "no-end-reason"
            ))
        #expect(binding.providerEndedAt == endedAt)
        #expect(binding.providerEndReason == .notGiven)
        #expect(binding.providerEndReasonText == nil)
    }

    @Test("the ingestion probe receives only the closed reason after a reported end commits")
    func reasonProbeCarriesClosedCase() async throws {
        let fixture = try SessionsDatabaseFixture()
        let paneId = UUIDv7.generate()
        let sourceGenerationId = UUIDv7.generate()
        let reportedReasons = Mutex<[ProviderEndReason]>([])
        let ingestion = SessionsIngestion(
            repository: fixture.makeRepository(),
            limits: SessionsIngestionLimits(maximumPendingPerPane: 32, maximumPendingGlobal: 128),
            probe: { statistics in
                if case .providerEndReported(let reason) = statistics.event {
                    reportedReasons.withLock { $0.append(reason) }
                }
            }
        )
        try await withOwnedSessionsIngestion(ingestion) { owner in
            _ = try await owner.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    makeQualifiedBindMutation(
                        paneId: paneId, providerConversationId: "probe-end",
                        sourceGenerationId: sourceGenerationId, reportedAt: 1
                    ))
            )
            _ = try await owner.submit(
                correlationId: UUIDv7.generate(),
                mutation: .sourceEnded(
                    SessionsSourceEndMutation(
                        paneId: paneId, sourceGenerationId: sourceGenerationId,
                        endedAt: Date(timeIntervalSince1970: 2),
                        providerEndReason: .unrecognized,
                        providerEndReasonText: "private provider reason that must never enter a probe"
                    ))
            )
        }
        #expect(reportedReasons.withLock { $0 } == [.unrecognized])
    }

    private func storedEndFact(
        fixture: SessionsDatabaseFixture, bindingGenerationId: UUID
    ) async throws -> StoredEndFact {
        try await fixture.sqliteAccess.read { database in
            let row = try #require(
                Row.fetchOne(
                    database,
                    sql: """
                        SELECT provider_end_reason, provider_end_reason_text, CAST(provider_ended_at AS TEXT) AS end_time
                        FROM sessions_pane_binding WHERE binding_generation_id = ?
                        """,
                    arguments: [bindingGenerationId.uuidString]
                ))
            return StoredEndFact(
                reason: row["provider_end_reason"], text: row["provider_end_reason_text"], time: row["end_time"]
            )
        }
    }

    private struct StoredEndFact: Sendable {
        let reason: String?
        let text: String?
        let time: String?
    }
}
