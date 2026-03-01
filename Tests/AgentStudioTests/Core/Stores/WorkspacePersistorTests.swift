import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class WorkspacePersistorTests {

    private var tempDir: URL!
    private var persistor: WorkspacePersistor!

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "persistor-tests-\(UUID().uuidString)")
        persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Save & Load

    @Test

    func test_saveAndLoad_emptyState() throws {
        // Arrange
        let state = WorkspacePersistor.PersistableState()

        // Act
        try persistor.save(state)
        let loaded = persistor.load()

        // Assert
        #expect((loaded) != nil)
        #expect(loaded?.id == state.id)
        #expect(loaded?.panes.isEmpty ?? false)
    }

    @Test

    func test_saveAndLoad_withPanes() throws {
        // Arrange
        let pane = makePane(
            source: .worktree(worktreeId: UUID(), repoId: UUID()),
            title: "Feature",
            agent: .claude,
            provider: .zmx,
            lifetime: .persistent,
            residency: .active
        )
        var state = WorkspacePersistor.PersistableState()
        state.panes = [pane]

        // Act
        try persistor.save(state)
        let loaded = persistor.load()

        // Assert
        #expect(loaded?.panes.count == 1)
        #expect(loaded?.panes[0].id == pane.id)
        #expect(loaded?.panes[0].title == "Feature")
        #expect(loaded?.panes[0].agent == .claude)
        #expect(loaded?.panes[0].provider == .zmx)
        #expect(loaded?.panes[0].lifetime == .persistent)
        #expect(loaded?.panes[0].residency == .active)
    }

    @Test

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
        #expect(loaded?.tabs.count == 1)
        #expect(loaded?.tabs[0].paneIds == [paneId])
        #expect(loaded?.activeTabId == tab.id)
    }

    @Test

    func test_saveAndLoad_withSplitLayout() throws {
        // Arrange
        let s1 = UUID()
        let s2 = UUID()
        let s3 = UUID()
        let tab = makeTab(paneIds: [s1, s2, s3], activePaneId: s1)
        var state = WorkspacePersistor.PersistableState()
        state.tabs = [tab]

        // Act
        try persistor.save(state)
        let loaded = persistor.load()

        // Assert
        #expect(loaded?.tabs[0].paneIds == [s1, s2, s3])
        #expect(loaded?.tabs[0].isSplit ?? false)
    }

    @Test

    func test_saveAndLoad_preservesAllFields() throws {
        // Arrange
        var state = WorkspacePersistor.PersistableState(
            name: "My Workspace",
            sidebarWidth: 300,
            windowFrame: CGRect(x: 10, y: 20, width: 1000, height: 800)
        )
        let repo = CanonicalRepo(
            name: "test-repo",
            repoPath: URL(fileURLWithPath: "/tmp/test-repo")
        )
        state.repos = [repo]
        state.worktrees = [
            CanonicalWorktree(
                repoId: repo.id,
                name: "main",
                path: URL(fileURLWithPath: "/tmp/test-repo/main"),
                isMainWorktree: true
            )
        ]

        // Act
        try persistor.save(state)
        let loaded = persistor.load()

        // Assert
        #expect(loaded?.name == "My Workspace")
        #expect(loaded?.sidebarWidth == 300)
        #expect(loaded?.windowFrame == CGRect(x: 10, y: 20, width: 1000, height: 800))
        #expect(loaded?.repos.count == 1)
        #expect(loaded?.repos[0].name == "test-repo")
        #expect(loaded?.worktrees.count == 1)
    }

    @Test

    func test_load_noFiles_returnsNil() {
        // The temp dir is empty
        let loaded = persistor.load()
        #expect((loaded) == nil)
    }

    @Test

    func test_load_nonExistentDir_returnsNil() {
        // Arrange
        let badPersistor = WorkspacePersistor(
            workspacesDir: URL(fileURLWithPath: "/nonexistent/path/\(UUID().uuidString)")
        )

        // Act
        let loaded = badPersistor.load()

        // Assert
        #expect((loaded) == nil)
    }

    @Test

    func test_load_legacyPaneSchemaWithoutKind_returnsNil() throws {
        let pane = makePane(
            source: .floating(workingDirectory: nil, title: nil),
            title: "LegacyPane",
            provider: .zmx
        )
        var state = WorkspacePersistor.PersistableState()
        state.panes = [pane]
        let stateData = try JSONEncoder().encode(state)

        guard var stateObject = try JSONSerialization.jsonObject(with: stateData) as? [String: Any],
            var panes = stateObject["panes"] as? [[String: Any]],
            var firstPane = panes.first
        else {
            Issue.record("Expected persistable state JSON with panes")
            return
        }

        firstPane.removeValue(forKey: "kind")
        firstPane["drawer"] = [
            "paneIds": [],
            "layout": NSNull(),
            "activePaneId": NSNull(),
            "isExpanded": false,
            "minimizedPaneIds": [],
        ]
        panes[0] = firstPane
        stateObject["panes"] = panes

        let legacyData = try JSONSerialization.data(withJSONObject: stateObject)
        let legacyURL = tempDir.appending(path: "legacy-\(UUID().uuidString).json")
        try legacyData.write(to: legacyURL, options: .atomic)

        let loaded = persistor.load(from: legacyURL)
        #expect(loaded == nil)
    }

    // MARK: - Delete

    @Test

    func test_delete_removesFile() throws {
        // Arrange
        let state = WorkspacePersistor.PersistableState()
        try persistor.save(state)
        #expect((persistor.load()) != nil)

        // Act
        persistor.delete(id: state.id)

        // Assert
        #expect((persistor.load()) == nil)
    }

    // MARK: - Multiple Saves

    @Test

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
        #expect(loaded?.name == "Second Save")
    }

    // MARK: - hasWorkspaceFiles

    @Test

    func test_hasWorkspaceFiles_emptyDir_returnsFalse() {
        // Assert — freshly created temp dir has no workspace files
        #expect(!(persistor.hasWorkspaceFiles()))
    }

    @Test

    func test_hasWorkspaceFiles_afterSave_returnsTrue() throws {
        // Arrange
        let state = WorkspacePersistor.PersistableState()
        try persistor.save(state)

        // Assert
        #expect(persistor.hasWorkspaceFiles())
    }

    @Test

    func test_hasWorkspaceFiles_nonExistentDir_returnsFalse() {
        // Arrange
        let badPersistor = WorkspacePersistor(
            workspacesDir: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        )

        // Assert
        #expect(!(badPersistor.hasWorkspaceFiles()))
    }

    // MARK: - Save Failure

    @Test

    func test_save_toNonWritablePath_throws() {
        // Arrange
        let readOnlyPersistor = WorkspacePersistor(
            workspacesDir: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        )
        let state = WorkspacePersistor.PersistableState()

        // Act & Assert
        #expect(throws: Error.self) {
            try readOnlyPersistor.save(state)
        }
    }

    @Test
    func test_saveAndLoad_cacheState() throws {
        let workspaceId = UUID()
        let repoId = UUID()
        let worktreeId = UUID()
        let cacheState = WorkspacePersistor.PersistableCacheState(
            workspaceId: workspaceId,
            repoEnrichmentByRepoId: [
                repoId: .resolved(
                    repoId: repoId,
                    raw: RawRepoOrigin(origin: "git@github.com:askluna/agent-studio.git", upstream: nil),
                    identity: RepoIdentity(
                        groupKey: "remote:askluna/agent-studio",
                        remoteSlug: "askluna/agent-studio",
                        organizationName: "askluna",
                        displayName: "agent-studio"
                    ),
                    updatedAt: Date()
                )
            ],
            worktreeEnrichmentByWorktreeId: [
                worktreeId: WorktreeEnrichment(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    branch: "main"
                )
            ],
            pullRequestCountByWorktreeId: [worktreeId: 2],
            notificationCountByWorktreeId: [worktreeId: 7],
            sourceRevision: 10,
            lastRebuiltAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try persistor.saveCache(cacheState)
        let loaded = persistor.loadCache(for: workspaceId)

        #expect(loaded?.workspaceId == workspaceId)
        #expect(loaded?.repoEnrichmentByRepoId[repoId]?.organizationName == "askluna")
        #expect(loaded?.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main")
        #expect(loaded?.pullRequestCountByWorktreeId[worktreeId] == 2)
        #expect(loaded?.notificationCountByWorktreeId[worktreeId] == 7)
        #expect(loaded?.sourceRevision == 10)
    }

    @Test
    func test_saveAndLoad_uiState() throws {
        let workspaceId = UUID()
        let uiState = WorkspacePersistor.PersistableUIState(
            workspaceId: workspaceId,
            expandedGroups: ["askluna", "personal"],
            checkoutColors: ["repoA": "#22cc88"],
            filterText: "forge",
            isFilterVisible: true
        )

        try persistor.saveUI(uiState)
        let loaded = persistor.loadUI(for: workspaceId)

        #expect(loaded?.workspaceId == workspaceId)
        #expect(loaded?.expandedGroups == ["askluna", "personal"])
        #expect(loaded?.checkoutColors["repoA"] == "#22cc88")
        #expect(loaded?.filterText == "forge")
        #expect(loaded?.isFilterVisible == true)
    }

    @Test
    func test_loadCache_corruptJson_returnsNil() throws {
        let workspaceId = UUID()
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.cache.json")
        let data = Data("{not-valid-json}".utf8)
        try data.write(to: cacheURL, options: .atomic)

        let loaded = persistor.loadCache(for: workspaceId)

        #expect(loaded == nil)
    }

    @Test
    func test_loadUI_corruptJson_returnsNil() throws {
        let workspaceId = UUID()
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        let data = Data("{not-valid-json}".utf8)
        try data.write(to: uiURL, options: .atomic)

        let loaded = persistor.loadUI(for: workspaceId)

        #expect(loaded == nil)
    }

    @Test
    func test_load_legacyWorkspaceStateWithInlineWorktrees_migratesToCanonicalShape() throws {
        let workspaceId = UUID()
        let repoId = UUID()
        let worktreeId = UUID()
        let repoPath = URL(fileURLWithPath: "/tmp/legacy-repo")

        let legacyState = LegacyPersistableState(
            id: workspaceId,
            name: "Legacy Workspace",
            repos: [
                LegacyRepo(
                    id: repoId,
                    name: "legacy-repo",
                    repoPath: repoPath,
                    organizationName: "askluna",
                    origin: "git@github.com:askluna/legacy-repo.git",
                    upstream: nil,
                    worktrees: [
                        LegacyWorktree(
                            id: worktreeId,
                            name: "main",
                            path: repoPath,
                            branch: "main",
                            agent: nil,
                            status: .idle,
                            isMainWorktree: true
                        )
                    ],
                    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
                )
            ],
            panes: [],
            tabs: [],
            activeTabId: nil,
            sidebarWidth: 250,
            windowFrame: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let legacyURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.state.json")
        try JSONEncoder().encode(legacyState).write(to: legacyURL, options: .atomic)

        let loaded = persistor.load()

        #expect(loaded != nil)
        #expect(loaded?.repos.count == 1)
        #expect(loaded?.repos.first?.id == repoId)
        #expect(loaded?.repos.first?.repoPath == repoPath)
        #expect(loaded?.worktrees.count == 1)
        #expect(loaded?.worktrees.first?.id == worktreeId)
        #expect(loaded?.worktrees.first?.repoId == repoId)
        #expect(loaded?.worktrees.first?.path == repoPath)
        #expect(loaded?.unavailableRepoIds.isEmpty == true)
    }

    private struct LegacyPersistableState: Codable {
        var id: UUID
        var name: String
        var repos: [LegacyRepo]
        var panes: [Pane]
        var tabs: [Tab]
        var activeTabId: UUID?
        var sidebarWidth: CGFloat
        var windowFrame: CGRect?
        var createdAt: Date
        var updatedAt: Date
    }

    private struct LegacyRepo: Codable {
        var id: UUID
        var name: String
        var repoPath: URL
        var organizationName: String?
        var origin: String?
        var upstream: String?
        var worktrees: [LegacyWorktree]
        var createdAt: Date
        var updatedAt: Date
    }

    private struct LegacyWorktree: Codable {
        var id: UUID
        var name: String
        var path: URL
        var branch: String
        var agent: AgentType?
        var status: WorktreeStatus
        var isMainWorktree: Bool
    }
}
