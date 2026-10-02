import AgentStudioInfrastructure
import AgentStudioTestHarness
import Darwin
import Foundation
import GRDB
import Synchronization
import Testing

@testable import AgentStudioCore
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

struct ZmxForegroundFixture: Sendable {
    let paneId: UUID
    let sessionId: ZmxSessionID
    let generationId: UUID
    let repository: SQLitePaneForegroundObservationRepository
    let observer: PaneForegroundObserver<TestPushClock>
    let clock: TestPushClock
    let probe: DarwinTerminalForegroundProbe
    let probeGate: ZmxForegroundProbeGate
    private let recordingWatcher: ZmxForegroundRecordingExitWatcher
    let facts: FactRecorder<ForegroundObserverFactScope, ForegroundObserverFact>
    let inputWriter: ForegroundFIFOHandle
    let agentOutputReader: ForegroundFIFOHandle
    let shellReadyPath: String
    let successorInputPath: String?
    let successorOutputPath: String?
    let successorHandles: ForegroundFIFOGroup
    let identity: Data
    let harness: ZmxTestHarness
    private let ownership: ResumeEvidenceZmxEnvironment?

    static func make(
        harness: ZmxTestHarness, backend: ZmxBackend, provider: String, successorProgram: Bool = false,
        bindingContext: ZmxForegroundBindingContext? = nil, exitWatcher: (any ProcessExitWatching)? = nil
    )
        async throws -> Self
    {
        let root = URL(fileURLWithPath: harness.zmxDir)
        let sessionId = ZmxSessionID.generateUUIDv7()
        let paneId = bindingContext?.paneID ?? UUIDv7.generate()
        let generationId = bindingContext?.generationID ?? UUIDv7.generate()
        let launchId = UUIDv7.generate()
        let binary = root.appending(path: provider)
        let inputPath = root.appending(path: "agent-input-\(sessionId.rawValue)").path
        let outputPath = root.appending(path: "agent-output-\(sessionId.rawValue)").path
        let shellPath = root.appending(path: "shell-ready-\(sessionId.rawValue)").path
        let successorInput = successorProgram ? root.appending(path: "other-input-\(sessionId.rawValue)").path : nil
        let successorOutput = successorProgram ? root.appending(path: "other-output-\(sessionId.rawValue)").path : nil
        // The probe reads argv[0], so the invocation name supplies the agent
        // identity. Keep the platform binary at its signed original location.
        if !FileManager.default.fileExists(atPath: binary.path) {
            try FileManager.default.createSymbolicLink(atPath: binary.path, withDestinationPath: "/bin/cat")
        }
        for path in [inputPath, outputPath, shellPath] {
            guard mkfifo(path, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        for path in [successorInput, successorOutput].compactMap({ $0 }) {
            guard mkfifo(path, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        let successor: String
        if let successorInput, let successorOutput {
            successor = "exec /bin/cat <\(quoteForegroundPath(successorInput)) >\(quoteForegroundPath(successorOutput))"
        } else {
            successor = "printf shell-ready >\(quoteForegroundPath(shellPath)); exec /bin/sh -i"
        }
        // Evidence-table job-control cases require an explicit interactive monitor owner.
        let jobControl = bindingContext == nil ? "" : "set -m; "
        let command =
            "\(jobControl)\(quoteForegroundPath(binary.path)) <\(quoteForegroundPath(inputPath)) >\(quoteForegroundPath(outputPath)); \(successor)"
        let zmxPath = try #require(harness.zmxPath)
        if let ownership = bindingContext?.ownership {
            try await ownership.launchSession(sessionId, arguments: ["/bin/sh", "-i", "-c", command])
            // The FIFO round trip below proves the actual child is ready, not
            // merely that its session socket or terminal leader has appeared.
        } else {
            _ = try await harness.spawnZmxSession(
                zmxPath: zmxPath, sessionId: sessionId.rawValue,
                commandArgs: ["/bin/sh", "-i", "-c", command])
        }
        let writer = ForegroundFIFOHandle(try await openForegroundFIFO(path: inputPath, flags: O_WRONLY))
        var reader: ForegroundFIFOHandle?
        do {
            let outputReader = ForegroundFIFOHandle(try await openForegroundFIFO(path: outputPath, flags: O_RDONLY))
            reader = outputReader
            let marker = Data("agent-ready".utf8)
            try await writeForegroundFIFO(descriptor: writer.descriptor(), bytes: marker)
            let readyBytes = try await readForegroundBytes(
                descriptor: outputReader.descriptor(), byteCount: marker.count)
            #expect(readyBytes == marker)
            let observed = try await backend.observeSessionIdentity(sessionId)
            let identity = try #require(observed)
            let bootId = try ZmxSessionIdentity.decode(identity).bootID
            let database =
                try bindingContext?.database
                ?? SQLiteDatabaseFactory.makeInMemoryQueue(label: "zmx-foreground-observation")
            if bindingContext == nil {
                try WorkspaceLocalMigrations.migrate(database)
                try await seedZmxForegroundBinding(database: database, paneId: paneId, generationId: generationId)
            }
            let sessions = [paneId: sessionId]
            let repository = SQLitePaneForegroundObservationRepository(
                access: TestForegroundSQLiteAccess(databaseQueue: database), observerLaunchId: launchId,
                paneSessions: { sessions })
            let source = LocalFactSource(
                vocabulary: FactVocabulary<ForegroundObserverFactScope, ForegroundObserverFact>(
                    describeScope: { "\($0.paneId)/\($0.operationId)" }, describeFact: { String(describing: $0) },
                    isClosing: { _, fact in if case .closed = fact { true } else { false } }))
            let facts = try source.attach()
            let probe = DarwinTerminalForegroundProbe(sessionDirectory: harness.zmxDir, bootId: bootId)
            let probeGate = ZmxForegroundProbeGate(probe: probe)
            let recordingWatcher = ZmxForegroundRecordingExitWatcher(
                wrapping: exitWatcher ?? DarwinProcessExitWatcher())
            let clock = TestPushClock()
            let observer = PaneForegroundObserver(
                clock: clock,
                policy: .init(lookSettleDelay: .seconds(5), lookMaxDelay: .seconds(60), quitLookDeadline: .seconds(1)),
                repository: repository, probe: probeGate, exitWatcher: recordingWatcher,
                observerLaunchId: launchId,
                factSink: source.sink)
            return Self(
                paneId: paneId, sessionId: sessionId, generationId: generationId, repository: repository,
                observer: observer, clock: clock, probe: probe, probeGate: probeGate,
                recordingWatcher: recordingWatcher,
                facts: facts, inputWriter: writer,
                agentOutputReader: outputReader,
                shellReadyPath: shellPath, successorInputPath: successorInput, successorOutputPath: successorOutput,
                successorHandles: ForegroundFIFOGroup(), identity: identity, harness: harness,
                ownership: bindingContext?.ownership)
        } catch {
            writer.closeOnce()
            reader?.closeOnce()
            // One snapshot, only on setup failure: distinguish a broken FIFO
            // transfer from the real child failing to exec or exiting early.
            let terminalOutput = try? await harness.sessionHistory(sessionId: sessionId.rawValue)
            throw ForegroundFixtureSetupFailure(
                underlying: String(describing: error), terminalOutput: terminalOutput)
        }
    }

    func initialLook() async throws -> UUID {
        await observer.note(.bindingChanged, pane: paneId)
        let pane = paneId
        let demand = try await facts.expectNextOperation(
            matching: { $0.paneId == pane }, opening: { $0 == .scheduled }, "real foreground demand")
        try await facts.expectNext(in: demand, .scheduled)
        try await facts.expectNext(in: demand, .closed(.scheduled))
        let look = try await nextLook(sequence: 1)
        try await facts.expectNext(in: look, .observation(.admitted))
        let registered = try await facts.expectNext(
            in: look, where: { if case .watchRegistered = $0 { true } else { false } }, "real agent watch")
        try await facts.expectNext(in: look, .closed(.looked))
        guard case .watchRegistered(let watchId) = registered else { throw POSIXError(.EPROTO) }
        return watchId
    }

    func nextLook(sequence: UInt64) async throws -> ForegroundObserverFactScope {
        let pane = paneId
        let watches = recordingWatcher
        let scope = try await facts.expectNextOperation(
            matching: { $0.paneId == pane && !watches.isWatchOperation($0.operationId) },
            opening: { $0 == .snapshotStarted(sequence: sequence) }, "real look \(sequence)")
        try await facts.expectNext(in: scope, .snapshotStarted(sequence: sequence))
        return scope
    }

    func letAgentExitIntoShell() async throws {
        inputWriter.closeOnce()
        let reader = try await openForegroundFIFO(path: shellReadyPath, flags: O_RDONLY)
        defer { close(reader) }
        let marker = Data("shell-ready".utf8)
        let readyBytes = try await readForegroundBytes(descriptor: reader, byteCount: marker.count)
        #expect(readyBytes == marker)
    }

    /// SIGSTOP is delivered only to the positively identified child owned by this session.
    func suspendAgentIntoShell(background: Bool) async throws {
        let snapshots = try await probe.probeForeground(of: [sessionId])
        let agent = try #require(snapshots[sessionId]?.foregroundProcess)
        try #require(DarwinColdStartObserverSyscalls().leaderState(of: agent) == .sameIncarnationAlive)
        ownership?.retainJobControlChild(agent)
        try #require(Darwin.kill(agent.pid, SIGSTOP) == 0)
        let reader = try await openForegroundFIFO(path: shellReadyPath, flags: O_RDONLY)
        defer { close(reader) }
        let bytes = try await readForegroundBytes(descriptor: reader, byteCount: Data("shell-ready".utf8).count)
        #expect(bytes == Data("shell-ready".utf8))
        let status = try await withoutBlockingCooperativePool {
            var information = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(agent.pid, PROC_PIDTBSDINFO, 0, &information, size) == size else {
                throw POSIXError(.ESRCH)
            }
            return information.pbi_status
        }
        #expect(status == UInt32(SSTOP))
        if background {
            try #require(DarwinColdStartObserverSyscalls().leaderState(of: agent) == .sameIncarnationAlive)
            try #require(Darwin.kill(agent.pid, SIGCONT) == 0)
            let marker = Data("background-ready".utf8)
            try await writeForegroundFIFO(descriptor: inputWriter.descriptor(), bytes: marker)
            let echoed = try await readForegroundBytes(
                descriptor: agentOutputReader.descriptor(), byteCount: marker.count)
            #expect(echoed == marker)
        }
    }

    func letAnotherProgramTakeForeground() async throws {
        let inputPath = try #require(successorInputPath)
        let outputPath = try #require(successorOutputPath)
        inputWriter.closeOnce()
        let writer = ForegroundFIFOHandle(try await openForegroundFIFO(path: inputPath, flags: O_WRONLY))
        successorHandles.add(writer)
        let reader = ForegroundFIFOHandle(try await openForegroundFIFO(path: outputPath, flags: O_RDONLY))
        successorHandles.add(reader)
        let marker = Data("other-ready".utf8)
        try await writeForegroundFIFO(descriptor: writer.descriptor(), bytes: marker)
        let readyBytes = try await readForegroundBytes(descriptor: reader.descriptor(), byteCount: marker.count)
        #expect(readyBytes == marker)
    }

    func killOwnedSession() async throws {
        if let ownership {
            try await ownership.killSession(sessionId)
            return
        }
        let zmxPath = try #require(harness.zmxPath)
        var environment = ProcessInfo.processInfo.environment
        environment["ZMX_DIR"] = harness.zmxDir
        let output = try await runProcessToExit(
            executableURL: URL(fileURLWithPath: zmxPath),
            arguments: ["kill", sessionId.rawValue], environment: environment)
        #expect(output.terminationStatus == 0)
    }

    func closeFixture() async throws {
        await observer.shutdown()
        inputWriter.closeOnce()
        agentOutputReader.closeOnce()
        successorHandles.closeAll()
        try await facts.finish()
    }
}

/// Kept in this executable-test target: the Terminal unit-test wrapper is in
/// another module. Record IDs before native delivery without sharing test targets.
private final class ZmxForegroundRecordingExitWatcher: ProcessExitWatching, Sendable {
    private let wrapped: any ProcessExitWatching
    private let watchIds = Mutex<Set<UUID>>([])

    init(wrapping wrapped: any ProcessExitWatching) { self.wrapped = wrapped }

    func watchExit(of process: ProcessIncarnation, watchId: UUID) -> ProcessExitWatch {
        watchIds.withLock { _ = $0.insert(watchId) }
        return wrapped.watchExit(of: process, watchId: watchId)
    }

    func isWatchOperation(_ operationId: UUID) -> Bool { watchIds.withLock { $0.contains(operationId) } }
}

final class ForegroundFIFOGroup: Sendable {
    private let handles = Mutex<[ForegroundFIFOHandle]>([])
    func add(_ handle: ForegroundFIFOHandle) { handles.withLock { $0.append(handle) } }
    func closeAll() {
        let owned = handles.withLock { handles in
            defer { handles.removeAll() }
            return handles
        }
        for handle in owned { handle.closeOnce() }
    }
}

final class ForegroundFIFOHandle: Sendable {
    private let state: Mutex<Int32?>
    init(_ descriptor: Int32) { state = Mutex(descriptor) }
    func descriptor() throws -> Int32 {
        try state.withLock { descriptor in
            guard let descriptor else { throw POSIXError(.EBADF) }
            return descriptor
        }
    }
    func closeOnce() {
        let descriptor = state.withLock { descriptor in
            defer { descriptor = nil }
            return descriptor
        }
        if let descriptor { close(descriptor) }
    }
}

actor ZmxForegroundProbeGate: TerminalForegroundProbing {
    private let probe: DarwinTerminalForegroundProbe
    private var nextHold: HeldStep<[ZmxSessionID]>?
    init(probe: DarwinTerminalForegroundProbe) { self.probe = probe }
    func holdNext(_ step: HeldStep<[ZmxSessionID]>) { nextHold = step }
    func probeForeground(of sessions: [ZmxSessionID]) async throws -> [ZmxSessionID: ForegroundSnapshot] {
        let hold = nextHold
        nextHold = nil
        if let hold { try await hold.arrive(sessions) }
        return try await probe.probeForeground(of: sessions)
    }
}

private func quoteForegroundPath(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func openForegroundFIFO(path: String, flags: Int32) async throws -> Int32 {
    try await withoutBlockingCooperativePool {
        let descriptor = open(path, flags)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return descriptor
    }
}

private struct ForegroundFixtureSetupFailure: Error, CustomStringConvertible {
    let underlying: String
    let terminalOutput: String?
    var description: String {
        "foreground fixture setup: \(underlying); terminal output: \(terminalOutput ?? "unavailable")"
    }
}

private enum ForegroundFIFOTransferFailure: Error {
    case zeroProgressWrite(bytesWritten: Int, expectedBytes: Int)
    case prematureEOF(bytesRead: Int, expectedBytes: Int)
}

private func writeForegroundFIFO(descriptor: Int32, bytes: Data) async throws {
    try await withoutBlockingCooperativePool {
        var written = 0
        while written < bytes.count {
            let count = bytes.withUnsafeBytes { buffer in
                write(descriptor, buffer.baseAddress?.advanced(by: written), bytes.count - written)
            }
            if count < 0 {
                let failure = errno
                if failure == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
            }
            guard count > 0 else {
                throw ForegroundFIFOTransferFailure.zeroProgressWrite(bytesWritten: written, expectedBytes: bytes.count)
            }
            written += count
        }
    }
}

private func readForegroundBytes(descriptor: Int32, byteCount: Int) async throws -> Data {
    try await withoutBlockingCooperativePool {
        var result = Data()
        while result.count < byteCount {
            var bytes = [UInt8](repeating: 0, count: byteCount - result.count)
            let count = bytes.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                let failure = errno
                if failure == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
            }
            guard count > 0 else {
                throw ForegroundFIFOTransferFailure.prematureEOF(bytesRead: result.count, expectedBytes: byteCount)
            }
            result.append(contentsOf: bytes.prefix(count))
        }
        return result
    }
}

private func seedZmxForegroundBinding(database: DatabaseQueue, paneId: UUID, generationId: UUID) async throws {
    try await database.write { connection in
        let conversationId = UUIDv7.generate().uuidString
        try connection.execute(
            sql: "INSERT INTO sessions_conversation VALUES (?, 'claude-code', ?, 1, 1)",
            arguments: [conversationId, UUIDv7.generate().uuidString])
        try connection.execute(
            sql: """
                INSERT INTO sessions_operation(operation_scope,correlation_id,operation_kind,semantic_fingerprint,outcome_kind,created_at)
                VALUES ('real-proof',?,'bind','proof','binding',1)
                """, arguments: [UUIDv7.generate().uuidString])
        try connection.execute(
            sql: """
                INSERT INTO sessions_pane_binding(binding_generation_id,pane_id,conversation_id,source_generation_id,
                    origin,status,transition_occurrence_id,started_at,ended_at,committed_revision)
                VALUES (?,?,?,?,'reported','active',?,1,NULL,?)
                """,
            arguments: [
                generationId.uuidString, paneId.uuidString, conversationId,
                UUIDv7.generate().uuidString, UUIDv7.generate().uuidString, connection.lastInsertedRowID,
            ])
    }
}

struct TestForegroundSQLiteAccess: ForegroundObservationSQLiteAccess {
    let databaseQueue: DatabaseQueue
    func read<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        try await databaseQueue.read(operation)
    }
    func write<Output: Sendable>(_ operation: @Sendable (Database) throws -> Output) async throws -> Output {
        try await databaseQueue.write(operation)
    }
}

/// The evidence table shares the real Sessions writer and admitted generation with the observer.
struct ZmxForegroundBindingContext: Sendable {
    let paneID: UUID
    let generationID: UUID
    let database: DatabaseQueue
    let ownership: ResumeEvidenceZmxEnvironment
}
