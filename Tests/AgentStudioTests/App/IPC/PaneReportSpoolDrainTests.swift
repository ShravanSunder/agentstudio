import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioSessions
import Foundation
import GRDB
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

/// The drain is proved against a real migrated Sessions database, real
/// ingestion and the same App adapter the live IPC server uses, so nothing here
/// mocks the admission the spooled line has to survive.
@MainActor
@Suite("Pane report spool drain", .serialized)
struct PaneReportSpoolDrainTests {
    @Test("one spooled message reaches the pane as late evidence and empties the file")
    func spooledMessageIsAdmittedLateAndTruncated() async throws {
        // Arrange
        try await withPaneReportSpoolDrainHarness { harness in
            let paneId = UUIDv7.generate()
            try harness.writeSpoolFile(
                paneId: paneId,
                lines: [try harness.messageLine(text: "deploy finished")]
            )

            // Act
            let report = await harness.drain()

            // Assert
            #expect(report.admittedLineCount == 1)
            #expect(report.truncatedFileCount == 1)
            #expect(report.retainedFileCount == 0)
            #expect(try harness.spoolFileByteCount(paneId: paneId) == 0)
            let snapshot = try await harness.snapshot(paneId: paneId)
            #expect(snapshot.messages.count == 1)
            #expect(snapshot.messages.first?.text == "deploy finished")
            #expect(snapshot.messages.first?.freshness == .late)
            #expect(snapshot.messages.first?.attribution == .unattributed)
        }
    }

    @Test("the same correlation twice yields one occurrence and still empties the file")
    func duplicateCorrelationIsAdmittedOnce() async throws {
        // Arrange
        try await withPaneReportSpoolDrainHarness { harness in
            let paneId = UUIDv7.generate()
            let line = try harness.messageLine(text: "duplicate", correlationId: UUIDv7.generate())
            try harness.writeSpoolFile(paneId: paneId, lines: [line, line])

            // Act
            let report = await harness.drain()

            // Assert
            #expect(report.admittedLineCount == 2)
            #expect(report.truncatedFileCount == 1)
            #expect(try harness.spoolFileByteCount(paneId: paneId) == 0)
            #expect(try await harness.snapshot(paneId: paneId).messages.count == 1)
        }
    }

    @Test("a malformed line is counted and skipped while the valid line is admitted")
    func malformedLineIsCountedAndSkipped() async throws {
        // Arrange
        try await withPaneReportSpoolDrainHarness { harness in
            let paneId = UUIDv7.generate()
            try harness.writeSpoolFile(
                paneId: paneId,
                lines: ["{\"not\":\"a json-rpc request\"}", try harness.messageLine(text: "survivor")]
            )

            // Act
            let report = await harness.drain()

            // Assert
            #expect(report.malformedLineCount == 1)
            #expect(report.admittedLineCount == 1)
            #expect(try harness.spoolFileByteCount(paneId: paneId) == 0)
            #expect(try await harness.snapshot(paneId: paneId).messages.map(\.text) == ["survivor"])
        }
    }

    @Test("a session.event line is malformed and never admitted")
    func providerEventLineIsNeverAdmitted() async throws {
        // Arrange
        try await withPaneReportSpoolDrainHarness { harness in
            let paneId = UUIDv7.generate()
            try harness.writeSpoolFile(paneId: paneId, lines: [try harness.providerEventLine()])

            // Act
            let report = await harness.drain()

            // Assert
            #expect(report.malformedLineCount == 1)
            #expect(report.admittedLineCount == 0)
            #expect(try harness.spoolFileByteCount(paneId: paneId) == 0)
            #expect(try await harness.snapshot(paneId: paneId).currentBinding == nil)
        }
    }

    @Test("a line addressed to another pane is malformed for this pane's file")
    func foreignHandleIsMalformed() async throws {
        // Arrange
        try await withPaneReportSpoolDrainHarness { harness in
            let paneId = UUIDv7.generate()
            try harness.writeSpoolFile(
                paneId: paneId,
                lines: [try harness.messageLine(text: "wrong pane", handle: UUIDv7.generate().uuidString)]
            )

            // Act
            let report = await harness.drain()

            // Assert
            #expect(report.malformedLineCount == 1)
            #expect(try await harness.snapshot(paneId: paneId).messages.isEmpty)
        }
    }

    @Test("a failing datastore retains the file intact for the next readiness")
    func datastoreFailureRetainsTheFile() async throws {
        // Arrange
        try await withPaneReportSpoolDrainHarness { harness in
            let paneId = UUIDv7.generate()
            let lines = [try harness.messageLine(text: "retry me")]
            try harness.writeSpoolFile(paneId: paneId, lines: lines)
            let expectedByteCount = try harness.spoolFileByteCount(paneId: paneId)
            await harness.failEveryWrite()

            // Act
            let report = await harness.drain()

            // Assert
            #expect(report.admittedLineCount == 0)
            #expect(report.retainedFileCount == 1)
            #expect(report.truncatedFileCount == 0)
            #expect(try harness.spoolFileByteCount(paneId: paneId) == expectedByteCount)
            #expect(try harness.spoolFileLines(paneId: paneId) == lines)
        }
    }

