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

    // MARK: - Legacy Schema Migration

    func test_load_legacySchema_migratesSessions() throws {
        // Arrange — write a legacy-format JSON file directly
        let sessionId = UUID()
        let worktreeId = UUID()
        let repoId = UUID()
        let legacy = LegacyPersistableState(
            id: UUID(),
            name: "Legacy Workspace",
            repos: [],
            sessions: [
                LegacySession(
                    id: sessionId,
                    source: .worktree(worktreeId: worktreeId, repoId: repoId),
                    title: "Feature Branch",
                    agent: .claude,
                    provider: .tmux,
                    lifetime: .persistent,
                    residency: .active,
                    lastKnownCWD: URL(fileURLWithPath: "/tmp/test")
                )
            ],
            views: [
                LegacyView(
                    id: UUID(),
                    name: "Main",
                    kind: .main,
                    tabs: [
                        LegacyTab(
                            id: UUID(),
                            layout: Layout(paneId: sessionId),
                            activeSessionId: sessionId
                        )
                    ],
                    activeTabId: nil
                )
            ],
            activeViewId: nil,
            sidebarWidth: 250,
            windowFrame: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Write legacy JSON to disk
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(legacy)
        let fileURL = tempDir.appending(path: "\(legacy.id.uuidString).json")
        try data.write(to: fileURL, options: .atomic)

        // Act — load should detect legacy format and migrate
        let loaded = persistor.load()

        // Assert
        XCTAssertNotNil(loaded, "Legacy schema should be migrated successfully")
        XCTAssertEqual(loaded?.name, "Legacy Workspace")
        XCTAssertEqual(loaded?.panes.count, 1)
        XCTAssertEqual(loaded?.panes[0].id, sessionId, "Pane ID must match session ID")
        XCTAssertEqual(loaded?.panes[0].title, "Feature Branch")
        XCTAssertEqual(loaded?.panes[0].agent, .claude)
        XCTAssertEqual(loaded?.panes[0].provider, .tmux)
        XCTAssertEqual(loaded?.panes[0].worktreeId, worktreeId)
        XCTAssertEqual(loaded?.panes[0].repoId, repoId)
        XCTAssertEqual(loaded?.tabs.count, 1)
        XCTAssertEqual(loaded?.tabs[0].paneIds, [sessionId], "Layout pane IDs must match migrated session")
        XCTAssertEqual(loaded?.tabs[0].activePaneId, sessionId)
    }

    func test_load_legacySchema_multipleSessions_andTabs() throws {
        // Arrange
        let s1 = UUID(), s2 = UUID()
        let tabId = UUID()
        let layout = Layout(paneId: s1)
            .inserting(paneId: s2, at: s1, direction: .horizontal, position: .after)

        let legacy = LegacyPersistableState(
            id: UUID(),
            name: "Multi",
            repos: [],
            sessions: [
                LegacySession(id: s1, source: .floating(workingDirectory: nil, title: nil), title: "Shell 1",
                              agent: nil, provider: .tmux, lifetime: .persistent, residency: .active, lastKnownCWD: nil),
                LegacySession(id: s2, source: .floating(workingDirectory: nil, title: nil), title: "Shell 2",
                              agent: nil, provider: .ghostty, lifetime: .persistent, residency: .active, lastKnownCWD: nil),
            ],
            views: [
                LegacyView(id: UUID(), name: "Main", kind: .main,
                           tabs: [LegacyTab(id: tabId, layout: layout, activeSessionId: s2)],
                           activeTabId: tabId)
            ],
            activeViewId: nil,
            sidebarWidth: 300,
            windowFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            createdAt: Date(),
            updatedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(legacy)
        let fileURL = tempDir.appending(path: "\(legacy.id.uuidString).json")
        try data.write(to: fileURL, options: .atomic)

        // Act
        let loaded = persistor.load()

        // Assert
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.panes.count, 2)
        XCTAssertEqual(loaded?.tabs.count, 1)
        XCTAssertEqual(loaded?.tabs[0].id, tabId)
        XCTAssertEqual(Set(loaded?.tabs[0].paneIds ?? []), Set([s1, s2]))
        XCTAssertEqual(loaded?.tabs[0].activePaneId, s2)
        XCTAssertEqual(loaded?.sidebarWidth, 300)
        XCTAssertEqual(loaded?.windowFrame, CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    func test_load_legacySchema_emptyViews_producesEmptyTabs() throws {
        // Arrange — legacy with sessions but no views
        let legacy = LegacyPersistableState(
            id: UUID(),
            name: "Empty Views",
            repos: [],
            sessions: [
                LegacySession(id: UUID(), source: .floating(workingDirectory: nil, title: nil), title: "Orphan",
                              agent: nil, provider: .tmux, lifetime: .persistent, residency: .active, lastKnownCWD: nil)
            ],
            views: [],
            activeViewId: nil,
            sidebarWidth: 250,
            windowFrame: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let data = try JSONEncoder().encode(legacy)
        let fileURL = tempDir.appending(path: "\(legacy.id.uuidString).json")
        try data.write(to: fileURL, options: .atomic)

        // Act
        let loaded = persistor.load()

        // Assert
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.panes.count, 1, "Sessions should still be migrated to panes")
        XCTAssertTrue(loaded?.tabs.isEmpty ?? false, "No views means no tabs")
    }

    func test_migrate_convertsLegacyToCurrentFormat() {
        // Arrange
        let sessionId = UUID()
        let legacy = LegacyPersistableState(
            id: UUID(),
            name: "Test",
            repos: [],
            sessions: [
                LegacySession(id: sessionId, source: .floating(workingDirectory: nil, title: "Shell"),
                              title: "My Terminal", agent: .codex, provider: .ghostty,
                              lifetime: .temporary, residency: .backgrounded, lastKnownCWD: nil)
            ],
            views: [
                LegacyView(id: UUID(), name: "Main", kind: .main,
                           tabs: [LegacyTab(id: UUID(), layout: Layout(paneId: sessionId), activeSessionId: sessionId)],
                           activeTabId: nil)
            ],
            activeViewId: nil,
            sidebarWidth: 200,
            windowFrame: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Act
        let migrated = WorkspacePersistor.migrate(from: legacy)

        // Assert
        XCTAssertEqual(migrated.panes.count, 1)
        let pane = migrated.panes[0]
        XCTAssertEqual(pane.id, sessionId)
        XCTAssertEqual(pane.agent, .codex)
        XCTAssertEqual(pane.provider, .ghostty)
        XCTAssertEqual(pane.lifetime, .temporary)
        XCTAssertEqual(pane.residency, .backgrounded)

        // Tab should have a default arrangement wrapping the layout
        XCTAssertEqual(migrated.tabs.count, 1)
        XCTAssertEqual(migrated.tabs[0].defaultArrangement.layout.paneIds, [sessionId])
    }
}
