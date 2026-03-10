import Foundation
import Testing

@testable import AgentStudio

// MARK: - LoadResult test helpers

extension WorkspacePersistor.LoadResult {
    /// Extract the loaded value or return nil — convenience for test assertions.
    fileprivate var value: T? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    fileprivate var isMissing: Bool {
        if case .missing = self { return true }
        return false
    }

    fileprivate var isCorrupt: Bool {
        if case .corrupt = self { return true }
        return false
    }
}

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
        let loaded = persistor.load().value

        // Assert
        #expect(loaded != nil)
        #expect(loaded?.id == state.id)
        #expect(loaded?.panes.isEmpty ?? false)
    }

    @Test
    func test_saveAndLoad_withPanes() throws {
        // Arrange
        let pane = makePane(
            source: .worktree(worktreeId: UUID(), repoId: UUID()),
            title: "Feature",
            provider: .zmx,
            lifetime: .persistent,
            residency: .active
        )
        var state = WorkspacePersistor.PersistableState()
        state.panes = [pane]

        // Act
        try persistor.save(state)
        let loaded = persistor.load().value

        // Assert
        #expect(loaded?.panes.count == 1)
        #expect(loaded?.panes[0].id == pane.id)
        #expect(loaded?.panes[0].title == "Feature")
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
        let loaded = persistor.load().value

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
        let loaded = persistor.load().value

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
        let loaded = persistor.load().value

        // Assert
        #expect(loaded?.name == "My Workspace")
        #expect(loaded?.sidebarWidth == 300)
        #expect(loaded?.windowFrame == CGRect(x: 10, y: 20, width: 1000, height: 800))
        #expect(loaded?.repos.count == 1)
        #expect(loaded?.repos[0].name == "test-repo")
        #expect(loaded?.worktrees.count == 1)
    }

    // MARK: - Load Missing & Corrupt

    @Test
    func test_load_noFiles_returnsMissing() {
        // The temp dir is empty
        #expect(persistor.load().isMissing)
    }

    @Test
    func test_load_nonExistentDir_returnsMissing() {
        // Arrange
        let badPersistor = WorkspacePersistor(
            workspacesDir: URL(fileURLWithPath: "/nonexistent/path/\(UUID().uuidString)")
        )

        // Act & Assert
        #expect(badPersistor.load().isMissing)
    }

    @Test
    func test_load_corruptStateFile_returnsCorrupt() throws {
        // Arrange — write garbage with the canonical suffix
        let fakeId = UUID()
        let corruptURL = tempDir.appending(
            path: "\(fakeId.uuidString).workspace.state.json"
        )
        try Data("{not-valid-json}".utf8).write(to: corruptURL, options: .atomic)

        // Act
        let result = persistor.load()

        // Assert
        #expect(result.isCorrupt)
    }

    @Test
    func test_load_canonicalState_missingWatchedPaths_returnsCorrupt() throws {
        // Arrange — valid JSON but without the watchedPaths field
        let workspaceId = UUID()
        let json: [String: Any] = [
            "schemaVersion": 1,
            "id": workspaceId.uuidString,
            "name": "Test Workspace",
            "repos": [] as [Any],
            "worktrees": [] as [Any],
            "unavailableRepoIds": [] as [Any],
            "panes": [] as [Any],
            "tabs": [] as [Any],
            "sidebarWidth": 250,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let stateURL = tempDir.appending(
            path: "\(workspaceId.uuidString).workspace.state.json"
        )
        try data.write(to: stateURL, options: .atomic)

        // Act
        let result = persistor.load()

        // Assert — strict decode means missing required field → corrupt
        #expect(result.isCorrupt)
    }

    @Test
    func test_load_ignoresCacheAndUIFiles() throws {
        // Arrange — write only cache and UI files, no canonical state
        let workspaceId = UUID()
        let cacheState = WorkspacePersistor.PersistableCacheState(workspaceId: workspaceId)
        try persistor.saveCache(cacheState)
        let uiState = WorkspacePersistor.PersistableUIState(workspaceId: workspaceId)
        try persistor.saveUI(uiState)

        // Act — load() should only look for *.workspace.state.json
        let result = persistor.load()

        // Assert
        #expect(result.isMissing)
    }

    // MARK: - Delete

    @Test
    func test_delete_removesFile() throws {
        // Arrange
        let state = WorkspacePersistor.PersistableState()
        try persistor.save(state)
        #expect(persistor.load().value != nil)

        // Act
        persistor.delete(id: state.id)

        // Assert
        #expect(persistor.load().isMissing)
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
        let loaded = persistor.load().value

        // Assert
        #expect(loaded?.name == "Second Save")
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

    // MARK: - Schema Version

    @Test
    func test_schemaVersion_roundTripsForCanonicalState() throws {
        // Arrange
        let state = WorkspacePersistor.PersistableState()

        // Act
        try persistor.save(state)
        let loaded = persistor.load().value

        // Assert
        #expect(loaded?.schemaVersion == WorkspacePersistor.currentSchemaVersion)
    }

    @Test
    func test_schemaVersion_roundTripsForCacheState() throws {
        // Arrange
        let workspaceId = UUID()
        let cacheState = WorkspacePersistor.PersistableCacheState(workspaceId: workspaceId)

        // Act
        try persistor.saveCache(cacheState)
        let loaded = persistor.loadCache(for: workspaceId).value

        // Assert
        #expect(loaded?.schemaVersion == WorkspacePersistor.currentSchemaVersion)
    }

    @Test
    func test_schemaVersion_roundTripsForUIState() throws {
        // Arrange
        let workspaceId = UUID()
        let uiState = WorkspacePersistor.PersistableUIState(workspaceId: workspaceId)

        // Act
        try persistor.saveUI(uiState)
        let loaded = persistor.loadUI(for: workspaceId).value

        // Assert
        #expect(loaded?.schemaVersion == WorkspacePersistor.currentSchemaVersion)
    }

    // MARK: - Cache State

    @Test
    func test_saveAndLoad_cacheState() throws {
        let workspaceId = UUID()
        let repoId = UUID()
        let worktreeId = UUID()
        let cacheState = WorkspacePersistor.PersistableCacheState(
            workspaceId: workspaceId,
            repoEnrichmentByRepoId: [
                repoId: .resolvedRemote(
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
        let loaded = persistor.loadCache(for: workspaceId).value

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
        let loaded = persistor.loadUI(for: workspaceId).value

        #expect(loaded?.workspaceId == workspaceId)
        #expect(loaded?.expandedGroups == ["askluna", "personal"])
        #expect(loaded?.checkoutColors["repoA"] == "#22cc88")
        #expect(loaded?.filterText == "forge")
        #expect(loaded?.isFilterVisible == true)
    }

    @Test
    func test_loadCache_corruptJson_returnsCorrupt() throws {
        let workspaceId = UUID()
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.cache.json")
        let data = Data("{not-valid-json}".utf8)
        try data.write(to: cacheURL, options: .atomic)

        #expect(persistor.loadCache(for: workspaceId).isCorrupt)
    }

    @Test
    func test_loadUI_corruptJson_returnsCorrupt() throws {
        let workspaceId = UUID()
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        let data = Data("{not-valid-json}".utf8)
        try data.write(to: uiURL, options: .atomic)

        #expect(persistor.loadUI(for: workspaceId).isCorrupt)
    }

    // MARK: - Strict Decoding (no legacy fallbacks)

    @Test
    func test_load_canonicalState_missingWorktrees_returnsCorrupt() throws {
        // Arrange — JSON with all required fields except `worktrees`
        let id = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "id": "\(id.uuidString)",
                "name": "Test",
                "repos": [],
                "unavailableRepoIds": [],
                "panes": [],
                "tabs": [],
                "sidebarWidth": 250,
                "createdAt": 0,
                "updatedAt": 0
            }
            """
        let fileURL = tempDir.appending(path: "\(id.uuidString).workspace.state.json")
        try Data(json.utf8).write(to: fileURL, options: .atomic)

        // Act & Assert — missing `worktrees` must be rejected, not silently defaulted
        #expect(persistor.load().isCorrupt)
    }

    @Test
    func test_load_canonicalState_missingSchemaVersion_returnsCorrupt() throws {
        // Arrange — JSON with all required fields except `schemaVersion`
        let id = UUID()
        let json = """
            {
                "id": "\(id.uuidString)",
                "name": "Test",
                "repos": [],
                "worktrees": [],
                "unavailableRepoIds": [],
                "panes": [],
                "tabs": [],
                "sidebarWidth": 250,
                "createdAt": 0,
                "updatedAt": 0
            }
            """
        let fileURL = tempDir.appending(path: "\(id.uuidString).workspace.state.json")
        try Data(json.utf8).write(to: fileURL, options: .atomic)

        // Act & Assert — missing `schemaVersion` must be rejected, not defaulted to 0
        #expect(persistor.load().isCorrupt)
    }

    @Test
    func test_loadCache_missingRequiredField_returnsCorrupt() throws {
        // Arrange — cache JSON missing required `repoEnrichmentByRepoId`
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "worktreeEnrichmentByWorktreeId": {},
                "pullRequestCountByWorktreeId": {},
                "notificationCountByWorktreeId": {},
                "sourceRevision": 0
            }
            """
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.cache.json")
        try Data(json.utf8).write(to: cacheURL, options: .atomic)

        // Act & Assert — missing `repoEnrichmentByRepoId` must be rejected, not silently defaulted
        #expect(persistor.loadCache(for: workspaceId).isCorrupt)
    }

    @Test
    func test_loadUI_missingRequiredField_returnsCorrupt() throws {
        // Arrange — UI JSON missing required `expandedGroups`
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "checkoutColors": {},
                "filterText": "",
                "isFilterVisible": false
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        // Act & Assert — missing `expandedGroups` must be rejected, not silently defaulted
        #expect(persistor.loadUI(for: workspaceId).isCorrupt)
    }

}
