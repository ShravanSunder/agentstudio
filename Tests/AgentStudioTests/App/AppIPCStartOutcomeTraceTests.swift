import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

/// Agent IPC v2 R-25 keeps optional IPC unavailable, without retry, when its
/// release edges or optional work fail. These cases prove each outcome is
/// explicit: one `app.ipc.start` record saying started, or unavailable and why.
@MainActor
@Suite("App IPC start outcome trace", .serialized)
struct AppIPCStartOutcomeTraceTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("a published first frame runs initialization and reports no unavailability")
    func publishedFirstFrameInitializes() async {
        let windowLifecycleStore = WindowLifecycleAtom(deferralDelay: NeverElapsingDelay().delay)
        windowLifecycleStore.recordFirstInteractiveFramePublished(source: .presented)
        let initialization = InitializationCount()

        let unavailability = await AppIPCDeferredInitialization.run(windowLifecycleStore: windowLifecycleStore) {
            initialization.increment()
        }

        #expect(unavailability == nil)
        #expect(initialization.count == 1)
    }

    @Test("a first-frame fallback timeout skips initialization and reports first_frame_timeout")
    func fallbackTimeoutSkipsInitialization() async {
        // The deferral ceiling elapses at once: the frame never arrives in time.
        let windowLifecycleStore = WindowLifecycleAtom(deferralDelay: AsyncDelay { _ in })
        let initialization = InitializationCount()

        let unavailability = await AppIPCDeferredInitialization.run(windowLifecycleStore: windowLifecycleStore) {
            initialization.increment()
        }

        #expect(unavailability == .firstFrameTimeout)
        #expect(initialization.isEmpty)
    }

    @Test("a cancelled first-frame wait skips initialization and reports first_frame_cancelled")
    func cancelledWaitSkipsInitialization() async {
        let delay = NeverElapsingDelay()
        let windowLifecycleStore = WindowLifecycleAtom(deferralDelay: delay.delay)
        let initialization = InitializationCount()
        let task = Task { @MainActor in
            await AppIPCDeferredInitialization.run(windowLifecycleStore: windowLifecycleStore) {
                initialization.increment()
            }
        }
        await delay.waitUntilEntered()

        task.cancel()

        #expect(await task.value == .firstFrameCancelled)
        #expect(initialization.isEmpty)
    }

    @Test("scheduled initialization records a first-frame timeout as app.ipc.start unavailable")
    func scheduledTimeoutIsRecorded() async throws {
        let trace = StartupTraceCapture()
        let appDelegate = AppDelegate()
        appDelegate.startupTraceRecorder = trace.recorder
        appDelegate.windowLifecycleStore = WindowLifecycleAtom(deferralDelay: AsyncDelay { _ in })

        appDelegate.scheduleAppIPCInitialization()
        let initializationTask = try #require(appDelegate.appIPCInitializationTask)
        await initializationTask.value

        #expect(try await trace.ipcStartRecords() == [.init(outcome: "unavailable", reason: "first_frame_timeout")])
        #expect(appDelegate.appIPCServer == nil)
        appDelegate.stopAppIPCServer()
    }

    @Test("starting without local SQLite records local_store_unavailable")
    func missingLocalStoreIsRecorded() async throws {
        let trace = StartupTraceCapture()
        let appDelegate = AppDelegate()
        appDelegate.startupTraceRecorder = trace.recorder

        await appDelegate.startAppIPCServer()

        #expect(try await trace.ipcStartRecords() == [.init(outcome: "unavailable", reason: "local_store_unavailable")])
    }

    @Test("starting with an unavailable optional local schema records optional_schema_unavailable")
    func unavailableOptionalSchemaIsRecorded() async throws {
        let trace = StartupTraceCapture()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.sqlite.ipc-start-outcome")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        let appDelegate = AppDelegate()
        appDelegate.startupTraceRecorder = trace.recorder
        appDelegate.workspaceSQLiteDatastore = WorkspaceSQLiteDatastoreActor(
            preparedCoreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            preparationReceipt: .init(
                core: .uninitialized,
                local: .unavailable(
                    WorkspaceSQLiteDatastoreFailure(
                        WorkspaceSQLiteDatastoreError.applicationLocalRepositoryUnavailable))),
            preparedApplicationLocalRepository: nil
        )

        await appDelegate.startAppIPCServer()

        #expect(
            try await trace.ipcStartRecords() == [.init(outcome: "unavailable", reason: "optional_schema_unavailable")])
        #expect(appDelegate.appIPCServer == nil)
    }

    @Test("a started server records app.ipc.start started")
    func startedServerIsRecorded() async throws {
        let trace = StartupTraceCapture()
        let windowLifecycleStore = WindowLifecycleAtom()
        windowLifecycleStore.recordFirstInteractiveFramePublished(source: .presented)
        let harness = try makeServerCapableAppIPCTestHarness(windowLifecycleStore: windowLifecycleStore)
        harness.appDelegate.startupTraceRecorder = trace.recorder
        do {
            harness.appDelegate.scheduleAppIPCInitialization()
            let initializationTask = try #require(harness.appDelegate.appIPCInitializationTask)
            await initializationTask.value

            #expect(harness.appDelegate.appIPCServer != nil)
            #expect(try await trace.ipcStartRecords() == [.init(outcome: "started", reason: nil)])
        } catch {
            await harness.shutdown()
            throw error
        }
        await harness.shutdown()
    }
}

/// Collects `app.startup` records in a JSONL file this test owns.
@MainActor
private final class StartupTraceCapture {
    struct IPCStartRecord: Equatable {
        let outcome: String?
        let reason: String?
    }

    let recorder: AgentStudioStartupTraceRecorder
    private let runtime: AgentStudioTraceRuntime
    private let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "ipc-start-outcome-\(UUIDv7.generate().uuidString)")
        runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": directory.path,
                "AGENTSTUDIO_TRACE_TAGS": "app.startup",
            ]),
            processIdentifier: 4242,
            timeUnixNano: { 1 }
        )
        recorder = AgentStudioStartupTraceRecorder(traceRuntime: runtime)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func ipcStartRecords() async throws -> [IPCStartRecord] {
        try await recorder.drain()
        guard let fileURL = runtime.outputFileURL,
            let contents = try? String(contentsOf: fileURL, encoding: .utf8)
        else { return [] }
        return try contents.split(separator: "\n").compactMap { line in
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            guard object?["body"] as? String == "app.ipc.start" else { return nil }
            let attributes = object?["attributes"] as? [String: Any]
            return IPCStartRecord(
                outcome: attributes?["agentstudio.app.startup.outcome"] as? String,
                reason: attributes?["agentstudio.app.ipc.start.reason"] as? String
            )
        }
    }
}

@MainActor
private final class InitializationCount {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// A deferral ceiling that never elapses; it only ends when its task is
/// cancelled. Announces entry so a test can cancel a wait that is in place.
private final class NeverElapsingDelay: @unchecked Sendable {
    private let entered: AsyncStream<Void>
    private let enteredContinuation: AsyncStream<Void>.Continuation

    init() {
        (entered, enteredContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    var delay: AsyncDelay {
        AsyncDelay { [enteredContinuation] _ in
            enteredContinuation.yield(())
            let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
            await withTaskCancellationHandler {
                for await _ in stream {}
            } onCancel: {
                continuation.finish()
            }
            try Task.checkCancellation()
        }
    }

    func waitUntilEntered() async {
        var iterator = entered.makeAsyncIterator()
        _ = await iterator.next()
    }
}
