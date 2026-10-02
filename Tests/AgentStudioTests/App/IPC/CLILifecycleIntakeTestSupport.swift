import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioSessions
import AgentStudioTestHarness
import Foundation
import GRDB
import Synchronization

@testable import AgentStudio
@testable import AgentStudioCLIStore
@testable import AgentStudioCore

struct LifecycleIntakeFileFixture: Sendable {
    let rootURL: URL
    let storeURL: URL
    let workspaceID = UUIDv7.generate()
    let paneID: UUID
    let storeID: UUID
    let access: LifecycleTestSQLiteAccess
    let repository: SessionsRepository
    let ingestion: SessionsIngestion
    let members: LifecyclePaneMembership
    let refusals: LifecycleRefusalLedger
    let intakes = LifecycleIntakeOwnerLedger()
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    static func make(rootURL existingRoot: URL? = nil, paneID: UUID = UUIDv7.generate()) async throws -> Self {
        let prepared = try await valueFromDedicatedThread {
            let root =
                existingRoot
                ?? FileManager.default.temporaryDirectory.appending(path: "lifecycle-intake-\(UUIDv7.generate())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let storeURL = root.appending(path: "cli.sqlite")
            let writer = try CLIStore.openWriter(url: storeURL, channel: .debug).get()
            let local = try DatabaseQueue(path: root.appending(path: "local.sqlite").path)
            try WorkspaceLocalMigrations.migrate(local)
            return (root, storeURL, writer.identity.storeID, local)
        }
        let access = LifecycleTestSQLiteAccess(queue: prepared.3)
        let repository = SessionsRepository(sqliteAccess: access)
        let ingestion = SessionsIngestion(
            repository: repository, limits: .init(maximumPendingPerPane: 32, maximumPendingGlobal: 128), probe: { _ in }
        )
        return Self(
            rootURL: prepared.0, storeURL: prepared.1, paneID: paneID, storeID: prepared.2, access: access,
            repository: repository, ingestion: ingestion, members: LifecyclePaneMembership([paneID]),
            refusals: LifecycleRefusalLedger())
    }

    func intake() -> CLILifecycleReportIntake {
        let members = members
        let refusals = refusals
        let intake = CLILifecycleReportIntake(
            storeURL: storeURL, expectedChannel: .debug, admission: adapter(), sqliteAccess: access,
            workspaceID: workspaceID,
            paneExists: { pane, _ in members.contains(pane) },
            refusalProbe: { reason in refusals.record(reason) })
        intakes.record(intake)
        return intake
    }

    func adapter() -> AgentStudioIPCSessionsAdapter {
        AgentStudioIPCSessionsAdapter(
            ingestion: ingestion,
            providerRegistry: SessionsProviderAdapterRegistry(profiles: [
                .codexCommandLine,
                .init(
                    providerIdentifier: "claude-code", exactVersion: "2.1.274", operatingMode: "cli",
                    qualifiedCapabilities: [.sessionStart, .sessionEnd]),
            ]), now: { now })
    }

    func record(
        sessionID: String = UUIDv7.generate().uuidString, event: CLILifecycleEvent = .sessionStart,
        provider: String = "codex", version: String? = nil
    ) -> CLILifecycleReportRecord {
        .init(
            reportID: UUIDv7.generate(), paneID: paneID, providerIdentifier: provider,
            providerVersion: version ?? (provider == "codex" ? "0.154.0" : "2.1.274"), providerMode: "cli",
            event: event, conversationID: sessionID, correlationID: UUIDv7.generate(), recordedAt: now,
            bootSessionID: "test-boot")
    }

    func seed(_ record: CLILifecycleReportRecord, sequence: Int64? = nil) async throws -> CLILifecycleReport {
        let storeURL = storeURL
        return try await valueFromDedicatedThread {
            let writer = try CLIStore.openWriter(url: storeURL, channel: .debug).get()
            return try writer.databaseQueue.write { database in
                let name: String
                let reason: String?
                switch record.event {
                case .sessionStart:
                    name = "sessionStart"
                    reason = nil
                case .sessionEnd(let value):
                    name = "sessionEnd"
                    reason = value
                }
                try database.execute(
                    sql: """
                        INSERT INTO cli_lifecycle_report
                        (sequence,report_id,pane_id,provider_identifier,provider_version,provider_mode,event_name,
                         conversation_id,end_reason,correlation_id,recorded_at,boot_session_id)
                        VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                        """,
                    arguments: [
                        sequence, record.reportID.uuidString, record.paneID.uuidString, record.providerIdentifier,
                        record.providerVersion, record.providerMode, name, record.conversationID, reason,
                        record.correlationID.uuidString, Int64(record.recordedAt.timeIntervalSince1970 * 1000),
                        record.bootSessionID,
                    ])
                return CLILifecycleReport(sequence: database.lastInsertedRowID, record: record)
            }
        }
    }

    func params(_ record: CLILifecycleReportRecord, sequence: Int64? = nil, storeID: UUID? = nil)
        -> IPCSessionEventParams
    {
        let name: IPCSessionEventName
        let reason: String?
        switch record.event {
        case .sessionStart:
            name = .sessionStart
            reason = nil
        case .sessionEnd(let value):
            name = .sessionEnd
            reason = value
        }
        let provider = IPCSessionProviderIdentity(
            identifier: record.providerIdentifier, version: record.providerVersion, mode: record.providerMode)
        let event = IPCSessionEventIdentity(
            name: name, conversationId: record.conversationID, turnId: nil, requestId: nil,
            toolId: nil, subagentId: nil, occurrenceId: record.reportID, endReason: reason)
        return .init(
            handle: "self", provider: provider, event: event, correlationId: record.correlationID,
            lifecycleReport: sequence.map { .init(storeId: storeID ?? self.storeID, sequence: $0) })
    }

    func binding() async throws -> SessionsBindingRecord? {
        try await repository.snapshot(.pane(paneID, page: .init(limit: 10, after: nil))).currentBinding
    }

    func state() async throws -> LifecycleDatabaseObservation {
        let storeID = storeID.uuidString
        return try await access.read { database in
            try LifecycleDatabaseObservation(
                mark: Int64.fetchOne(
                    database, sql: "SELECT last_handled_sequence FROM sessions_cli_report_cursor WHERE store_id=?",
                    arguments: [storeID]) ?? 0,
                bindings: Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sessions_pane_binding") ?? 0,
                operations: Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sessions_operation") ?? 0,
                activeSources: Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sessions_source WHERE status='active'")
                    ?? 0)
        }
    }

    func sameProviderLookVerdict() async throws -> ResumeEvidence {
        let binding = try await binding()
        let sessionID = ZmxSessionID.generateUUIDv7()
        let identity = try ZmxSessionIdentity(
            version: 1, bootID: "earlier-boot", daemon: .init(pid: 50, startSeconds: 1, startMicroseconds: 0),
            terminalLeader: .init(pid: 51, startSeconds: 1, startMicroseconds: 0), processGroupID: 51,
            sessionCreatedAt: 1
        ).encoded()
        let look = PaneForegroundObservation(
            paneId: paneID, zmxSessionId: sessionID, sessionIdentity: identity,
            bindingGenerationId: binding?.bindingGenerationId,
            program: .codex, observerLaunchId: UUIDv7.generate(), sequence: 1, observedAt: now)
        return await SessionsResumeResolver(repository: repository).resumeEvidence(
            for: .init(
                paneId: paneID, zmxSessionId: sessionID, observation: look, launchBootId: "current-boot",
                inventory: .complete([:])))
    }

    func close() async {
        for intake in intakes.snapshot() { await intake.finish() }
        await ingestion.finish()
    }
    func remove() { try? FileManager.default.removeItem(at: rootURL) }
}

struct LifecycleDatabaseObservation: Equatable, Sendable {
    let mark: Int64
    let bindings: Int
    let operations: Int
    let activeSources: Int
}

final class LifecyclePaneMembership: Sendable {
    private let panes: Mutex<Set<UUID>>
    init(_ panes: Set<UUID>) { self.panes = Mutex(panes) }
    func contains(_ pane: UUID) -> Bool { panes.withLock { $0.contains(pane) } }
    func retire(_ pane: UUID) { panes.withLock { _ = $0.remove(pane) } }
}

final class LifecycleRefusalLedger: Sendable {
    private let reasons = Mutex<[CLILifecycleRefusalReason]>([])
    func record(_ reason: CLILifecycleRefusalReason) { reasons.withLock { $0.append(reason) } }
    func snapshot() -> [CLILifecycleRefusalReason] { reasons.withLock { $0 } }
}

enum LifecycleTransactionInjectedFailure: Error { case afterCursorWrite }

final class LifecycleTestSQLiteAccess: SessionsSQLiteAccess, Sendable {
    let queue: DatabaseQueue
    private let rejectCursorAdvance = Mutex(false)
    private let rejectUnorderedAdmission = Mutex(false)
    init(queue: DatabaseQueue) { self.queue = queue }
    func failNextCursorAdvance() { rejectCursorAdvance.withLock { $0 = true } }
    func failNextUnorderedAdmission() { rejectUnorderedAdmission.withLock { $0 = true } }
    func read<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        try await queue.read(operation)
    }
    func write<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        try await queue.write { database in
            let unorderedBefore =
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sessions_pane_binding WHERE evidence_unordered=1")
                ?? 0
            let before =
                try Int64.fetchOne(database, sql: "SELECT MAX(last_handled_sequence) FROM sessions_cli_report_cursor")
                ?? 0
            let result = try operation(database)
            let unorderedAfter =
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sessions_pane_binding WHERE evidence_unordered=1")
                ?? 0
            if unorderedAfter > unorderedBefore,
                self.rejectUnorderedAdmission.withLock({ reject in
                    defer { reject = false }
                    return reject
                })
            {
                throw LifecycleTransactionInjectedFailure.afterCursorWrite
            }
            let after =
                try Int64.fetchOne(database, sql: "SELECT MAX(last_handled_sequence) FROM sessions_cli_report_cursor")
                ?? 0
            if after > before,
                self.rejectCursorAdvance.withLock({ reject in
                    defer { reject = false }
                    return reject
                })
            {
                throw LifecycleTransactionInjectedFailure.afterCursorWrite
            }
            return result
        }
    }
}

final class LifecycleIntakeOwnerLedger: Sendable {
    private let intakes = Mutex<[CLILifecycleReportIntake]>([])
    func record(_ intake: CLILifecycleReportIntake) { intakes.withLock { $0.append(intake) } }
    func snapshot() -> [CLILifecycleReportIntake] { intakes.withLock { $0 } }
}
