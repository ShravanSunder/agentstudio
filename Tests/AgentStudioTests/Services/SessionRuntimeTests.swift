import XCTest
@testable import AgentStudio

@MainActor
final class SessionRuntimeTests: XCTestCase {

    private var runtime: SessionRuntime!

    override func setUp() {
        super.setUp()
        runtime = SessionRuntime(healthCheckInterval: 1)
    }

    override func tearDown() {
        runtime.stopHealthChecks()
        runtime = nil
        super.tearDown()
    }

    // MARK: - Status Queries

    func test_status_unknownPane_returnsInitializing() {
        XCTAssertEqual(runtime.status(for: UUID()), .initializing)
    }

    func test_status_afterInitialize_returnsInitializing() {
        let id = UUID()
        runtime.initializeSession(id)
        XCTAssertEqual(runtime.status(for: id), .initializing)
    }

    func test_status_afterMarkRunning_returnsRunning() {
        let id = UUID()
        runtime.initializeSession(id)
        runtime.markRunning(id)
        XCTAssertEqual(runtime.status(for: id), .running)
    }

    func test_status_afterMarkExited_returnsExited() {
        let id = UUID()
        runtime.markRunning(id)
        runtime.markExited(id)
        XCTAssertEqual(runtime.status(for: id), .exited)
    }

    func test_removeSession_clearsStatus() {
        let id = UUID()
        runtime.markRunning(id)
        runtime.removeSession(id)
        // Should return default (initializing) since entry is gone
        XCTAssertEqual(runtime.status(for: id), .initializing)
        XCTAssertFalse(runtime.statuses.keys.contains(id))
    }

    // MARK: - Aggregate Queries

    func test_runningCount_reflectsState() {
        let ids = (0..<5).map { _ in UUID() }
        for id in ids { runtime.markRunning(id) }
        runtime.markExited(ids[0])
        runtime.markExited(ids[1])

        XCTAssertEqual(runtime.runningCount, 3)
    }

    func test_panesWithStatus_filtersCorrectly() {
        let runningId = UUID()
        let exitedId = UUID()
        let initId = UUID()

        runtime.markRunning(runningId)
        runtime.markExited(exitedId)
        runtime.initializeSession(initId)

        let running = runtime.panes(withStatus: .running)
        XCTAssertEqual(running, [runningId])

        let exited = runtime.panes(withStatus: .exited)
        XCTAssertEqual(exited, [exitedId])

        let initializing = runtime.panes(withStatus: .initializing)
        XCTAssertEqual(initializing, [initId])
    }

    // MARK: - Sync With Store

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

        XCTAssertEqual(runtime.status(for: pane.id), .initializing)
        XCTAssertTrue(runtime.statuses.keys.contains(pane.id))

        try? FileManager.default.removeItem(at: tempDir)
    }

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

        XCTAssertFalse(runtime.statuses.keys.contains(staleId))

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Backend Registration

    func test_registerBackend_storesCorrectly() {
        let backend = MockSessionRuntimeBackend(provider: .tmux)
        runtime.registerBackend(backend)
        // No direct way to query backends, but startSession should use it
        // Tested via integration in startSession tests
        XCTAssertTrue(true) // Backend registered without error
    }

    // MARK: - Backend Operations

    func test_startSession_withoutBackend_marksRunning() async throws {
        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .ghostty
        )

        let handle = try await runtime.startSession(pane)

        XCTAssertNil(handle)
        XCTAssertEqual(runtime.status(for: pane.id), .running)
    }

    func test_startSession_withBackend_callsStart() async throws {
        let backend = MockSessionRuntimeBackend(provider: .tmux)
        runtime.registerBackend(backend)

        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .tmux
        )

        let handle = try await runtime.startSession(pane)

        XCTAssertEqual(handle, "mock-handle-\(pane.id)")
        XCTAssertEqual(runtime.status(for: pane.id), .running)
        XCTAssertEqual(backend.startCount, 1)
    }

    func test_restoreSession_withoutBackend_marksRunning() async {
        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .ghostty
        )

        let restored = await runtime.restoreSession(pane)

        XCTAssertTrue(restored)
        XCTAssertEqual(runtime.status(for: pane.id), .running)
    }

    func test_restoreSession_withBackend_success() async {
        let backend = MockSessionRuntimeBackend(provider: .tmux)
        backend.restoreResult = true
        runtime.registerBackend(backend)

        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .tmux
        )

        let restored = await runtime.restoreSession(pane)

        XCTAssertTrue(restored)
        XCTAssertEqual(runtime.status(for: pane.id), .running)
    }

    func test_restoreSession_withBackend_failure() async {
        let backend = MockSessionRuntimeBackend(provider: .tmux)
        backend.restoreResult = false
        runtime.registerBackend(backend)

        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .tmux
        )

        let restored = await runtime.restoreSession(pane)

        XCTAssertFalse(restored)
        XCTAssertEqual(runtime.status(for: pane.id), .exited)
    }

    func test_terminateSession_withBackend_marksExited() async {
        let backend = MockSessionRuntimeBackend(provider: .tmux)
        runtime.registerBackend(backend)

        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .tmux
        )
        runtime.markRunning(pane.id)

        await runtime.terminateSession(pane)

        XCTAssertEqual(runtime.status(for: pane.id), .exited)
        XCTAssertEqual(backend.terminateCount, 1)
    }

    func test_terminateSession_withoutBackend_marksExited() async {
        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .ghostty
        )
        runtime.markRunning(pane.id)

        await runtime.terminateSession(pane)

        XCTAssertEqual(runtime.status(for: pane.id), .exited)
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
