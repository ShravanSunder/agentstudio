import Foundation
import Observation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
final class SessionRuntimeTests {
    private func makeRuntime(
        store: WorkspaceStore? = nil,
        healthCheckInterval: TimeInterval = 1
    ) -> SessionRuntime {
        SessionRuntime(store: store, healthCheckInterval: healthCheckInterval)
    }

    private final class ObservationFlag: @unchecked Sendable {
        var fired = false
    }

    // MARK: - Status Queries

    @Test
    func test_sessionRuntime_statusUpdatesAreObservedThroughObservable() {
        let runtime = makeRuntime()
        let flag = ObservationFlag()
        withObservationTracking {
            _ = runtime.statuses
        } onChange: {
            flag.fired = true
        }

        let id = UUID()
        runtime.markRunning(id)
        #expect(flag.fired)
    }

    @Test

    func test_status_unknownPane_returnsInitializing() {
        let runtime = makeRuntime()
        let status = runtime.status(for: UUID())
        #expect(status == .initializing)
    }

    @Test

    func test_status_afterInitialize_returnsInitializing() {
        let runtime = makeRuntime()
        let id = UUID()
        runtime.initializeSession(id)
        let status = runtime.status(for: id)
        #expect(status == .initializing)
    }

    @Test

    func test_status_afterMarkRunning_returnsRunning() {
        let runtime = makeRuntime()
        let id = UUID()
        runtime.initializeSession(id)
        runtime.markRunning(id)
        let status = runtime.status(for: id)
        #expect(status == .running)
    }

    @Test

    func test_status_afterMarkExited_returnsExited() {
        let runtime = makeRuntime()
        let id = UUID()
        runtime.markRunning(id)
        runtime.markExited(id)
        let status = runtime.status(for: id)
        #expect(status == .exited)
    }

    @Test

    func test_removeSession_clearsStatus() {
        let runtime = makeRuntime()
        let id = UUID()
        runtime.markRunning(id)
        runtime.removeSession(id)
        // Should return default (initializing) since entry is gone
        let status = runtime.status(for: id)
        #expect(status == .initializing)
        #expect(!(runtime.statuses.keys.contains(id)))
    }

    // MARK: - Aggregate Queries

    @Test

    func test_runningCount_reflectsState() {
        let runtime = makeRuntime()
        let ids = (0..<5).map { _ in UUID() }
        for id in ids { runtime.markRunning(id) }
        runtime.markExited(ids[0])
        runtime.markExited(ids[1])

        let runningCount = runtime.runningCount
        #expect(runningCount == 3)
    }

    @Test

    func test_panesWithStatus_filtersCorrectly() {
        let runtime = makeRuntime()
        let runningId = UUID()
        let exitedId = UUID()
        let initId = UUID()

        runtime.markRunning(runningId)
        runtime.markExited(exitedId)
        runtime.initializeSession(initId)

        let running = runtime.panes(withStatus: .running)
        #expect(running == [runningId])

        let exited = runtime.panes(withStatus: .exited)
        #expect(exited == [exitedId])

        let initializing = runtime.panes(withStatus: .initializing)
        #expect(initializing == [initId])
    }

    // MARK: - Sync With Store

    @Test

    func test_syncWithStore_addsNewPanes() {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "runtime-test-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let runtime = makeRuntime(store: store)

        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )

        runtime.syncWithStore()

        let status = runtime.status(for: pane.id)
        #expect(status == .initializing)
        #expect(runtime.statuses.keys.contains(pane.id))

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test

    func test_syncWithStore_removesStalePanes() {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "runtime-test-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let runtime = makeRuntime(store: store)

        let staleId = UUID()
        runtime.markRunning(staleId)

        runtime.syncWithStore()

        let hasStale = runtime.statuses.keys.contains(staleId)
        #expect(!hasStale)

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Backend Registration

    @Test

    func test_registerBackend_storesCorrectly() async throws {
        let runtime = makeRuntime()
        let backend = MockSessionRuntimeBackend(provider: .zmx)
        runtime.registerBackend(backend)
        let pane = makePane(
            source: .floating(workingDirectory: nil, title: "Terminal"),
            provider: .zmx
        )

        let handle = try await runtime.startSession(pane)

        #expect(handle == "mock-handle-\(pane.id)")
        #expect(backend.startCount == 1)
    }

    // MARK: - Backend Operations

    @Test

    func test_startSession_withoutBackend_marksExited() async throws {
        let runtime = makeRuntime()
        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .ghostty
        )

        let handle = try await runtime.startSession(pane)

        #expect((handle) == nil)
        let status = runtime.status(for: pane.id)
        #expect(status == .exited)
    }

    @Test

    func test_startSession_withBackend_callsStart() async throws {
        let runtime = makeRuntime()
        let backend = MockSessionRuntimeBackend(provider: .zmx)
        runtime.registerBackend(backend)

        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .zmx
        )

        let handle = try await runtime.startSession(pane)

        #expect(handle == "mock-handle-\(pane.id)")
        let status = runtime.status(for: pane.id)
        #expect(status == .running)
        #expect(backend.startCount == 1)
    }

    @Test

    func test_restoreSession_withoutBackend_marksExited() async {
        let runtime = makeRuntime()
        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .ghostty
        )

        let restored = await runtime.restoreSession(pane)

        #expect(!(restored))
        let status = runtime.status(for: pane.id)
        #expect(status == .exited)
    }

    @Test

    func test_restoreSession_withBackend_success() async {
        let runtime = makeRuntime()
        let backend = MockSessionRuntimeBackend(provider: .zmx)
        backend.restoreResult = true
        runtime.registerBackend(backend)

        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .zmx
        )

        let restored = await runtime.restoreSession(pane)

        #expect(restored)
        let status = runtime.status(for: pane.id)
        #expect(status == .running)
    }

    @Test

    func test_restoreSession_withBackend_failure() async {
        let runtime = makeRuntime()
        let backend = MockSessionRuntimeBackend(provider: .zmx)
        backend.restoreResult = false
        runtime.registerBackend(backend)

        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .zmx
        )

        let restored = await runtime.restoreSession(pane)

        #expect(!(restored))
        let status = runtime.status(for: pane.id)
        #expect(status == .exited)
    }

    @Test

    func test_terminateSession_withBackend_marksExited() async {
        let runtime = makeRuntime()
        let backend = MockSessionRuntimeBackend(provider: .zmx)
        runtime.registerBackend(backend)

        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .zmx
        )
        runtime.markRunning(pane.id)

        await runtime.terminateSession(pane)

        let status = runtime.status(for: pane.id)
        #expect(status == .exited)
        #expect(backend.terminateCount == 1)
    }

    @Test

    func test_terminateSession_withoutBackend_marksExited() async {
        let runtime = makeRuntime()
        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .ghostty
        )
        runtime.markRunning(pane.id)

        await runtime.terminateSession(pane)

        let status = runtime.status(for: pane.id)
        #expect(status == .exited)
    }
}

// MARK: - Mock Backend

private final class MockSessionRuntimeBackend: SessionBackendProtocol, @unchecked Sendable {
    let provider: SessionProvider
    var startCount = 0
    var terminateCount = 0
    var restoreResult = true
    var isAliveResult = true

    init(provider: SessionProvider) {
        self.provider = provider
    }

    func start(pane: Pane) async throws -> String {
        startCount += 1
        return "mock-handle-\(pane.id)"
    }

    func isAlive(pane: Pane) async -> Bool {
        isAliveResult
    }

    func terminate(pane: Pane) async {
        terminateCount += 1
    }

    func restore(pane: Pane) async -> Bool {
        restoreResult
    }
}
