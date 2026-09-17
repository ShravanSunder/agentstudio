import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioSessions
import Darwin
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

    /// The CLI already answered the model "Report queued." A pane that has not
    /// bound yet may still bind, so the line waits rather than disappearing.
    @Test("a late deliberate report on a pane that never bound is retained until that pane binds")
    func lateDeliberateReportWithoutAnyBindingIsRetained() async throws {
        // Arrange
        try await withPaneReportSpoolDrainHarness { harness in
            let paneId = UUIDv7.generate()
            let lines = [try harness.reportLine(kind: .needsYou, explanation: "approve the plan")]
            try harness.writeSpoolFile(paneId: paneId, lines: lines)
            let expectedByteCount = try harness.spoolFileByteCount(paneId: paneId)

            // Act
            let beforeBinding = await harness.drain()

            // Assert
            #expect(beforeBinding.retainedFileCount == 1)
            #expect(beforeBinding.rejectedLineCount == 0)
            #expect(beforeBinding.admittedLineCount == 0)
            #expect(beforeBinding.truncatedFileCount == 0)
            #expect(try harness.spoolFileByteCount(paneId: paneId) == expectedByteCount)
            #expect(try harness.spoolFileLines(paneId: paneId) == lines)

            // Act
            try await harness.bindPane(paneId: paneId)
            let afterBinding = await harness.drain()

            // Assert
            #expect(afterBinding.admittedLineCount == 1)
            #expect(afterBinding.retainedFileCount == 0)
            #expect(afterBinding.truncatedFileCount == 1)
            #expect(try harness.spoolFileByteCount(paneId: paneId) == 0)
            #expect(try await harness.snapshot(paneId: paneId).currentAttention.count == 1)
        }
    }

    /// The wire frame decoder drops everything it still holds when one frame is
    /// over the ceiling. Reusing it here would wedge a pane's whole file behind
    /// a line that can never be admitted.
    @Test("an over-limit line is counted as malformed while its neighbour still drains")
    func overLimitLineIsSkippedAndTheFileStillEmpties() async throws {
        // Arrange
        try await withPaneReportSpoolDrainHarness { harness in
            let paneId = UUIDv7.generate()
            let oversized = try harness.messageLine(
                text: String(repeating: "x", count: AppPolicies.IPC.spoolDrainMaximumLineBytes))
            try harness.writeSpoolFile(
                paneId: paneId,
                lines: [oversized, try harness.messageLine(text: "survivor")]
            )

            // Act
            let report = await harness.drain()

            // Assert
            #expect(report.malformedLineCount == 1)
            #expect(report.admittedLineCount == 1)
            #expect(report.retainedFileCount == 0)
            #expect(report.truncatedFileCount == 1)
            #expect(try harness.spoolFileByteCount(paneId: paneId) == 0)
            #expect(try await harness.snapshot(paneId: paneId).messages.map(\.text) == ["survivor"])
        }
    }

    /// `flock(LOCK_EX)` waits for as long as the pane's own CLI holds the file.
    /// If that syscall ran on the actor's executor, nothing else the spool owns
    /// could run for that whole time.
    @Test(
        "a drain waiting on another writer's lock leaves the spool actor answering",
        .timeLimit(.minutes(1))
    )
    func aLockedFileDoesNotParkTheActor() async throws {
        // Arrange: another process holds the append lock this drain must wait for.
        try await withPaneReportSpoolDrainHarness { harness in
            let paneId = UUIDv7.generate()
            try harness.writeSpoolFile(
                paneId: paneId, lines: [try harness.messageLine(text: "behind a lock")])
            let heldLock = try harness.holdExclusiveLock(paneId: paneId)
            let idleDirectory = try harness.makeIdleSpoolDirectory()

            // Act
            let blockedDrain = Task { await harness.drain() }
            for _ in 0..<100 { await Task.yield() }
            let idleReport = await harness.drain(in: idleDirectory)

            // Assert
            #expect(idleReport.hasWork == false)
            heldLock.release()
            let unblocked = await blockedDrain.value
            #expect(unblocked.admittedLineCount == 1)
            #expect(unblocked.truncatedFileCount == 1)
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

    @Test("a partial drain leaves only the lines that still have to be retried")
    func partialDrainRewritesRetainedLines() async throws {
        // Arrange: one line that admits and one that cannot until the pane binds.
        try await withPaneReportSpoolDrainHarness { harness in
            let paneId = UUIDv7.generate()
            let messageLine = try harness.messageLine(text: "deploy finished")
            let needsYouLine = try harness.reportLine(kind: .needsYou, explanation: "approve the plan")
            try harness.writeSpoolFile(paneId: paneId, lines: [messageLine, needsYouLine])

            // Act
            let report = await harness.drain()

            // Assert
            #expect(report.admittedLineCount == 1)
            #expect(report.retainedFileCount == 1)
            #expect(report.truncatedFileCount == 0)
            // Keeping the admitted line would re-read and re-dedupe it on every
            // launch, without bound.
            #expect(try harness.spoolFileLines(paneId: paneId) == [needsYouLine])
            #expect(try await harness.snapshot(paneId: paneId).messages.count == 1)
        }
    }

    /// Both the drain and a pane's CLI end up waiting on the same lock, and
    /// whichever wins leaves the same file: if the append lands first the drain
    /// retains it, and if the rewrite lands first the append follows it. The
    /// rewrite therefore cannot swallow a line, which renaming a replacement
    /// over the path would, because the writer opens before it blocks in
    /// `flock` and would be left appending to an unlinked inode.
    @Test("a concurrent append during a partial drain is not lost")
    func concurrentAppendDuringPartialDrainIsNotLost() async throws {
        // Arrange
        try await withPaneReportSpoolDrainHarness { harness in
            let paneId = UUIDv7.generate()
            let messageLine = try harness.messageLine(text: "deploy finished")
            let needsYouLine = try harness.reportLine(kind: .needsYou, explanation: "approve the plan")
            let appendedLine = try harness.reportLine(kind: .needsYou, explanation: "second approval")
            try harness.writeSpoolFile(paneId: paneId, lines: [messageLine, needsYouLine])
            let spoolFilePath = harness.spoolFileURL(paneId: paneId).path
            let heldLock = try harness.holdExclusiveLock(paneId: paneId)

            // Act: both contenders block on the held lock, then race for it.
            // swiftlint:disable:next no_task_detached
            let writer = Task.detached {
                appendSpoolLineUnderLock(appendedLine, atPath: spoolFilePath)
            }
            async let drained = harness.drain()
            heldLock.release()
            let report = await drained
            let appended = await writer.value

            // Assert
            #expect(appended)
            #expect(report.retainedFileCount == 1)
            #expect(try harness.spoolFileLines(paneId: paneId) == [needsYouLine, appendedLine])
        }
    }
}

/// Appends exactly the way the pane CLI does: open the path, take the exclusive
/// lock, append, synchronize, release.
private func appendSpoolLineUnderLock(_ line: String, atPath path: String) -> Bool {
    let descriptor = open(path, O_WRONLY | O_APPEND)
    guard descriptor >= 0 else { return false }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { return false }
    defer { flock(descriptor, LOCK_UN) }
    let bytes = Array("\(line)\n".utf8)
    var writtenCount = 0
    while writtenCount < bytes.count {
        let result = bytes.withUnsafeBytes { pointer -> Int in
            guard let baseAddress = pointer.baseAddress else { return -1 }
            return write(descriptor, baseAddress.advanced(by: writtenCount), bytes.count - writtenCount)
        }
        if result < 0 {
            if errno == EINTR { continue }
            return false
        }
        writtenCount += result
    }
    return fsync(descriptor) == 0
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

    func drain(in directory: URL) async -> PaneReportSpool.DrainReport {
        await spool.drain(spoolDirectory: directory)
    }

    /// A second spool directory with nothing in it, so a drain of it can only be
    /// slow if the actor itself is parked.
    func makeIdleSpoolDirectory() throws -> URL {
        let directory = rootDirectory.appending(path: "ipc/spool/idle")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    /// Takes the same exclusive lock a pane's CLI takes to append, on a separate
    /// open file description, so the drain's own `flock` really has to wait.
    func holdExclusiveLock(paneId: UUID) throws -> HeldSpoolLock {
        let descriptor = open(spoolFileURL(paneId: paneId).path, O_RDWR)
        guard descriptor >= 0, flock(descriptor, LOCK_EX) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            throw PaneReportSpoolDrainHarnessError.spoolLockUnavailable
        }
        return HeldSpoolLock(descriptor: descriptor)
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

    func spoolFileURL(paneId: UUID) -> URL {
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
    case spoolLockUnavailable
}

/// An exclusive `flock` the test holds until it says otherwise.
@MainActor
private final class HeldSpoolLock {
    private var descriptor: Int32?

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    func release() {
        guard let descriptor else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        self.descriptor = nil
    }
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
