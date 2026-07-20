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
    func test_defaultWorkspacesDir_usesDebugAppDataRoot() {
        let defaultPersistor = WorkspacePersistor()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        #expect(defaultPersistor.workspacesDir.path == "\(homeDir)/.agentstudio-db/workspaces")
    }

    // MARK: - Delete

    @Test
    func test_delete_removesNotificationInboxFile() throws {
        let workspaceId = UUIDv7.generate()
        let inboxFileURL = persistor.notificationInboxFileURL(for: workspaceId)
        #expect(persistor.ensureDirectory())
        try Data("{}".utf8).write(to: inboxFileURL, options: .atomic)
        #expect(FileManager.default.fileExists(atPath: inboxFileURL.path))

        persistor.delete(id: workspaceId)

        #expect(!FileManager.default.fileExists(atPath: inboxFileURL.path))
    }

    // MARK: - Schema Version

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

    @Test
    func test_unknownSchemaVersion_returnsCorrupt() throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 99999,
                "workspaceId": "\(workspaceId.uuidString)",
                "expandedGroups": ["repo:agent-studio"],
                "checkoutColors": {}
            }
            """
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.sidebar-cache.json")
        try Data(json.utf8).write(to: cacheURL, options: .atomic)

        #expect(persistor.loadSidebarCache(for: workspaceId).isCorrupt)
    }

    @Test
    func test_missingPersistedIdentity_returnsCorrupt() throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "expandedGroups": ["repo:agent-studio"],
                "checkoutColors": {}
            }
            """
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.sidebar-cache.json")
        try Data(json.utf8).write(to: cacheURL, options: .atomic)

        #expect(persistor.loadSidebarCache(for: workspaceId).isCorrupt)
    }

    // MARK: - Cache State

    @Test
    func test_saveAndLoad_cacheState() throws {
        let workspaceId = UUID()
        let repoId = UUID()
        let worktreeId = UUID()
        let recentTarget = RecentWorkspaceTarget.forWorktree(
            path: URL(fileURLWithPath: "/tmp/agent-studio"),
            worktree: Worktree(
                id: worktreeId,
                repoId: repoId,
                name: "agent-studio",
                path: URL(fileURLWithPath: "/tmp/agent-studio"),
                isMainWorktree: true
            ),
            repo: Repo(
                id: repoId,
                name: "agent-studio",
                repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
                worktrees: [],
                createdAt: Date()
            ),
            displayTitle: "agent-studio",
            subtitle: "main",
            lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_123)
        )
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
            recentTargets: [recentTarget],
            sourceRevision: 10,
            lastRebuiltAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try persistor.saveCache(cacheState)
        let loaded = persistor.loadCache(for: workspaceId).value

        #expect(loaded?.workspaceId == workspaceId)
        #expect(loaded?.repoEnrichmentByRepoId[repoId]?.organizationName == "askluna")
        #expect(loaded?.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main")
        #expect(loaded?.pullRequestCountByWorktreeId[worktreeId] == 2)
        #expect(loaded?.recentTargets == [recentTarget])
        #expect(loaded?.sourceRevision == 10)
    }

    @Test
    func test_loadCache_missingRecentTargets_defaultsToEmpty() throws {
        let workspaceId = UUID()
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.cache.json")
        let baseline = WorkspacePersistor.PersistableCacheState(
            workspaceId: workspaceId,
            sourceRevision: 7,
            lastRebuiltAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let baselineData = try encoder.encode(baseline)
        let rawObject = try JSONSerialization.jsonObject(with: baselineData, options: [])
        guard var dictionary = rawObject as? [String: Any] else {
            Issue.record("Expected baseline cache JSON dictionary")
            return
        }
        dictionary.removeValue(forKey: "recentTargets")
        let compatibilityData = try JSONSerialization.data(
            withJSONObject: dictionary,
            options: [.prettyPrinted, .sortedKeys]
        )
        try compatibilityData.write(to: cacheURL, options: .atomic)

        let loaded = persistor.loadCache(for: workspaceId).value

        #expect(loaded?.recentTargets.isEmpty == true)
        #expect(loaded?.sourceRevision == 7)
    }

    @Test
    func test_saveAndLoad_uiState() throws {
        let workspaceId = UUID()
        let uiState = WorkspacePersistor.PersistableUIState(
            workspaceId: workspaceId,
            filterText: "forge",
            isFilterVisible: true
        )

        try persistor.saveUI(uiState)
        let loaded = persistor.loadUI(for: workspaceId).value

        #expect(loaded?.workspaceId == workspaceId)
        #expect(loaded?.filterText == "forge")
        #expect(loaded?.isFilterVisible == true)
    }

    @Test
    func test_saveAndLoad_sidebarCache() throws {
        let workspaceId = UUID()
        let sidebarCache = WorkspacePersistor.PersistableSidebarCache(
            workspaceId: workspaceId,
            expandedGroups: [SidebarGroupKey("askluna"), SidebarGroupKey("personal")]
        )

        try persistor.saveSidebarCache(sidebarCache)
        let loaded = persistor.loadSidebarCache(for: workspaceId).value

        #expect(loaded?.workspaceId == workspaceId)
        #expect(loaded?.expandedGroups == [SidebarGroupKey("askluna"), SidebarGroupKey("personal")])
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

    // MARK: - Recoverable Decoding

    @Test
    func test_loadCache_missingRequiredField_defaultsOnlyThatSlice() throws {
        // Arrange — cache JSON missing required `repoEnrichmentByRepoId`
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "worktreeEnrichmentByWorktreeId": {},
                "pullRequestCountByWorktreeId": {},
                "sourceRevision": 0
            }
            """
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.cache.json")
        try Data(json.utf8).write(to: cacheURL, options: .atomic)

        let loaded = persistor.loadCache(for: workspaceId).value

        #expect(loaded?.workspaceId == workspaceId)
        #expect(loaded?.repoEnrichmentByRepoId.isEmpty == true)
        #expect(loaded?.worktreeEnrichmentByWorktreeId.isEmpty == true)
        #expect(loaded?.sourceRevision == 0)
    }

    @Test
    func test_loadCache_sliceTypeError_defaultsBadSlice() throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "repoEnrichmentByRepoId": 42,
                "worktreeEnrichmentByWorktreeId": {},
                "pullRequestCountByWorktreeId": {},
                "recentTargets": [],
                "sourceRevision": 7
            }
            """
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.cache.json")
        try Data(json.utf8).write(to: cacheURL, options: .atomic)

        let loaded = persistor.loadCache(for: workspaceId).value

        #expect(loaded?.workspaceId == workspaceId)
        #expect(loaded?.repoEnrichmentByRepoId.isEmpty == true)
        #expect(loaded?.sourceRevision == 7)
    }

    @Test
    func test_loadUI_missingOptionalCompositionFields_defaults() throws {
        // Arrange — UI JSON missing optional composition fields.
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "filterText": "",
                "isFilterVisible": false
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        // Act & Assert — UI composition fields default without corrupting the whole file.
        let loaded = persistor.loadUI(for: workspaceId).value
        #expect(loaded?.sidebarCollapsed == false)
        #expect(loaded?.sidebarSurface == .repos)
    }

    @Test
    func test_loadUI_sliceTypeError_defaultsBadSlice() throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "filterText": 42,
                "isFilterVisible": "bad-value",
                "showMinimizedBars": false,
                "sidebarCollapsed": true,
                "sidebarSurface": "inbox"
            }
            """
        let uiURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
        try Data(json.utf8).write(to: uiURL, options: .atomic)

        let loaded = persistor.loadUI(for: workspaceId).value

        #expect(loaded?.filterText.isEmpty == true)
        #expect(loaded?.isFilterVisible == false)
        #expect(loaded?.sidebarCollapsed == true)
        #expect(loaded?.sidebarSurface == .inbox)
    }

    @Test
    func test_loadSidebarCache_sliceTypeError_defaultsBadSlice() throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "expandedGroups": 42,
                "checkoutColors": {"repoA": "#22cc88"}
            }
            """
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.sidebar-cache.json")
        try Data(json.utf8).write(to: cacheURL, options: .atomic)

        let loaded = persistor.loadSidebarCache(for: workspaceId).value

        #expect(loaded?.expandedGroups.isEmpty == true)
    }

}
