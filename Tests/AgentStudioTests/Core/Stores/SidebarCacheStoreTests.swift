import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct SidebarCacheStoreTests {
    private let tempDir: URL
    private let persistor: WorkspacePersistor

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "sidebar-cache-store-tests-\(UUID().uuidString)")
        persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
    }

    @Test
    func flushAndRestore_roundTripsExpandedGroupsOnly() async throws {
        let workspaceId = UUID()
        let atom = SidebarCacheState()
        let store = SidebarCacheStore(atom: atom, persistor: persistor)

        atom.setGroupExpanded("repo:agent-studio", isExpanded: true)
        atom.setCheckoutColor("#ff6600", for: SidebarCheckoutColorKey("repo:agent-studio"))

        try await store.flushAsync(for: workspaceId)

        let restoredAtom = SidebarCacheState()
        await SidebarCacheStore(atom: restoredAtom, persistor: persistor).restoreAsync(for: workspaceId)

        #expect(restoredAtom.expandedGroups == [SidebarGroupKey("repo:agent-studio")])
        #expect(restoredAtom.checkoutColors.isEmpty)
    }

    @Test
    func flushAndRestore_roundTripsExpandedGroupsThroughLocalSQLite() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atom = SidebarCacheState()
        let store = SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )

        atom.setGroupExpanded("repo:agent-studio", isExpanded: true)
        atom.setCheckoutColor("#ff6600", for: SidebarCheckoutColorKey("repo:agent-studio"))

        try await store.flushAsync(for: workspaceId)

        #expect(try fixture.repository.fetchExpandedGroups() == [SidebarGroupKey("repo:agent-studio")])
        guard case .missing = persistor.loadSidebarCache(for: workspaceId) else {
            Issue.record("SQLite-backed sidebar cache flush should not write the legacy JSON sidecar")
            return
        }

        let restoredAtom = SidebarCacheState()
        await SidebarCacheStore(
            atom: restoredAtom,
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        ).restoreAsync(for: workspaceId)

        #expect(restoredAtom.expandedGroups == [SidebarGroupKey("repo:agent-studio")])
        #expect(restoredAtom.checkoutColors.isEmpty)
    }

    @Test
    func restoreWithSQLiteBackendImportsLegacyJSONWhenLaneIsMissing() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        try persistor.saveSidebarCache(
            .init(
                workspaceId: workspaceId,
                expandedGroups: [SidebarGroupKey("repo:legacy")],
                checkoutColors: [SidebarCheckoutColorKey("repo:legacy"): "#ff6600"]
            )
        )
        let atom = SidebarCacheState()
        let store = SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )

        await store.restoreAsync(for: workspaceId)

        #expect(atom.expandedGroups == [SidebarGroupKey("repo:legacy")])
        #expect(atom.checkoutColors.isEmpty)
        #expect(try fixture.repository.fetchExpandedGroups() == [SidebarGroupKey("repo:legacy")])
        #expect(try fixture.repository.hasExpandedGroupsState())
    }

    @Test
    func unavailableSQLiteBackendResetsSidebarCacheAndBlocksLegacyArchiveReadiness() async throws {
        let workspaceId = UUID()
        try persistor.saveSidebarCache(
            .init(
                workspaceId: workspaceId,
                expandedGroups: [SidebarGroupKey("repo:legacy")],
                checkoutColors: [SidebarCheckoutColorKey("repo:legacy"): "#ff6600"]
            )
        )
        let atom = SidebarCacheState()
        let store = SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: failingWorkspaceLocalSQLiteBackend())
        )

        await store.restoreAsync(for: workspaceId)

        #expect(atom.expandedGroups.isEmpty)
        #expect(!atom.expandedGroups.contains(SidebarGroupKey("repo:legacy")))
        #expect(!store.canArchiveLegacySidebarCacheFile)
    }

    @Test
    func restoreWithSQLiteBackendDoesNotResurrectLegacyJSONAfterEmptyLaneFlush() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        try persistor.saveSidebarCache(
            .init(
                workspaceId: workspaceId,
                expandedGroups: [SidebarGroupKey("repo:stale")],
                checkoutColors: [:]
            )
        )
        let atom = SidebarCacheState()
        let store = SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )

        try await store.flushAsync(for: workspaceId)
        await store.restoreAsync(for: workspaceId)

        #expect(atom.expandedGroups.isEmpty)
        #expect(try fixture.repository.hasExpandedGroupsState())
    }

    @Test
    func missingSQLiteExpandedGroupsLaneAfterImportResetsInsteadOfReplayingLegacyJSON() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        try persistor.saveSidebarCache(
            .init(
                workspaceId: workspaceId,
                expandedGroups: [SidebarGroupKey("repo:stale")],
                checkoutColors: [:]
            )
        )
        let atom = SidebarCacheState()
        atom.setExpandedGroups([SidebarGroupKey("repo:sqlite")])
        let store = SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )
        try await store.flushAsync(for: workspaceId)
        try await fixture.databaseQueue.write { database in
            try database.execute(
                sql: """
                    DELETE FROM local_persistence_lane_marker
                    WHERE workspace_id = ? AND lane = 'sidebar_expanded_groups'
                    """,
                arguments: [workspaceId.uuidString]
            )
            try database.execute(
                sql: "DELETE FROM local_sidebar_expanded_group WHERE workspace_id = ?",
                arguments: [workspaceId.uuidString]
            )
        }
        let restoredAtom = SidebarCacheState()
        let restoredStore = SidebarCacheStore(
            atom: restoredAtom,
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(
                from: workspaceLocalSQLiteBackendWithImportedLegacyLanes(repository: fixture.repository))
        )

        await restoredStore.restoreAsync(for: workspaceId)

        #expect(restoredAtom.expandedGroups.isEmpty)
        #expect(!restoredAtom.expandedGroups.contains(SidebarGroupKey("repo:stale")))
        #expect(!restoredStore.canArchiveLegacySidebarCacheFile)
    }

    @Test
    func missingSQLiteExpandedGroupsLaneAfterImportDoesNotBlockArchiveWhenLegacySidebarFileIsAbsent() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let restoredAtom = SidebarCacheState()
        let restoredStore = SidebarCacheStore(
            atom: restoredAtom,
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(
                from: workspaceLocalSQLiteBackendWithImportedLegacyLanes(repository: fixture.repository))
        )

        await restoredStore.restoreAsync(for: workspaceId)

        #expect(restoredAtom.expandedGroups.isEmpty)
        #expect(restoredStore.canArchiveLegacySidebarCacheFile)
    }

    @Test
    func restoreWithSQLiteBackendResetsWhenSQLiteExpandedGroupLaneFailsInsteadOfReplayingLegacyJSON() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atom = SidebarCacheState()
        let store = SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )
        atom.setGroupExpanded("repo:sqlite", isExpanded: true)
        try await store.flushAsync(for: workspaceId)
        try persistor.saveSidebarCache(
            .init(
                workspaceId: workspaceId,
                expandedGroups: [SidebarGroupKey("repo:stale")],
                checkoutColors: [:]
            )
        )
        try await fixture.databaseQueue.write { database in
            try database.drop(table: "local_sidebar_expanded_group")
        }

        let restoredAtom = SidebarCacheState()
        let restoredStore = SidebarCacheStore(
            atom: restoredAtom,
            persistor: persistor,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )
        await restoredStore.restoreAsync(for: workspaceId)

        #expect(restoredAtom.expandedGroups.isEmpty)
        #expect(!restoredAtom.expandedGroups.contains(SidebarGroupKey("repo:stale")))
        #expect(!restoredStore.canArchiveLegacySidebarCacheFile)
    }

    @Test
    func observedExpansionChange_autosavesSidebarCache() async throws {
        let workspaceId = UUID()
        let atom = SidebarCacheState()
        let store = SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            persistDebounceDuration: .zero
        )
        await store.restoreAsync(for: workspaceId)
        store.startObserving()

        atom.setGroupExpanded(SidebarGroupKey("repo:agent-studio"), isExpanded: true)

        await assertEventuallyMain("expanded repo group should autosave") {
            switch persistor.loadSidebarCache(for: workspaceId) {
            case .loaded(let cache):
                return cache.expandedGroups == [SidebarGroupKey("repo:agent-studio")]
            case .missing, .corrupt:
                return false
            }
        }
    }

    @Test
    func observedCheckoutColorChangeDoesNotAutosaveSidebarCache() async throws {
        let workspaceId = UUID()
        let atom = SidebarCacheState()
        let store = SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            persistDebounceDuration: .zero
        )
        await store.restoreAsync(for: workspaceId)
        store.startObserving()

        atom.setCheckoutColor("#22cc88", for: SidebarCheckoutColorKey("repo:agent-studio"))

        await assertEventuallyMain("checkout color mutation should not autosave sidebar cache") {
            if case .missing = persistor.loadSidebarCache(for: workspaceId) { return true }
            return false
        }
    }

    @Test
    func directExpandedGroupMutation_autosavesWithoutCheckoutColors() async throws {
        let workspaceId = UUID()
        let expandedGroupAtom = SidebarExpandedGroupAtom()
        let checkoutColorAtom = SidebarCheckoutColorAtom()
        let atom = SidebarCacheState(
            expandedGroupAtom: expandedGroupAtom,
            checkoutColorAtom: checkoutColorAtom
        )
        let store = SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            persistDebounceDuration: .zero
        )
        await store.restoreAsync(for: workspaceId)
        store.startObserving()

        expandedGroupAtom.setGroupExpanded(SidebarGroupKey("repo:agent-studio"), isExpanded: true)
        checkoutColorAtom.setCheckoutColor("#22cc88", for: SidebarCheckoutColorKey("repo:agent-studio"))

        await assertEventuallyMain("write-owner mutations should autosave through composed state") {
            switch persistor.loadSidebarCache(for: workspaceId) {
            case .loaded(let cache):
                return cache.expandedGroups == [SidebarGroupKey("repo:agent-studio")]
                    && cache.checkoutColors.isEmpty
            case .missing, .corrupt:
                return false
            }
        }
    }

    @Test
    func restore_cancelsPendingDebouncedSaveForPreviousWorkspace() async throws {
        let workspaceAId = UUID()
        let workspaceBId = UUID()
        try persistor.saveSidebarCache(
            .init(
                workspaceId: workspaceBId,
                expandedGroups: [SidebarGroupKey("repo:workspace-b")],
                checkoutColors: [:]
            )
        )
        let atom = SidebarCacheState()
        let clock = TestPushClock()
        let store = SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )

        await store.restoreAsync(for: workspaceAId)
        store.startObserving()
        atom.setGroupExpanded(SidebarGroupKey("repo:workspace-a"), isExpanded: true)
        await clock.waitForPendingSleepCount()
        await store.restoreAsync(for: workspaceBId)
        clock.advance(by: .milliseconds(10))
        await Task.yield()

        guard case .missing = persistor.loadSidebarCache(for: workspaceAId) else {
            Issue.record("Expected stale workspace A debounce to be cancelled")
            return
        }
    }

    @Test
    func restore_corruptSidebarCacheFile_fallsBackToDefaultsAndQuarantines() async throws {
        let workspaceId = UUID()
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.sidebar-cache.json")
        try Data("not-json".utf8).write(to: cacheURL, options: .atomic)
        var reportedRecovery: PersistenceRecoveryEvent?

        let atom = SidebarCacheState()
        await SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            recoveryReporter: { reportedRecovery = $0 }
        ).restoreAsync(for: workspaceId)

        #expect(atom.expandedGroups.isEmpty)
        #expect(atom.checkoutColors.isEmpty)
        #expect(reportedRecovery?.store == .sidebarCache)
        #expect(reportedRecovery?.workspaceId == workspaceId)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)

        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("\(workspaceId.uuidString).workspace.sidebar-cache.corrupt-")
        }
        #expect(quarantinedFiles.count == 1)
    }

    @Test
    func restore_missingSidebarCacheFile_keepsDefaults() async {
        let workspaceId = UUID()
        let atom = SidebarCacheState()

        await SidebarCacheStore(atom: atom, persistor: persistor).restoreAsync(for: workspaceId)

        #expect(atom.expandedGroups.isEmpty)
        #expect(atom.checkoutColors.isEmpty)
    }

    @Test
    func autosaveObservationStateIsExplicitlyArmed() async {
        let workspaceId = UUID()
        let store = SidebarCacheStore(atom: SidebarCacheState(), persistor: persistor)

        #expect(store.isAutosaveObservationActive == false)
        await store.restoreAsync(for: workspaceId)
        #expect(store.isAutosaveObservationActive == false)
        store.startObserving()
        #expect(store.isAutosaveObservationActive == true)
    }

    @Test
    func flushFailure_reportsSaveFailedRecovery() async {
        let workspaceId = UUID()
        let blockedDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: "sidebar-cache-blocked-\(UUID().uuidString)")
        try? Data("not-a-directory".utf8).write(to: blockedDirectoryURL, options: .atomic)
        let atom = SidebarCacheState()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = SidebarCacheStore(
            atom: atom,
            persistor: WorkspacePersistor(workspacesDir: blockedDirectoryURL),
            recoveryReporter: { reportedRecovery = $0 }
        )

        do {
            try await store.flushAsync(for: workspaceId)
            Issue.record("Expected sidebar cache flush to fail")
        } catch {
            // Expected path.
        }

        #expect(reportedRecovery?.store == .sidebarCache)
        #expect(reportedRecovery?.workspaceId == workspaceId)
        #expect(reportedRecovery?.recovery == .saveFailed)
    }

    @Test
    func restoreLegacyCheckoutColorsLeavesSettingsOwnedAtomUntouched() async throws {
        let workspaceId = UUID()
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.sidebar-cache.json")
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "checkoutColors": {"repo:agent-studio": "#ff6600"}
            }
            """
        try Data(json.utf8).write(to: cacheURL, options: .atomic)

        let atom = SidebarCacheState()
        atom.setCheckoutColor("#22cc88", for: SidebarCheckoutColorKey("repo:live"))
        await SidebarCacheStore(atom: atom, persistor: persistor).restoreAsync(for: workspaceId)

        #expect(atom.expandedGroups.isEmpty)
        #expect(atom.checkoutColors == [SidebarCheckoutColorKey("repo:live"): "#22cc88"])
    }
}
