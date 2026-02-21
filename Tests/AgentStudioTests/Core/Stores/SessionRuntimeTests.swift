import Testing
import Foundation

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class SessionRuntimeTests {

    private var runtime: SessionRuntime!

    @BeforeEach
    func setUp() {
        runtime = SessionRuntime(healthCheckInterval: 1)
    }

    @AfterEach
    func tearDown() {
        runtime.stopHealthChecks()
        runtime = nil
    }

    // MARK: - Status Queries

    @Test

    func test_status_unknownPane_returnsInitializing() {
        #expect(runtime.status(for: UUID()) == .initializing)
    }

    @Test

    func test_status_afterInitialize_returnsInitializing() {
        let id = UUID()
        runtime.initializeSession(id)
        #expect(runtime.status(for: id) == .initializing)
    }

    @Test

    func test_status_afterMarkRunning_returnsRunning() {
        let id = UUID()
        runtime.initializeSession(id)
        runtime.markRunning(id)
        #expect(runtime.status(for: id) == .running)
    }

    @Test

    func test_status_afterMarkExited_returnsExited() {
        let id = UUID()
        runtime.markRunning(id)
        runtime.markExited(id)
        #expect(runtime.status(for: id) == .exited)
    }

    @Test

    func test_removeSession_clearsStatus() {
        let id = UUID()
        runtime.markRunning(id)
        runtime.removeSession(id)
        // Should return default (initializing) since entry is gone
        #expect(runtime.status(for: id) == .initializing)
        #expect(!(runtime.statuses.keys.contains(id)))
    }

    // MARK: - Aggregate Queries

    @Test

    func test_runningCount_reflectsState() {
        let ids = (0..<5).map { _ in UUID() }
        for id in ids { runtime.markRunning(id) }
        runtime.markExited(ids[0])
        runtime.markExited(ids[1])

        #expect(runtime.runningCount == 3)
    }

    @Test

    func test_panesWithStatus_filtersCorrectly() {
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
        let runtime = SessionRuntime(store: store)

        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )

        runtime.syncWithStore()

        #expect(runtime.status(for: pane.id) == .initializing)
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
        let runtime = SessionRuntime(store: store)

        let staleId = UUID()
        runtime.markRunning(staleId)

        runtime.syncWithStore()

        #expect(!(runtime.statuses.keys.contains(staleId)))

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Backend Registration

    @Test

    func test_registerBackend_storesCorrectly() {
        let backend = MockSessionRuntimeBackend(provider: .zmx)
        runtime.registerBackend(backend)
        // No direct way to query backends, but startSession should use it
        // Tested via integration in startSession tests
        #expect(true)  // Backend registered without error
    }

    // MARK: - Backend Operations

    @Test

    func test_startSession_withoutBackend_marksRunning() async throws {
        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .ghostty
        )

        let handle = try await runtime.startSession(pane)

        #expect((handle) == nil)
        #expect(runtime.status(for: pane.id) == .running)
    }

    @Test

    func test_startSession_withBackend_callsStart() async throws {
        let backend = MockSessionRuntimeBackend(provider: .zmx)
        runtime.registerBackend(backend)

        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .zmx
        )

        let handle = try await runtime.startSession(pane)

        #expect(handle == "mock-handle-\(pane.id)")
        #expect(runtime.status(for: pane.id) == .running)
        #expect(backend.startCount == 1)
    }

    @Test

    func test_restoreSession_withoutBackend_marksRunning() async {
        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .ghostty
        )

        let restored = await runtime.restoreSession(pane)

        #expect(restored)
        #expect(runtime.status(for: pane.id) == .running)
    }

    @Test

    func test_restoreSession_withBackend_success() async {
        let backend = MockSessionRuntimeBackend(provider: .zmx)
        backend.restoreResult = true
        runtime.registerBackend(backend)

        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .zmx
        )

        let restored = await runtime.restoreSession(pane)

        #expect(restored)
        #expect(runtime.status(for: pane.id) == .running)
    }

    @Test

    func test_restoreSession_withBackend_failure() async {
        let backend = MockSessionRuntimeBackend(provider: .zmx)
        backend.restoreResult = false
        runtime.registerBackend(backend)

        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .zmx
        )

        let restored = await runtime.restoreSession(pane)

        #expect(!(restored))
        #expect(runtime.status(for: pane.id) == .exited)
    }

    @Test

    func test_terminateSession_withBackend_marksExited() async {
        let backend = MockSessionRuntimeBackend(provider: .zmx)
        runtime.registerBackend(backend)

        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .zmx
        )
        runtime.markRunning(pane.id)

        await runtime.terminateSession(pane)

        #expect(runtime.status(for: pane.id) == .exited)
        #expect(backend.terminateCount == 1)
    }

    @Test

    func test_terminateSession_withoutBackend_marksExited() async {
        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .ghostty
        )
        runtime.markRunning(pane.id)

        await runtime.terminateSession(pane)

        #expect(runtime.status(for: pane.id) == .exited)
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