    @Test("a late deliberate report on a pane that never bound is a counted rejection, not a retry")
    func lateDeliberateReportWithoutAnyBindingIsRejected() async throws {
        // Arrange
        try await withPaneReportSpoolDrainHarness { harness in
            let paneId = UUIDv7.generate()
            try harness.writeSpoolFile(
                paneId: paneId,
                lines: [try harness.reportLine(kind: .needsYou, explanation: "approve the plan")]
            )

            // Act
            let report = await harness.drain()

            // Assert
            #expect(report.rejectedLineCount == 1)
            #expect(report.admittedLineCount == 0)
            #expect(report.truncatedFileCount == 1)
            #expect(try harness.spoolFileByteCount(paneId: paneId) == 0)
        }
    }

    @Test("spooled needs-you and done from before a relaunch are admitted as history")
    func spooledDeliberateReportsSurviveARelaunch() async throws {
        // Arrange: bind the pane, then end that generation the way launch does.
        try await withPaneReportSpoolDrainHarness { harness in
            let paneId = UUIDv7.generate()
            try await harness.bindPane(paneId: paneId)
            try await harness.simulateRelaunch()
            let stateAfterRelaunch = try await harness.snapshot(paneId: paneId).state
            try harness.writeSpoolFile(
                paneId: paneId,
                lines: [
                    try harness.reportLine(kind: .needsYou, explanation: "approve the plan"),
                    try harness.reportLine(kind: .done, explanation: nil),
                ]
            )

            // Act
            let report = await harness.drain()

            // Assert
            #expect(report.admittedLineCount == 2)
            #expect(report.rejectedLineCount == 0)
            #expect(report.truncatedFileCount == 1)
            #expect(try harness.spoolFileByteCount(paneId: paneId) == 0)
            let snapshot = try await harness.snapshot(paneId: paneId)
            #expect(snapshot.state == stateAfterRelaunch)
            #expect(snapshot.currentAttention.isEmpty)
            #expect(snapshot.results.count == 1)
            #expect(snapshot.results.first?.freshness == .late)
            #expect(snapshot.historicalOccurrenceIds.count == 2)
        }
    }
}

/// The harness owns a live ingestion consumer, so every case shuts it down
/// before returning rather than leaving a task behind.
@MainActor
private func withPaneReportSpoolDrainHarness(
    _ body: @MainActor (PaneReportSpoolDrainHarness) async throws -> Void
) async throws {
    let harness = try await PaneReportSpoolDrainHarness()
    do {
        try await body(harness)
    } catch {
        await harness.tearDown()
        throw error
    }
    await harness.tearDown()
}

/// A real prepared application-local database, real Sessions ingestion, the
/// live App adapter composed with late freshness, and one temporary spool
/// directory. Only the SQLite write seam can be forced to fail, so the
/// admission under test is never mocked.
@MainActor
private final class PaneReportSpoolDrainHarness {
    let spoolDirectory: URL
    private let rootDirectory: URL
    static let qualifiedProvider = IPCSessionProviderIdentity(
        identifier: "spool-drain-provider",
        version: "1.0.0",
        mode: "interactive"
    )

    private let sqliteAccess: FailableSessionsSQLiteAccess
    private let repository: SessionsRepository
    private let ingestion: SessionsIngestion
    private let admission: AgentStudioIPCSessionsAdapter
    private let spool: PaneReportSpool

    init() async throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-spool-drain-\(UUIDv7.generate().uuidString)")
        spoolDirectory = rootDirectory.appending(path: "ipc/spool/v2")
        try FileManager.default.createDirectory(
            at: spoolDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        guard case .ready = await datastore.prepareOptionalApplicationLocalSchema() else {
            throw PaneReportSpoolDrainHarnessError.optionalSchemaUnavailable
        }
        sqliteAccess = FailableSessionsSQLiteAccess(
            base: WorkspaceSessionsSQLiteAccess(datastore: datastore)
        )
        repository = SessionsRepository(sqliteAccess: sqliteAccess)
        ingestion = SessionsIngestion(
            repository: repository,
            limits: SessionsIngestionLimits(maximumPendingPerPane: 32, maximumPendingGlobal: 128),
            probe: { _ in }
        )
        admission = AgentStudioIPCSessionsAdapter(
            ingestion: ingestion,
            providerRegistry: SessionsProviderAdapterRegistry(
                profiles: [
                    SessionsProviderProfile(
                        providerIdentifier: Self.qualifiedProvider.identifier,
                        exactVersion: Self.qualifiedProvider.version,
                        operatingMode: Self.qualifiedProvider.mode,
                        qualifiedCapabilities: [.sessionStart, .sessionEnd]
                    )
                ]
            ),
            admissionFreshness: .late
        )
        spool = try PaneReportSpool(admission: admission)
    }

