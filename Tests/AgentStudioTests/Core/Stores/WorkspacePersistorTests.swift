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
    func test_loadMultipleCanonicalFiles_choosesDeterministicFilenameOrder() throws {
        let laterId = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let earlierId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        try persistor.save(.init(id: laterId, name: "later"))
        try persistor.save(.init(id: earlierId, name: "earlier"))

        let loaded = persistor.load().value

        #expect(loaded?.id == earlierId)
        #expect(loaded?.name == "earlier")
    }

    @Test
    func test_saveAndLoad_withPanes() throws {
        // Arrange
        let pane = makePane(
            launchDirectory: URL(fileURLWithPath: "/tmp/worktree"),
            title: "Feature",
            provider: .zmx,
            lifetime: .persistent,
            residency: .active,
            facets: PaneContextFacets(
                repoId: UUID(),
                worktreeId: UUID(),
                cwd: URL(fileURLWithPath: "/tmp/worktree")
            )
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
    func test_load_canonicalState_missingWatchedPaths_defaultsOnlyThatSlice() throws {
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

        // Assert — missing recoverable fields default without wiping the workspace.
        let loaded = result.value
        #expect(loaded?.id == workspaceId)
        #expect(loaded?.name == "Test Workspace")
        #expect(loaded?.watchedPaths.isEmpty == true)
    }

    @Test
    func test_load_canonicalState_oldArrangementShape_returnsCorrupt() throws {
        let workspaceId = UUID()
        let tabId = UUID()
        let arrangementId = UUID()
        let paneId = UUID()
        let json = """
            {
              "schemaVersion": 1,
              "id": "\(workspaceId.uuidString)",
              "name": "Test Workspace",
              "repos": [],
              "worktrees": [],
              "unavailableRepoIds": [],
              "panes": [],
              "tabs": [
                {
                  "id": "\(tabId.uuidString)",
                  "name": "Tab",
                  "panes": ["\(paneId.uuidString)"],
                  "arrangements": [
                    {
                      "id": "\(arrangementId.uuidString)",
                      "name": "Default",
                      "isDefault": true,
                      "layout": {
                        "panes": [
                          { "paneId": "\(paneId.uuidString)", "ratio": 1 }
                        ],
                        "dividerIds": []
                      },
                      "visiblePaneIds": ["\(paneId.uuidString)"]
                    }
                  ],
                  "activeArrangementId": "\(arrangementId.uuidString)"
                }
              ],
              "sidebarWidth": 250,
              "createdAt": "\(ISO8601DateFormatter().string(from: Date()))",
              "updatedAt": "\(ISO8601DateFormatter().string(from: Date()))"
            }
            """
        let stateURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.state.json")
        try Data(json.utf8).write(to: stateURL, options: .atomic)

        #expect(persistor.load().isCorrupt)
    }

    @Test
    func test_load_canonicalState_legacyDrawerActivePaneId_doesNotCorruptWorkspace() throws {
        try assertLegacyDrawerActivePaneIdRoutesToDrawerView(using: .alternatingArray)
    }

    @Test
    func test_load_canonicalState_keyedDrawerViews_legacyDrawerActivePaneId_doesNotCorruptWorkspace() throws {
        try assertLegacyDrawerActivePaneIdRoutesToDrawerView(using: .keyedObject)
    }

    private enum LegacyDrawerViewsShape {
        case alternatingArray
        case keyedObject
    }

    private func assertLegacyDrawerActivePaneIdRoutesToDrawerView(
        using drawerViewsShape: LegacyDrawerViewsShape
    ) throws {
        let firstDrawerChildPaneId = UUIDv7.generate()
        let secondDrawerChildPaneId = UUIDv7.generate()
        var parentPane = makePane()
        parentPane.withDrawer { drawer in
            drawer.paneIds = [firstDrawerChildPaneId, secondDrawerChildPaneId]
        }
        guard let drawerId = parentPane.drawer?.drawerId else {
            Issue.record("Parent pane did not receive a drawer")
            return
        }
        let firstDrawerChildPane = Pane(
            id: firstDrawerChildPaneId,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(title: "First Drawer Child"),
            kind: .drawerChild(parentPaneId: parentPane.id)
        )
        let secondDrawerChildPane = Pane(
            id: secondDrawerChildPaneId,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: PaneMetadata(title: "Second Drawer Child"),
            kind: .drawerChild(parentPaneId: parentPane.id)
        )
        var tab = Tab(paneId: parentPane.id)
        tab.arrangements[0].drawerViews[drawerId] = DrawerView(
            layout: DrawerGridLayout(topRow: Layout.autoTiled([firstDrawerChildPaneId, secondDrawerChildPaneId])),
            activeChildId: firstDrawerChildPaneId
        )
        var state = WorkspacePersistor.PersistableState(
            panes: [parentPane, firstDrawerChildPane, secondDrawerChildPane],
            tabs: [tab]
        )
        state.activeTabId = tab.id
        try persistor.save(state)

        let stateURL = tempDir.appending(path: "\(state.id.uuidString).workspace.state.json")
        let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL))
        guard
            var root = payload as? [String: Any],
            var panes = root["panes"] as? [[String: Any]],
            var parentPanePayload = panes.first(where: { ($0["id"] as? String) == parentPane.id.uuidString }),
            var kindPayload = parentPanePayload["kind"] as? [String: Any],
            var layoutPayload = kindPayload["layout"] as? [String: Any],
            var drawerPayload = layoutPayload["drawer"] as? [String: Any],
            var tabs = root["tabs"] as? [[String: Any]],
            var firstTab = tabs.first,
            var arrangements = firstTab["arrangements"] as? [[String: Any]],
            var firstArrangement = arrangements.first,
            var drawerViews = firstArrangement["drawerViews"] as? [Any],
            let drawerViewKeyIndex = drawerViews.firstIndex(where: { ($0 as? String) == drawerId.uuidString }),
            drawerViews.indices.contains(drawerViewKeyIndex + 1),
            var drawerViewPayload = drawerViews[drawerViewKeyIndex + 1] as? [String: Any]
        else {
            Issue.record("Unable to locate encoded parent drawer and arrangement drawer view payload")
            return
        }
        drawerPayload["activePaneId"] = secondDrawerChildPaneId.uuidString
        layoutPayload["drawer"] = drawerPayload
        kindPayload["layout"] = layoutPayload
        parentPanePayload["kind"] = kindPayload
        if let parentIndex = panes.firstIndex(where: { ($0["id"] as? String) == parentPane.id.uuidString }) {
            panes[parentIndex] = parentPanePayload
        }
        root["panes"] = panes
        drawerViewPayload.removeValue(forKey: "activeChildId")
        switch drawerViewsShape {
        case .alternatingArray:
            drawerViews[drawerViewKeyIndex + 1] = drawerViewPayload
            firstArrangement["drawerViews"] = drawerViews
        case .keyedObject:
            firstArrangement["drawerViews"] = [drawerId.uuidString: drawerViewPayload]
        }
        arrangements[0] = firstArrangement
        firstTab["arrangements"] = arrangements
        tabs[0] = firstTab
        root["tabs"] = tabs
        let legacyData = try JSONSerialization.data(withJSONObject: root)
        try legacyData.write(to: stateURL, options: Data.WritingOptions.atomic)

        let loaded = persistor.load().value

        #expect(loaded?.id == state.id)
        #expect(loaded?.panes.count == 3)
        #expect(
            loaded?.panes.first { $0.id == parentPane.id }?.drawer?.paneIds == [
                firstDrawerChildPaneId,
                secondDrawerChildPaneId,
            ]
        )
        #expect(loaded?.tabs.first?.arrangements.first?.drawerViews[drawerId]?.activeChildId == secondDrawerChildPaneId)
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

    @Test
    func test_delete_removesNotificationInboxFile() throws {
        let state = WorkspacePersistor.PersistableState()
        let inboxFileURL = persistor.notificationInboxFileURL(for: state.id)
        #expect(persistor.ensureDirectory())
        try Data("{}".utf8).write(to: inboxFileURL, options: .atomic)
        #expect(FileManager.default.fileExists(atPath: inboxFileURL.path))

        persistor.delete(id: state.id)

        #expect(!FileManager.default.fileExists(atPath: inboxFileURL.path))
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

    @Test
    func test_canonicalStateMissingIdentity_returnsCorrupt() throws {
        let workspaceId = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "name": "Missing Identity",
                "repos": [],
                "worktrees": [],
                "unavailableRepoIds": [],
                "panes": [],
                "tabs": [],
                "activeTabId": null,
                "sidebarWidth": 250,
                "windowFrame": null,
                "watchedPaths": [],
                "createdAt": 0,
                "updatedAt": 0
            }
            """
        let stateURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.state.json")
        try Data(json.utf8).write(to: stateURL, options: .atomic)

        #expect(persistor.load().isCorrupt)
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
            expandedGroups: [SidebarGroupKey("askluna"), SidebarGroupKey("personal")],
            checkoutColors: [SidebarCheckoutColorKey("repoA"): "#22cc88"]
        )

        try persistor.saveSidebarCache(sidebarCache)
        let loaded = persistor.loadSidebarCache(for: workspaceId).value

        #expect(loaded?.workspaceId == workspaceId)
        #expect(loaded?.expandedGroups == [SidebarGroupKey("askluna"), SidebarGroupKey("personal")])
        #expect(loaded?.checkoutColors[SidebarCheckoutColorKey("repoA")] == "#22cc88")
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
    func test_load_canonicalState_missingWorktrees_defaultsOnlyThatSlice() throws {
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

        let loaded = persistor.load().value

        #expect(loaded?.id == id)
        #expect(loaded?.name == "Test")
        #expect(loaded?.repos.isEmpty == true)
        #expect(loaded?.worktrees.isEmpty == true)
    }

    @Test
    func test_load_canonicalState_badSidebarWidth_defaultsOnlyThatSlice() throws {
        let id = UUID()
        let json = """
            {
                "schemaVersion": 1,
                "id": "\(id.uuidString)",
                "name": "Test",
                "repos": [],
                "worktrees": [],
                "unavailableRepoIds": [],
                "panes": [],
                "tabs": [],
                "activeTabId": null,
                "sidebarWidth": "wide",
                "windowFrame": null,
                "watchedPaths": [],
                "createdAt": 0,
                "updatedAt": 0
            }
            """
        let fileURL = tempDir.appending(path: "\(id.uuidString).workspace.state.json")
        try Data(json.utf8).write(to: fileURL, options: .atomic)

        let loaded = persistor.load().value

        #expect(loaded?.id == id)
        #expect(loaded?.sidebarWidth == 250)
        #expect(loaded?.tabs.isEmpty == true)
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

        #expect(persistor.load().isCorrupt)
    }

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
        #expect(loaded?.checkoutColors == [SidebarCheckoutColorKey("repoA"): "#22cc88"])
    }

}
