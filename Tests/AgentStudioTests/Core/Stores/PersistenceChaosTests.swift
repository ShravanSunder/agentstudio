import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PersistenceChaosTests {
    @Test("workspace persistor handles every chaos flavor")
    func workspacePersistorHandlesEveryChaosFlavor() throws {
        for flavor in ChaosStoreSeeder.Flavor.allCases {
            let workspaceId = UUID()
            let tempDir = makeTempDir("workspace-persistor-chaos")
            let persistor = WorkspacePersistor(workspacesDir: tempDir)
            let url = tempDir.appending(path: "\(workspaceId.uuidString).workspace.state.json")
            try ChaosStoreSeeder.seed(
                flavor,
                at: url,
                payloads: .init(
                    validJSON: workspaceJSON(workspaceId: workspaceId, schemaVersion: 1),
                    sliceMissingJSON: """
                        {"schemaVersion":1,"id":"\(workspaceId.uuidString)"}
                        """,
                    sliceTypeErrorJSON: """
                        {"schemaVersion":1,"id":"\(workspaceId.uuidString)","name":42}
                        """,
                    sliceUnknownEnumJSON: workspaceJSON(workspaceId: workspaceId, schemaVersion: 1),
                    unknownSchemaVersionJSON: workspaceJSON(workspaceId: workspaceId, schemaVersion: 99_999)
                )
            )

            let result = persistor.load()

            switch flavor {
            case .missing:
                #expect(result.isMissingForChaos)
            case _ where flavor.corruptsWholeFile:
                #expect(result.isCorruptForChaos)
            default:
                #expect(result.valueForChaos?.id == workspaceId)
            }
        }
    }

    @Test("repo cache store handles every chaos flavor")
    func repoCacheStoreHandlesEveryChaosFlavor() throws {
        for flavor in ChaosStoreSeeder.Flavor.allCases {
            let workspaceId = UUID()
            let tempDir = makeTempDir("repo-cache-chaos")
            let persistor = WorkspacePersistor(workspacesDir: tempDir)
            let url = tempDir.appending(path: "\(workspaceId.uuidString).workspace.cache.json")
            try ChaosStoreSeeder.seed(
                flavor,
                at: url,
                payloads: .init(
                    validJSON: cacheJSON(workspaceId: workspaceId, schemaVersion: 1),
                    sliceMissingJSON: """
                        {"schemaVersion":1,"workspaceId":"\(workspaceId.uuidString)"}
                        """,
                    sliceTypeErrorJSON: """
                        {"schemaVersion":1,"workspaceId":"\(workspaceId.uuidString)","sourceRevision":"bad"}
                        """,
                    sliceUnknownEnumJSON: cacheJSON(workspaceId: workspaceId, schemaVersion: 1),
                    unknownSchemaVersionJSON: cacheJSON(workspaceId: workspaceId, schemaVersion: 99_999)
                )
            )

            let atom = RepoCacheAtom()
            RepoCacheStore(atom: atom, persistor: persistor).restore(for: workspaceId)

            #expect(atom.repoEnrichmentByRepoId.isEmpty)
            #expect(atom.worktreeEnrichmentByWorktreeId.isEmpty)
        }
    }

    @Test("ui state store handles every chaos flavor")
    func uiStateStoreHandlesEveryChaosFlavor() throws {
        for flavor in ChaosStoreSeeder.Flavor.allCases {
            let workspaceId = UUID()
            let tempDir = makeTempDir("ui-state-chaos")
            let persistor = WorkspacePersistor(workspacesDir: tempDir)
            let url = tempDir.appending(path: "\(workspaceId.uuidString).workspace.ui.json")
            try ChaosStoreSeeder.seed(
                flavor,
                at: url,
                payloads: .init(
                    validJSON: uiJSON(workspaceId: workspaceId, schemaVersion: 1, sidebarSurface: "inbox"),
                    sliceMissingJSON: """
                        {"schemaVersion":1,"workspaceId":"\(workspaceId.uuidString)"}
                        """,
                    sliceTypeErrorJSON: """
                        {"schemaVersion":1,"workspaceId":"\(workspaceId.uuidString)","showMinimizedBars":"bad"}
                        """,
                    sliceUnknownEnumJSON: uiJSON(
                        workspaceId: workspaceId,
                        schemaVersion: 1,
                        sidebarSurface: "not-a-surface"
                    ),
                    unknownSchemaVersionJSON: uiJSON(
                        workspaceId: workspaceId,
                        schemaVersion: 99_999,
                        sidebarSurface: "inbox"
                    )
                )
            )

            let atom = UIStateAtom()
            UIStateStore(atom: atom, persistor: persistor).restore(for: workspaceId)

            #expect(atom.sidebarHasFocus == false)
        }
    }

    @Test("sidebar cache store handles every chaos flavor")
    func sidebarCacheStoreHandlesEveryChaosFlavor() throws {
        for flavor in ChaosStoreSeeder.Flavor.allCases {
            let workspaceId = UUID()
            let tempDir = makeTempDir("sidebar-cache-chaos")
            let persistor = WorkspacePersistor(workspacesDir: tempDir)
            let url = tempDir.appending(path: "\(workspaceId.uuidString).workspace.sidebar-cache.json")
            try ChaosStoreSeeder.seed(
                flavor,
                at: url,
                payloads: .init(
                    validJSON: sidebarCacheJSON(workspaceId: workspaceId, schemaVersion: 1),
                    sliceMissingJSON: """
                        {"schemaVersion":1,"workspaceId":"\(workspaceId.uuidString)"}
                        """,
                    sliceTypeErrorJSON: """
                        {"schemaVersion":1,"workspaceId":"\(workspaceId.uuidString)","expandedGroups":42}
                        """,
                    sliceUnknownEnumJSON: sidebarCacheJSON(workspaceId: workspaceId, schemaVersion: 1),
                    unknownSchemaVersionJSON: sidebarCacheJSON(workspaceId: workspaceId, schemaVersion: 99_999)
                )
            )

            let atom = SidebarCacheAtom()
            SidebarCacheStore(atom: atom, persistor: persistor).restore(for: workspaceId)

            #expect(atom.expandedGroups.count <= 1)
            #expect(atom.collapsedInboxGroups.count <= 1)
        }
    }

    @Test("inbox notification store handles every chaos flavor")
    func inboxNotificationStoreHandlesEveryChaosFlavor() throws {
        for flavor in ChaosStoreSeeder.Flavor.allCases {
            let tempDir = makeTempDir("inbox-notification-chaos")
            let url = tempDir.appending(path: "notification-inbox.json")
            try ChaosStoreSeeder.seed(
                flavor,
                at: url,
                payloads: .init(
                    validJSON: inboxJSON(schemaVersion: 1, grouping: "byRepo"),
                    sliceMissingJSON: """
                        {"schemaVersion":1}
                        """,
                    sliceTypeErrorJSON: """
                        {"schemaVersion":1,"notifications":42,"prefs":{"grouping":"byRepo","sort":"newestFirst","bellEnabled":true}}
                        """,
                    sliceUnknownEnumJSON: inboxJSON(schemaVersion: 1, grouping: "not-a-group"),
                    unknownSchemaVersionJSON: inboxJSON(schemaVersion: 99_999, grouping: "byRepo")
                )
            )

            let inboxAtom = InboxNotificationAtom()
            let prefsAtom = InboxNotificationPrefsAtom()
            let store = InboxNotificationStore(
                inboxAtom: inboxAtom,
                prefsAtom: prefsAtom,
                fileURL: url
            )

            try? store.load()

            #expect(inboxAtom.notifications.isEmpty)
        }
    }

    private func makeTempDir(_ prefix: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func workspaceJSON(workspaceId: UUID, schemaVersion: Int) -> String {
        """
        {
            "schemaVersion": \(schemaVersion),
            "id": "\(workspaceId.uuidString)",
            "name": "Test",
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
    }

    private func cacheJSON(workspaceId: UUID, schemaVersion: Int) -> String {
        """
        {
            "schemaVersion": \(schemaVersion),
            "workspaceId": "\(workspaceId.uuidString)",
            "repoEnrichmentByRepoId": {},
            "worktreeEnrichmentByWorktreeId": {},
            "pullRequestCountByWorktreeId": {},
            "notificationCountByWorktreeId": {},
            "recentTargets": [],
            "sourceRevision": 0,
            "lastRebuiltAt": null
        }
        """
    }

    private func uiJSON(workspaceId: UUID, schemaVersion: Int, sidebarSurface: String) -> String {
        """
        {
            "schemaVersion": \(schemaVersion),
            "workspaceId": "\(workspaceId.uuidString)",
            "filterText": "",
            "isFilterVisible": false,
            "showMinimizedBars": true,
            "sidebarCollapsed": false,
            "sidebarSurface": "\(sidebarSurface)",
            "editorChooserState": {}
        }
        """
    }

    private func sidebarCacheJSON(workspaceId: UUID, schemaVersion: Int) -> String {
        """
        {
            "schemaVersion": \(schemaVersion),
            "workspaceId": "\(workspaceId.uuidString)",
            "expandedGroups": ["repo:agent-studio"],
            "checkoutColors": {"repo:agent-studio": "#ff6600"},
            "collapsedInboxGroups": ["__ungrouped__"]
        }
        """
    }

    private func inboxJSON(schemaVersion: Int, grouping: String) -> String {
        """
        {
            "schemaVersion": \(schemaVersion),
            "notifications": [],
            "prefs": {
                "grouping": "\(grouping)",
                "sort": "newestFirst",
                "bellEnabled": true
            }
        }
        """
    }
}

extension WorkspacePersistor.LoadResult {
    fileprivate var valueForChaos: T? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    fileprivate var isMissingForChaos: Bool {
        if case .missing = self { return true }
        return false
    }

    fileprivate var isCorruptForChaos: Bool {
        if case .corrupt = self { return true }
        return false
    }
}
