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

    func test_saveAndLoad_emptyState() {
        // Arrange
        let state = WorkspacePersistor.PersistableState()

        // Act
        persistor.save(state)
        let loaded = persistor.load()

        // Assert
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, state.id)
        XCTAssertEqual(loaded?.schemaVersion, 2)
        XCTAssertTrue(loaded?.sessions.isEmpty ?? false)
        XCTAssertTrue(loaded?.views.isEmpty ?? false)
    }

    func test_saveAndLoad_withSessions() {
        // Arrange
        let session = TerminalSession(
            source: .worktree(worktreeId: UUID(), repoId: UUID()),
            title: "Feature",
            agent: .claude,
            provider: .tmux,
            lifetime: .persistent,
            residency: .active
        )
        var state = WorkspacePersistor.PersistableState()
        state.sessions = [session]

        // Act
        persistor.save(state)
        let loaded = persistor.load()

        // Assert
        XCTAssertEqual(loaded?.sessions.count, 1)
        XCTAssertEqual(loaded?.sessions[0].id, session.id)
        XCTAssertEqual(loaded?.sessions[0].title, "Feature")
        XCTAssertEqual(loaded?.sessions[0].agent, .claude)
        XCTAssertEqual(loaded?.sessions[0].provider, .tmux)
        XCTAssertEqual(loaded?.sessions[0].lifetime, .persistent)
        XCTAssertEqual(loaded?.sessions[0].residency, .active)
    }

    func test_saveAndLoad_withViews() {
        // Arrange
        let sessionId = UUID()
        let tab = Tab(sessionId: sessionId)
        let view = ViewDefinition(
            name: "Main",
            kind: .main,
            tabs: [tab],
            activeTabId: tab.id
        )
        var state = WorkspacePersistor.PersistableState()
        state.views = [view]
        state.activeViewId = view.id

        // Act
        persistor.save(state)
        let loaded = persistor.load()

        // Assert
        XCTAssertEqual(loaded?.views.count, 1)
        XCTAssertEqual(loaded?.views[0].kind, .main)
        XCTAssertEqual(loaded?.views[0].tabs.count, 1)
        XCTAssertEqual(loaded?.views[0].tabs[0].sessionIds, [sessionId])
        XCTAssertEqual(loaded?.activeViewId, view.id)
    }

    func test_saveAndLoad_withSplitLayout() {
        // Arrange
        let s1 = UUID(), s2 = UUID(), s3 = UUID()
        let layout = Layout(sessionId: s1)
            .inserting(sessionId: s2, at: s1, direction: .horizontal, position: .after)
            .inserting(sessionId: s3, at: s2, direction: .vertical, position: .after)
        let tab = Tab(layout: layout, activeSessionId: s1)
        let view = ViewDefinition(name: "Main", kind: .main, tabs: [tab])
        var state = WorkspacePersistor.PersistableState()
        state.views = [view]

        // Act
        persistor.save(state)
        let loaded = persistor.load()

        // Assert
        XCTAssertEqual(loaded?.views[0].tabs[0].sessionIds, [s1, s2, s3])
        XCTAssertTrue(loaded?.views[0].tabs[0].isSplit ?? false)
    }

    func test_saveAndLoad_preservesAllFields() {
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
        persistor.save(state)
        let loaded = persistor.load()

        // Assert
        XCTAssertEqual(loaded?.name, "My Workspace")
        XCTAssertEqual(loaded?.sidebarWidth, 300)
        XCTAssertEqual(loaded?.windowFrame, CGRect(x: 10, y: 20, width: 1000, height: 800))
        XCTAssertEqual(loaded?.repos.count, 1)
        XCTAssertEqual(loaded?.repos[0].name, "test-repo")
        XCTAssertEqual(loaded?.repos[0].worktrees.count, 1)
    }

    // MARK: - Schema Version

    func test_load_wrongVersion_returnsNil() throws {
        // Arrange — manually write a v1 JSON
        let json = """
        {"schemaVersion": 1, "id": "\(UUID().uuidString)", "name": "Old", "repos": [], "sessions": [], "views": [], "sidebarWidth": 250, "createdAt": 0, "updatedAt": 0}
        """
        let fileURL = tempDir.appending(path: "\(UUID().uuidString).json")
        try json.data(using: .utf8)!.write(to: fileURL)

        // Act
        let loaded = persistor.load()

        // Assert
        XCTAssertNil(loaded)
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

    func test_delete_removesFile() {
        // Arrange
        let state = WorkspacePersistor.PersistableState()
        persistor.save(state)
        XCTAssertNotNil(persistor.load())

        // Act
        persistor.delete(id: state.id)

        // Assert
        XCTAssertNil(persistor.load())
    }

    // MARK: - Multiple Saves

    func test_save_overwritesPrevious() {
        // Arrange
        var state = WorkspacePersistor.PersistableState()
        state.name = "Version 1"
        persistor.save(state)

        state.name = "Version 2"
        persistor.save(state)

        // Act
        let loaded = persistor.load()

        // Assert
        XCTAssertEqual(loaded?.name, "Version 2")
    }

    // MARK: - ViewKind Codable

    func test_viewKind_allVariants_roundTrip() throws {
        // Arrange
        let worktreeId = UUID()
        let repoId = UUID()
        let views = [
            ViewDefinition(name: "Main", kind: .main),
            ViewDefinition(name: "Saved", kind: .saved),
            ViewDefinition(name: "WT", kind: .worktree(worktreeId: worktreeId)),
            ViewDefinition(name: "ByRepo", kind: .dynamic(rule: .byRepo(repoId: repoId))),
            ViewDefinition(name: "ByAgent", kind: .dynamic(rule: .byAgent(.claude))),
            ViewDefinition(name: "Custom", kind: .dynamic(rule: .custom(name: "test")))
        ]
        var state = WorkspacePersistor.PersistableState()
        state.views = views

        // Act
        persistor.save(state)
        let loaded = persistor.load()

        // Assert
        XCTAssertEqual(loaded?.views.count, 6)
        XCTAssertEqual(loaded?.views[0].kind, .main)
        XCTAssertEqual(loaded?.views[1].kind, .saved)
        XCTAssertEqual(loaded?.views[2].kind, .worktree(worktreeId: worktreeId))
        XCTAssertEqual(loaded?.views[3].kind, .dynamic(rule: .byRepo(repoId: repoId)))
        XCTAssertEqual(loaded?.views[4].kind, .dynamic(rule: .byAgent(.claude)))
        XCTAssertEqual(loaded?.views[5].kind, .dynamic(rule: .custom(name: "test")))
    }
}
