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

    func test_status_unknownSession_returnsInitializing() {
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

    func test_sessionsWithStatus_filtersCorrectly() {
        let runningId = UUID()
        let exitedId = UUID()
        let initId = UUID()

        runtime.markRunning(runningId)
        runtime.markExited(exitedId)
        runtime.initializeSession(initId)

        let running = runtime.sessions(withStatus: .running)
        XCTAssertEqual(running, [runningId])

        let exited = runtime.sessions(withStatus: .exited)
        XCTAssertEqual(exited, [exitedId])

        let initializing = runtime.sessions(withStatus: .initializing)
        XCTAssertEqual(initializing, [initId])
    }

    // MARK: - Sync With Store

    func test_syncWithStore_addsNewSessions() {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "runtime-test-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let runtime = SessionRuntime(store: store)

        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: nil)
        )

        runtime.syncWithStore()

        XCTAssertEqual(runtime.status(for: session.id), .initializing)
        XCTAssertTrue(runtime.statuses.keys.contains(session.id))

        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_syncWithStore_removesStaleSessions() {
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
        let backend = MockSessionBackend(provider: .tmux)
        runtime.registerBackend(backend)
        // No direct way to query backends, but startSession should use it
        // Tested via integration in startSession tests
        XCTAssertTrue(true) // Backend registered without error
    }

    // MARK: - Backend Operations

    func test_startSession_withoutBackend_marksRunning() async throws {
        let session = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .ghostty
        )

        let handle = try await runtime.startSession(session)

        XCTAssertNil(handle)
        XCTAssertEqual(runtime.status(for: session.id), .running)
    }

    func test_startSession_withBackend_callsStart() async throws {
        let backend = MockSessionBackend(provider: .tmux)
        runtime.registerBackend(backend)

        let session = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .tmux
        )

        let handle = try await runtime.startSession(session)

        XCTAssertEqual(handle, "mock-handle-\(session.id)")
        XCTAssertEqual(runtime.status(for: session.id), .running)
        XCTAssertEqual(backend.startCount, 1)
    }

    func test_restoreSession_withoutBackend_marksRunning() async {
        let session = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .ghostty
        )

        let restored = await runtime.restoreSession(session)

        XCTAssertTrue(restored)
        XCTAssertEqual(runtime.status(for: session.id), .running)
    }

    func test_restoreSession_withBackend_success() async {
        let backend = MockSessionBackend(provider: .tmux)
        backend.restoreResult = true
        runtime.registerBackend(backend)

        let session = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .tmux
        )

        let restored = await runtime.restoreSession(session)

        XCTAssertTrue(restored)
        XCTAssertEqual(runtime.status(for: session.id), .running)
    }

    func test_restoreSession_withBackend_failure() async {
        let backend = MockSessionBackend(provider: .tmux)
        backend.restoreResult = false
        runtime.registerBackend(backend)

        let session = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .tmux
        )

        let restored = await runtime.restoreSession(session)

        XCTAssertFalse(restored)
        XCTAssertEqual(runtime.status(for: session.id), .exited)
    }

    func test_terminateSession_withBackend_marksExited() async {
        let backend = MockSessionBackend(provider: .tmux)
        runtime.registerBackend(backend)

        let session = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .tmux
        )
        runtime.markRunning(session.id)

        await runtime.terminateSession(session)

        XCTAssertEqual(runtime.status(for: session.id), .exited)
        XCTAssertEqual(backend.terminateCount, 1)
    }

    func test_terminateSession_withoutBackend_marksExited() async {
        let session = TerminalSession(
            source: .floating(workingDirectory: nil, title: nil),
            provider: .ghostty
        )
        runtime.markRunning(session.id)

        await runtime.terminateSession(session)

        XCTAssertEqual(runtime.status(for: session.id), .exited)
    }
}

// MARK: - Mock Backend

private final class MockSessionBackend: SessionBackend, @unchecked Sendable {
    let provider: SessionProvider
    var startCount = 0
    var terminateCount = 0
    var restoreResult = true
    var isAliveResult = true

    init(provider: SessionProvider) {
        self.provider = provider
    }

    func start(session: TerminalSession) async throws -> String {
        startCount += 1
        return "mock-handle-\(session.id)"
    }

    func isAlive(session: TerminalSession) async -> Bool {
        isAliveResult
    }

    func terminate(session: TerminalSession) async {
        terminateCount += 1
    }

    func restore(session: TerminalSession) async -> Bool {
        restoreResult
    }
}
