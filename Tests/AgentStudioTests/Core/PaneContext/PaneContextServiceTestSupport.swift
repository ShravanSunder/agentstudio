import AgentStudioInfrastructure
import AgentStudioTestHarness
import AgentStudioTestSupport
import Foundation
import GRDB
import Synchronization
import Testing

@testable import AgentStudioCore

final class PaneContextServiceFixture: Sendable {
    let rootDirectory: URL
    let databasePool: DatabasePool
    let sqliteAccess: HeldPaneContextSQLiteAccess
    let clock = TestPushClock()
    let time: PaneContextTestTime
    let membership = TestPaneContextMembership()
    let paneId = PaneId.generateUUIDv7()
    let sender: AgentMessageSender

    init() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-context-\(UUIDv7.generate())")
        databasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: rootDirectory.appending(path: "local.sqlite"),
            label: "AgentStudio.sqlite.pane-context-tests"
        )
        try WorkspaceLocalMigrations.migrate(databasePool)
        sqliteAccess = HeldPaneContextSQLiteAccess(databasePool: databasePool)
        time = PaneContextTestTime(clock: clock)
        sender = .session(
            provider: try BridgeAgentProviderName("claude-code"),
            sessionRef: try BridgeAgentSessionRef("session-\(UUIDv7.generate())"),
            bindingGeneration: UUIDv7.generate()
        )
        membership.addPane(paneId)
        try databasePool.write { database in
            try database.execute(
                sql: "CREATE TABLE test_pane_context_binding (pane_id TEXT PRIMARY KEY, generation TEXT NOT NULL)")
            if case .session(_, _, let generation) = sender {
                try database.execute(
                    sql: "INSERT INTO test_pane_context_binding VALUES (?, ?)",
                    arguments: [paneId.uuidString, generation.uuidString]
                )
            }
        }
    }

    func makeService() -> PaneContextService {
        PaneContextService(
            sqliteAccess: sqliteAccess,
            clock: clock,
            wallNow: { [time] in time.now },
            membership: membership,
            currentBindingGeneration: { paneId, database in
                let value = try String.fetchOne(
                    database,
                    sql: "SELECT generation FROM test_pane_context_binding WHERE pane_id = ?",
                    arguments: [paneId.uuidString]
                )
                return value.flatMap(UUID.init(uuidString:))
            }
        )
    }

    func message(
        id: AgentMessageId = .generateUUIDv7(),
        paneId: PaneId? = nil,
        sender: AgentMessageSender? = nil,
        body: String = "Exact message",
        actions: [MessageAction] = [],
        shape: PaneMessageSendShape = .notice
    ) -> PaneMessageSendRequest {
        PaneMessageSendRequest(
            paneId: paneId ?? self.paneId,
            messageId: id,
            sender: sender ?? self.sender,
            sourceOccurredAt: nil,
            importance: .attention,
            body: body,
            why: nil,
            actions: actions,
            shape: shape
        )
    }

    func message(why: String) -> PaneMessageSendRequest {
        messageWithMetadata(message(), why: why, sourceOccurredAt: nil)
    }

    func message(sourceOccurredAt: Date, body: String = "Exact message", why: String? = nil) -> PaneMessageSendRequest {
        messageWithMetadata(message(body: body), why: why, sourceOccurredAt: sourceOccurredAt)
    }

    private func messageWithMetadata(_ request: PaneMessageSendRequest, why: String?, sourceOccurredAt: Date?)
        -> PaneMessageSendRequest
    {
        PaneMessageSendRequest(
            paneId: request.paneId, messageId: request.messageId, sender: request.sender,
            sourceOccurredAt: sourceOccurredAt, importance: request.importance, body: request.body,
            why: why, actions: request.actions, shape: request.shape
        )
    }

    func ask(
        id: AgentMessageId = .generateUUIDv7(),
        paneId: PaneId? = nil,
        body: String = "Choose",
        form: AskForm = .freeText(placeholder: nil),
        blocking: Bool = false,
        deadline: Date? = nil
    ) -> PaneMessageSendRequest {
        message(
            id: id,
            paneId: paneId,
            body: body,
            shape: .ask(
                reason: .question,
                form: form,
                waiting: blocking ? .blocking(deadline: deadline ?? time.now.addingTimeInterval(60)) : .nonBlocking
            )
        )
    }

    func detail(_ service: PaneContextService, paneId: PaneId? = nil, page: PaneContextReadPage = .first) async throws
        -> PaneContextDetail
    {
        let result = await service.readDetail(PaneContextReadRequest(paneId: paneId ?? self.paneId, page: page))
        let detail: PaneContextDetail?
        if case .detail(let value) = result { detail = value } else { detail = nil }
        return try #require(detail, "readDetail must return detail, got \(result)")
    }

    func epoch(
        _ service: PaneContextService, stream: PaneWriteStream = .title, claimId: UUID = UUIDv7.generate(),
        writer: AgentMessageSender? = nil
    ) async throws -> UInt64 {
        let result = await service.claimEpoch(
            PaneEpochClaimRequest(paneId: paneId, writer: writer ?? sender, stream: stream, claimId: claimId))
        let epoch: UInt64?
        if case .claimed(let value) = result { epoch = value } else { epoch = nil }
        return try #require(epoch, "claimEpoch must return an epoch, got \(result)")
    }

    func title(_ text: String?, epoch: UInt64, counter: UInt64, writer: AgentMessageSender? = nil)
        -> PaneTitleWriteRequest
    {
        PaneTitleWriteRequest(
            paneId: paneId, writer: writer ?? sender, text: text,
            writeNumber: WriteNumber(epoch: epoch, counter: counter))
    }

    func line(_ summary: String?, epoch: UInt64, counter: UInt64, lifetime: AgentLineLifetime = .untilReplaced)
        -> PaneLineWriteRequest
    {
        let line = summary.map {
            AgentLineInput(summary: $0, work: .working(.indeterminate), detail: nil, refs: [], lifetime: lifetime)
        }
        return PaneLineWriteRequest(
            paneId: paneId, writer: sender, line: line, writeNumber: WriteNumber(epoch: epoch, counter: counter))
    }

    func changes(_ service: PaneContextService, after: UInt64 = 0, sender: AgentMessageSender? = nil) async throws
        -> PaneMessageChangesPage
    {
        let result = await service.changes(
            PaneMessageChangesRequest(paneId: paneId, writer: sender ?? self.sender, after: AnswerPosition(after)))
        let page: PaneMessageChangesPage?
        if case .page(let value) = result { page = value } else { page = nil }
        return try #require(page, "changes must return a page, got \(result)")
    }

    func bind(_ sender: AgentMessageSender, to paneId: PaneId? = nil) async throws {
        guard case .session(_, _, let generation) = sender else { return }
        let target = paneId ?? self.paneId
        try await databasePool.write { database in
            try database.execute(
                sql:
                    "INSERT INTO test_pane_context_binding VALUES (?, ?) ON CONFLICT(pane_id) DO UPDATE SET generation = excluded.generation",
                arguments: [target.uuidString, generation.uuidString]
            )
        }
    }

    func removeFiles() throws {
        try databasePool.close()
        try FileManager.default.removeItem(at: rootDirectory)
    }

    func sendCreated(_ request: PaneMessageSendRequest, to service: PaneContextService) async throws {
        try #require(await service.send(request) == .created(request.messageId))
    }
}