    func drain() async -> PaneReportSpool.DrainReport {
        await spool.drain(spoolDirectory: spoolDirectory)
    }

    func snapshot(paneId: UUID) async throws -> SessionsSnapshot {
        try await repository.snapshot(
            .pane(paneId, page: SessionsSnapshotPage(limit: 100, after: nil))
        )
    }

    func failEveryWrite() async {
        await sqliteAccess.failEveryWrite()
    }

    /// Binds the pane through the same qualified session-start admission the
    /// live IPC path uses, so the generation the spooled lines belong to is real.
    func bindPane(paneId: UUID) async throws {
        _ = try await admission.recordProviderEvent(
            paneId: paneId,
            params: IPCSessionEventParams(
                handle: paneId.uuidString,
                provider: Self.qualifiedProvider,
                event: IPCSessionEventIdentity(
                    name: .sessionStart,
                    conversationId: "conversation-\(paneId.uuidString)",
                    turnId: nil,
                    requestId: nil,
                    toolId: nil,
                    subagentId: nil,
                    occurrenceId: UUIDv7.generate()
                ),
                correlationId: UUIDv7.generate()
            )
        )
    }

    /// Launch preparation is exactly what an app relaunch runs before the drain.
    func simulateRelaunch() async throws {
        _ = try await ingestion.prepareForLaunch(at: Date())
    }

    func messageLine(
        text: String,
        handle: String = "self",
        correlationId: UUID = UUIDv7.generate()
    ) throws -> String {
        try requestLine(
            method: "session.message",
            parameters: IPCSessionMessageParams(handle: handle, text: text, correlationId: correlationId)
        )
    }

    func reportLine(
        kind: IPCSessionReportKind,
        explanation: String?,
        handle: String = "self",
        correlationId: UUID = UUIDv7.generate()
    ) throws -> String {
        try requestLine(
            method: "session.report",
            parameters: IPCSessionReportParams(
                handle: handle, kind: kind, explanation: explanation, correlationId: correlationId)
        )
    }

    func providerEventLine(handle: String = "self") throws -> String {
        try requestLine(
            method: "session.event",
            parameters: IPCSessionEventParams(
                handle: handle,
                provider: IPCSessionProviderIdentity(
                    identifier: "fixture", version: "1.0.0", mode: "interactive"),
                event: IPCSessionEventIdentity(
                    name: .sessionStart,
                    conversationId: "conversation-spooled",
                    turnId: nil,
                    requestId: nil,
                    toolId: nil,
                    subagentId: nil,
                    occurrenceId: UUIDv7.generate()
                ),
                correlationId: UUIDv7.generate()
            )
        )
    }

    func writeSpoolFile(paneId: UUID, lines: [String]) throws {
        let contents = lines.map { "\($0)\n" }.joined()
        try Data(contents.utf8).write(to: spoolFileURL(paneId: paneId))
    }

    func spoolFileByteCount(paneId: UUID) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: spoolFileURL(paneId: paneId).path)
        return (attributes[.size] as? NSNumber)?.intValue ?? -1
    }

    func spoolFileLines(paneId: UUID) throws -> [String] {
        try String(contentsOf: spoolFileURL(paneId: paneId), encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }

    func tearDown() async {
        await ingestion.finish()
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    private func spoolFileURL(paneId: UUID) -> URL {
        spoolDirectory.appendingPathComponent("\(paneId.uuidString).notifications.ndjson")
    }

    /// The line is encoded exactly as the CLI encodes a wire request, so the
    /// drain is proved against the shape it will actually meet on disk.
    private func requestLine(method: String, parameters: some Encodable) throws -> String {
        let value = try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(parameters))
        return try JSONRPCCodec.encodeRequest(
            JSONRPCClientRequest(id: .number(1), method: method, params: value)
        )
    }
}

private enum PaneReportSpoolDrainHarnessError: Error {
    case optionalSchemaUnavailable
}

private struct PaneReportSpoolDrainStorageFailure: Error {}

/// The real application-local access with one switch that makes every later
/// write fail the way an unavailable datastore does.
private actor FailableSessionsSQLiteAccess: SessionsSQLiteAccess {
    private let base: WorkspaceSessionsSQLiteAccess
    private var rejectsWrites = false

    init(base: WorkspaceSessionsSQLiteAccess) {
        self.base = base
    }

    func failEveryWrite() {
        rejectsWrites = true
    }

    func read<Output: Sendable>(
        _ operation: @Sendable (Database) throws -> Output
    ) async throws -> Output {
        try await base.read(operation)
    }

    func write<Output: Sendable>(
        _ operation: @Sendable (Database) throws -> Output
    ) async throws -> Output {
        guard !rejectsWrites else { throw PaneReportSpoolDrainStorageFailure() }
        return try await base.write(operation)
    }
}
