import AgentStudioIPCClientCore
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioTestHarness
import Foundation
import GRDB
import Synchronization
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioSessions
@testable import AgentStudioTerminal

final class HeldResumeSessionsAccess: SessionsSQLiteAccess, Sendable {
    let database: DatabaseQueue
    private let nextHold = Mutex<HeldStep<Void>?>(nil)
    init(database: DatabaseQueue) { self.database = database }
    func holdNextWrite(_ hold: HeldStep<Void>) { nextHold.withLock { $0 = hold } }
    func read<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        try await database.read(operation)
    }
    func write<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        let hold = nextHold.withLock { held in
            defer { held = nil }
            return held
        }
        if let hold { try await hold.arrive(()) }
        return try await database.write(operation)
    }
}

struct AppResumeSessionsFixture: Sendable {
    let database: DatabaseQueue
    let access: HeldResumeSessionsAccess
    let repository: SessionsRepository
    let paneId = UUIDv7.generate()
    let zmxSessionId = ZmxSessionID.generateUUIDv7()
    let sessionId = UUIDv7.generate().uuidString
    init() throws {
        database = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "resume-sessions-app-proof")
        try WorkspaceLocalMigrations.migrate(database)
        access = HeldResumeSessionsAccess(database: database)
        repository = SessionsRepository(sqliteAccess: access)
    }
    func makeIngestion() -> SessionsIngestion {
        SessionsIngestion(
            repository: repository, limits: .init(maximumPendingPerPane: 32, maximumPendingGlobal: 128), probe: { _ in }
        )
    }
    func snapshot() async throws -> SessionsSnapshot {
        try await repository.snapshot(.init(paneId: paneId, page: .init(limit: 100, after: nil)))
    }
    func event(_ name: CodexHookEventName, version: String? = nil) throws -> IPCSessionEventParams {
        let payload = CodexHookPayload(
            sessionId: sessionId, turnId: "turn-proof", hookEventName: name.rawValue,
            codexVersion: version, reason: name == .sessionEnd ? "exit" : nil)
        let projected = try #require(
            CodexHookProjection.project(eventName: name, payload: payload, reportIdentifier: UUIDv7.generate()))
        return .init(
            handle: paneId.uuidString, provider: projected.provider, event: projected.event,
            correlationId: UUIDv7.generate())
    }
}

enum RecordedRestoreTrigger: Equatable, Sendable { case bindingChanged, agentMessage }
struct CommittedRestoreTrigger: Equatable, Sendable {
    let kind: RecordedRestoreTrigger
    let paneId: UUID
    let bindingId: UUID?
    let sessionId: String?
    let ended: Bool
    let messages: Int
}
final class RestoreSessionsTriggerLedger: Sendable {
    private let state = Mutex<[CommittedRestoreTrigger]>([])
    func snapshot() -> [CommittedRestoreTrigger] { state.withLock { $0 } }
    func record(_ trigger: ForegroundLookTrigger, paneId: UUID, repository: SessionsRepository) async {
        let kind: RecordedRestoreTrigger
        switch trigger {
        case .bindingChanged: kind = .bindingChanged
        case .agentMessage: kind = .agentMessage
        default: return
        }
        do {
            let snapshot = try await repository.snapshot(.init(paneId: paneId, page: .init(limit: 100, after: nil)))
            state.withLock {
                $0.append(
                    .init(
                        kind: kind, paneId: paneId,
                        bindingId: snapshot.currentBinding?.bindingGenerationId,
                        sessionId: snapshot.currentBinding?.providerConversationId,
                        ended: snapshot.currentBinding?.providerEndedAt != nil, messages: snapshot.messages.count))
            }
        } catch { Issue.record("could not read the committed Sessions value at its foreground trigger") }
    }
}

func resumeProducerAdapter(
    ingestion: SessionsIngestion, fixture: AppResumeSessionsFixture,
    ledger: RestoreSessionsTriggerLedger
) -> AgentStudioIPCSessionsAdapter {
    AgentStudioIPCSessionsAdapter(
        ingestion: ingestion, providerRegistry: .init(profiles: SessionsProviderProfile.shippedProfiles),
        now: { Date(timeIntervalSince1970: 3) },
        foregroundLookSink: { trigger, pane in
            await ledger.record(trigger, paneId: pane, repository: fixture.repository)
        })
}
