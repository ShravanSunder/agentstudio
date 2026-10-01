import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioSessions

struct ResumeResolverFixture: Sendable {
    let database: DatabaseQueue
    let repository: SessionsRepository
    let resolver: SessionsResumeResolver
    let paneId = UUIDv7.generate()
    let zmxSessionId = ZmxSessionID.generateUUIDv7()
    let sourceGenerationId = UUIDv7.generate()
    let providerSessionId = UUIDv7.generate().uuidString
    let launchBootId = "resume-current-boot"

    init() throws {
        let storage = try SessionsDatabaseFixture()
        database = storage.databaseQueue
        repository = storage.makeRepository()
        resolver = SessionsResumeResolver(repository: repository)
    }

    func bind(providerIdentifier: String = "claude-code", sessionId: String? = nil) async throws
        -> SessionsBindingRecord
    {
        try await withSessionsIngestion(repository: repository) { ingestion in
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .bind(
                    SessionsBindMutation(
                        paneId: paneId, providerIdentifier: providerIdentifier, providerVersion: "proof-version",
                        providerMode: "proof", providerConversationId: sessionId ?? providerSessionId,
                        sourceId: "proof-source",
                        sourceGenerationId: sourceGenerationId,
                        transition: .qualifiedSessionStart(occurrenceId: UUIDv7.generate()),
                        freshness: .live, reportedAt: Date(timeIntervalSince1970: 1))))
        }
        let snapshot = try await repository.snapshot(makeSessionsSnapshotQuery(paneId: paneId))
        return try #require(snapshot.currentBinding)
    }

    func observation(
        binding: SessionsBindingRecord, program: ForegroundProgram = .claudeCode,
        bootId: String = "resume-old-boot", generation: UUID? = nil, sessionId: ZmxSessionID? = nil
    ) throws
        -> PaneForegroundObservation
    {
        let identity = ZmxSessionIdentity(
            version: 1, bootID: bootId,
            daemon: .init(pid: 6000, startSeconds: 100, startMicroseconds: 1),
            terminalLeader: .init(pid: 6001, startSeconds: 100, startMicroseconds: 2),
            processGroupID: 6001, sessionCreatedAt: 100)
        return PaneForegroundObservation(
            paneId: paneId, zmxSessionId: sessionId ?? zmxSessionId,
            sessionIdentity: try identity.encoded(), bindingGenerationId: generation ?? binding.bindingGenerationId,
            program: program, observerLaunchId: UUIDv7.generate(), sequence: 1,
            observedAt: Date(timeIntervalSince1970: 1))
    }

    func input(observation: PaneForegroundObservation?, inventory: ZmxSessionInventory = .complete([:]))
        -> ResumeEvidenceInput
    {
        ResumeEvidenceInput(
            paneId: paneId, zmxSessionId: zmxSessionId, observation: observation,
            launchBootId: launchBootId, inventory: inventory)
    }

    func setEvidenceFlags(historical: Bool = false, unordered: Bool = false) async throws {
        try await database.write { connection in
            try connection.execute(
                sql: """
                    UPDATE sessions_pane_binding
                    SET started_from_historical_report = ?, evidence_unordered = ? WHERE pane_id = ?
                    """, arguments: [historical, unordered, paneId.uuidString])
        }
    }

    func reportEnd(_ reason: ProviderEndReason) async throws {
        try await withSessionsIngestion(repository: repository) { ingestion in
            _ = try await ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .sourceEnded(
                    SessionsSourceEndMutation(
                        paneId: paneId, sourceGenerationId: sourceGenerationId,
                        endedAt: Date(timeIntervalSince1970: 3), providerEndReason: reason, providerEndReasonText: nil))
            )
        }
    }
}
