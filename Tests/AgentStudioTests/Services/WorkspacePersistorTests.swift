import XCTest
@testable import AgentStudio

final class WorkspacePersistorTests: XCTestCase {

    private var tempDir: URL!
    private var persistor: WorkspacePersistor!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "persistor-tests-\(UUID().uuidString)")
        persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Save & Load

    func test_saveAndLoad_emptyState() throws {
        // Arrange
        let state = WorkspacePersistor.PersistableState()

        // Act
        try persistor.save(state)
        let loaded = persistor.load()

        // Assert
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, state.id)
        XCTAssertTrue(loaded?.panes.isEmpty ?? false)
    }

    func test_saveAndLoad_withPanes() throws {
        // Arrange
        let pane = makePane(
            source: .worktree(worktreeId: UUID(), repoId: UUID()),
            title: "Feature",
            agent: .claude,
            provider: .tmux,
            lifetime: .persistent,
            residency: .active
        )
        var state = WorkspacePersistor.PersistableState()
        state.panes = [pane]

        // Act
        try persistor.save(state)
        let loaded = persistor.load()

        // Assert
        XCTAssertEqual(loaded?.panes.count, 1)
        XCTAssertEqual(loaded?.panes[0].id, pane.id)
        XCTAssertEqual(loaded?.panes[0].title, "Feature")
        XCTAssertEqual(loaded?.panes[0].agent, .claude)
        XCTAssertEqual(loaded?.panes[0].provider, .tmux)
        XCTAssertEqual(loaded?.panes[0].lifetime, .persistent)
        XCTAssertEqual(loaded?.panes[0].residency, .active)
    }

    func test_saveAndLoad_withTabs() throws {
        // Arrange
        let paneId = UUID()
        let tab = Tab(paneId: paneId)
        var state = WorkspacePersistor.PersistableState()
        state.tabs = [tab]
        state.activeTabId = tab.id

        // Act
        try persistor.save(state)
        let loaded = persistor.load()

        // Assert
        XCTAssertEqual(loaded?.tabs.count, 1)
        XCTAssertEqual(loaded?.tabs[0].paneIds, [paneId])
        XCTAssertEqual(loaded?.activeTabId, tab.id)
    }

    func test_saveAndLoad_withSplitLayout() throws {
        // Arrange
        let s1 = UUID(), s2 = UUID(), s3 = UUID()
        let tab = makeTab(paneIds: [s1, s2, s3], activePaneId: s1)
        var state = WorkspacePersistor.PersistableState()
        state.tabs = [tab]

        // Act
        try persistor.save(state)
        let loaded = persistor.load()

        // Assert
        XCTAssertEqual(loaded?.tabs[0].paneIds, [s1, s2, s3])
        XCTAssertTrue(loaded?.tabs[0].isSplit ?? false)
    }

    func test_saveAndLoad_preservesAllFields() throws {
        // Arrange
        var state = WorkspacePersistor.PersistableState(
            name: "My Workspace",
            sidebarWidth: 300,
            windowFrame: CGRect(x: 10, y: 20, width: 1000, height: 800)
        )
        let repo = Repo(
            name: "test-repo",
            repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
            worktrees: [
                Worktree(
                    name: "main",
                    path: URL(fileURLWithPath: "/tmp/test-repo/main"),
                    branch: "main"
                )
            ]
        )
        state.repos = [repo]

        // Act
        try persistor.save(state)
        let loaded = persistor.load()

        // Assert
        XCTAssertEqual(loaded?.name, "My Workspace")
        XCTAssertEqual(loaded?.sidebarWidth, 300)
        XCTAssertEqual(loaded?.windowFrame, CGRect(x: 10, y: 20, width: 1000, height: 800))
        XCTAssertEqual(loaded?.repos.count, 1)
        XCTAssertEqual(loaded?.repos[0].name, "test-repo")
        XCTAssertEqual(loaded?.repos[0].worktrees.count, 1)
    }

    func test_load_noFiles_returnsNil() {
        // The temp dir is empty
        let loaded = persistor.load()
        XCTAssertNil(loaded)
    }

    func test_load_nonExistentDir_returnsNil() {
        // Arrange
        let badPersistor = WorkspacePersistor(
            workspacesDir: URL(fileURLWithPath: "/nonexistent/path/\(UUID().uuidString)")
        )

        // Act
        let loaded = badPersistor.load()

        // Assert
        XCTAssertNil(loaded)
    }

    // MARK: - Delete

    func test_delete_removesFile() throws {
        // Arrange
        let state = WorkspacePersistor.PersistableState()
        try persistor.save(state)
        XCTAssertNotNil(persistor.load())

        // Act
        persistor.delete(id: state.id)

        // Assert
        XCTAssertNil(persistor.load())
    }

    // MARK: - Multiple Saves

    func test_save_overwritesPrevious() throws {
        // Arrange
        var state = WorkspacePersistor.PersistableState()
        state.name = "First Save"
        try persistor.save(state)

        state.name = "Second Save"
        try persistor.save(state)

        // Act
        let loaded = persistor.load()

        // Assert
        XCTAssertEqual(loaded?.name, "Second Save")
    }

    // MARK: - hasWorkspaceFiles

    func test_hasWorkspaceFiles_emptyDir_returnsFalse() {
        // Assert — freshly created temp dir has no workspace files
        XCTAssertFalse(persistor.hasWorkspaceFiles())
    }

    func test_hasWorkspaceFiles_afterSave_returnsTrue() throws {
        // Arrange
        let state = WorkspacePersistor.PersistableState()
        try persistor.save(state)

        // Assert
        XCTAssertTrue(persistor.hasWorkspaceFiles())
    }

    func test_hasWorkspaceFiles_nonExistentDir_returnsFalse() {
        // Arrange
        let badPersistor = WorkspacePersistor(
            workspacesDir: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        )

        // Assert
        XCTAssertFalse(badPersistor.hasWorkspaceFiles())
    }

    // MARK: - Save Failure

    func test_save_toNonWritablePath_throws() {
        // Arrange
        let readOnlyPersistor = WorkspacePersistor(
            workspacesDir: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        )
        let state = WorkspacePersistor.PersistableState()

        // Act & Assert
        XCTAssertThrowsError(try readOnlyPersistor.save(state))
    }
}