func withPaneContextService<Output: Sendable>(
    _ operation: @Sendable (PaneContextServiceFixture, PaneContextService) async throws -> Output
) async throws -> Output {
    let fixture = try PaneContextServiceFixture()
    let service = fixture.makeService()
    do {
        let output = try await operation(fixture, service)
        await service.stop()
        try fixture.removeFiles()
        return output
    } catch {
        await service.stop()
        try? fixture.removeFiles()
        throw error
    }
}

final class PaneContextTestTime: Sendable {
    private let clock: TestPushClock
    private let origin: TestPushClock.Instant
    private let offset = Mutex<TimeInterval>(0)

    init(clock: TestPushClock) {
        self.clock = clock
        origin = clock.now
    }

    var now: Date {
        let elapsed = origin.duration(to: clock.now).components
        return Date(timeIntervalSince1970: 1_800_000_000 + Double(elapsed.seconds) + offset.withLock { $0 })
    }

    func shiftWallTime(by seconds: TimeInterval) {
        offset.withLock { $0 += seconds }
    }
}

final class TestPaneContextMembership: PaneContextMembershipReading, Sendable {
    private let views = Mutex<[PaneId: [PaneId]]>([:])

    func sources(for paneId: PaneId) -> [PaneId]? {
        views.withLock { $0[paneId] }
    }

    func addPane(_ paneId: PaneId) {
        views.withLock { $0[paneId] = [paneId] }
    }

    func setDrawers(_ drawers: [PaneId], for owner: PaneId) {
        views.withLock { current in
            current[owner] = [owner] + drawers
            for drawer in drawers { current[drawer] = [drawer] }
        }
    }

    func removePane(_ paneId: PaneId) {
        _ = views.withLock { $0.removeValue(forKey: paneId) }
    }
}

actor HeldPaneContextSQLiteAccess: PaneContextSQLiteAccess {
    let databasePool: DatabasePool
    private var beforeNextWrite: HeldStep<Void>?
    private var afterNextWrite: HeldStep<Void>?
    private var operations = 0

    init(databasePool: DatabasePool) {
        self.databasePool = databasePool
    }

    func read<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        operations += 1
        return try await databasePool.read(operation)
    }

    func write<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        operations += 1
        let before = beforeNextWrite
        let after = afterNextWrite
        beforeNextWrite = nil
        afterNextWrite = nil
        try await before?.arrive(())
        let output = try await databasePool.write(operation)
        try await after?.arrive(())
        return output
    }

    func holdNextWrite(_ step: HeldStep<Void>) {
        beforeNextWrite = step
    }

    func observeNextCommit(_ step: HeldStep<Void>) {
        afterNextWrite = step
    }

    func operationCount() -> Int { operations }
}

func withHeldPaneContextWrite<Output: Sendable>(
    fixture: PaneContextServiceFixture,
    name: String,
    operation: @escaping @Sendable () async -> Output,
    whileHeld: @Sendable () async throws -> Void
) async throws -> Output {
    let held = HeldStep<Void>(name, cancellation: .holdThroughCancellation)
    await fixture.sqliteAccess.holdNextWrite(held)
    let task = Task { await operation() }
    do {
        try await held.firstArrival()
        try await whileHeld()
        held.release()
        return await task.value
    } catch {
        held.retire()
        _ = await task.value
        throw error
    }
}
