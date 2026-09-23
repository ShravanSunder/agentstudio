import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

/// Real file-backed SQLite: drawer presentation choices survive ordinary
/// restart, close/undo, and the one-time legacy global-height cutover.
@MainActor
@Suite("Workspace drawer presentation persistence", .serialized)
struct WorkspaceDrawerPresentationPersistenceTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("independent owner heights and sides survive an ordinary restart")
    func independentPreferencesSurviveRestart() async throws {
        let databases = try DrawerPresentationDatabases()
        defer { databases.remove() }
        let store = try await databases.bootStore()
        let paneA = appendTabbedPane(to: store)
        let paneB = appendTabbedPane(to: store)

        store.paneAtom.setDrawerNormalHeightRatio(0.4, forOwner: paneA.id)
        store.paneAtom.setDrawerZoomSide(.bridge, forOwner: paneA.id)
        store.paneAtom.setDrawerNormalHeightRatio(0.6, forOwner: paneB.id)
        #expect(await store.flushAsync() == .persisted)

        let restored = try await databases.bootStore()
        #expect(
            restored.paneAtom.drawerPresentationPreference(forOwner: paneA.id)
                == DrawerPresentationPreference(normalHeightRatio: 0.4, zoomSide: .bridge)
        )
        #expect(
            restored.paneAtom.drawerPresentationPreference(forOwner: paneB.id)
                == DrawerPresentationPreference(normalHeightRatio: 0.6, zoomSide: .terminal)
        )
    }

    @Test("a closed owner keeps its choices through save, restart, and undo")
    func closedOwnerKeepsPreferencesThroughRestartAndUndo() async throws {
        let databases = try DrawerPresentationDatabases()
        defer { databases.remove() }
        let store = try await databases.bootStore()
        let keptPane = appendTabbedPane(to: store)
        let closedPane = store.createPane()
        let closedTab = Tab(paneId: closedPane.id)
        store.appendTab(closedTab)
        store.paneAtom.setDrawerNormalHeightRatio(0.35, forOwner: closedPane.id)
        store.paneAtom.setDrawerZoomSide(.bridge, forOwner: closedPane.id)
        #expect(await store.flushAsync() == .persisted)

        let time = WorkspaceUndoJournalTime(
            utc: Date(timeIntervalSince1970: 100), bootID: "drawer-presentation-undo",
            uptimeNanoseconds: 100_000_000_000)
        try await store.closeForUndo(
            tabID: closedTab.id, paneID: nil, closeID: UUIDv7.generate(), time: time,
            willPublish: { _, _ in }, didPublish: { _, _ in })
        #expect(store.paneAtom.pane(closedPane.id) == nil)
        // An ordinary save while the close is undoable must not prune its row.
        store.paneAtom.setDrawerNormalHeightRatio(0.5, forOwner: keptPane.id)
        #expect(await store.flushAsync() == .persisted)
        #expect(try databases.storedOwnerPaneIds(workspaceId: store.identityAtom.workspaceId).contains(closedPane.id))

        let restored = try await databases.bootStore()
        let receipt = try await restored.undoClose(
            time: time, willPublish: { _, _ in }, didPublish: { _, _ in })

        #expect(receipt != nil)
        #expect(restored.paneAtom.pane(closedPane.id) != nil)
        #expect(
            restored.paneAtom.drawerPresentationPreference(forOwner: closedPane.id)
                == DrawerPresentationPreference(normalHeightRatio: 0.35, zoomSide: .bridge)
        )
        #expect(restored.paneAtom.drawerPresentationPreference(forOwner: keptPane.id).normalHeightRatio == 0.5)
    }

    @Test("an owner outside live panes and undo records is pruned on the next save")
    func expiredOwnerRowIsPruned() async throws {
        let databases = try DrawerPresentationDatabases()
        defer { databases.remove() }
        let store = try await databases.bootStore()
        _ = appendTabbedPane(to: store)
        let closedPane = store.createPane()
        let closedTab = Tab(paneId: closedPane.id)
        store.appendTab(closedTab)
        store.paneAtom.setDrawerNormalHeightRatio(0.35, forOwner: closedPane.id)
        #expect(await store.flushAsync() == .persisted)
        let closedAt = WorkspaceUndoJournalTime(
            utc: Date(timeIntervalSince1970: 100), bootID: "drawer-presentation-expiry",
            uptimeNanoseconds: 100_000_000_000)
        try await store.closeForUndo(
            tabID: closedTab.id, paneID: nil, closeID: UUIDv7.generate(), time: closedAt,
            willPublish: { _, _ in }, didPublish: { _, _ in })

        let afterDeadline = WorkspaceUndoJournalTime(
            utc: Date(timeIntervalSince1970: 10_000), bootID: "drawer-presentation-expiry",
            uptimeNanoseconds: 100_000_000_000 + 10_000_000_000_000)
        _ = try await store.expireUndoCloses(time: afterDeadline)
        #expect(await store.flushAsync() == .persisted)

        #expect(
            !(try databases.storedOwnerPaneIds(workspaceId: store.identityAtom.workspaceId)
                .contains(closedPane.id))
        )
    }

    @Test("a preference committed during an in-flight save keeps the store dirty until saved")
    func preferenceChangedDuringSaveStaysDirty() async throws {
        let workspaceId = UUIDv7.generate()
        let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "drawer-presentation.dirty.core")
        let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "drawer-presentation.dirty.local")
        try WorkspaceCoreMigrations.migrate(coreQueue)
        try WorkspaceLocalMigrations.migrate(localQueue)
        let saveGate = DrawerPresentationSaveGate()
        let datastore = try await preparedWorkspaceSQLiteDatastore(
            coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
            preparedApplicationLocalRepository: WorkspaceLocalRepository(
                workspaceId: workspaceId,
                databaseWriter: localQueue
            ),
            probe: { event in
                guard event == .saveWorkspaceSnapshot else { return }
                await saveGate.pauseFirstSave()
            }
        )
        let store = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceId),
            sqliteDatastore: datastore,
            clock: TestPushClock()
        )
        let pane = appendTabbedPane(to: store)
        store.paneAtom.setDrawerNormalHeightRatio(0.4, forOwner: pane.id)
        #expect(store.isDirty)

        let inFlightFlush = Task { await store.flushAsync() }
        await saveGate.waitUntilFirstSavePaused()
        store.paneAtom.setDrawerNormalHeightRatio(0.6, forOwner: pane.id)
        await saveGate.releaseFirstSave()
        #expect(await inFlightFlush.value == .persisted)

        #expect(store.isDirty)
        #expect(await store.flushAsync() == .persisted)
        #expect(!store.isDirty)
        let stored = try WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
            .fetchDrawerPresentationRecords()
        #expect(stored.map(\.normalHeightRatio) == [0.6])
    }

    @Test("upgrade imports the populated legacy global height for every owning pane, then clears it")
    func legacyGlobalHeightImportsOnUpgrade() async throws {
        let databases = try DrawerPresentationDatabases()
        defer { databases.remove() }
        let store = try await databases.bootStore()
        let paneA = appendTabbedPane(to: store)
        let paneB = appendTabbedPane(to: store)
        let drawerChild = try #require(store.addDrawerPane(to: paneA.id))
        #expect(await store.flushAsync() == .persisted)
        try databases.rewindLocalSchemaBeforeDrawerPresentation()

        let legacyValue = LegacyHeightValueBox(value: 0.45)
        let restored = try await databases.bootStore(legacySource: legacyValue.source)

        for owner in [paneA.id, paneB.id] {
            #expect(
                restored.paneAtom.drawerPresentationPreference(forOwner: owner)
                    == DrawerPresentationPreference(normalHeightRatio: 0.45, zoomSide: .terminal)
            )
        }
        let storedOwners = try databases.storedOwnerPaneIds(workspaceId: restored.identityAtom.workspaceId)
        #expect(storedOwners == [paneA.id, paneB.id])
        #expect(!storedOwners.contains(drawerChild.id))
        #expect(legacyValue.value == nil)
    }

    @Test("unknown side and non-finite ratio fall back to each field's default")
    func invalidStoredFieldsFallBackToDefaults() async throws {
        let databases = try DrawerPresentationDatabases()
        defer { databases.remove() }
        let store = try await databases.bootStore()
        let paneA = appendTabbedPane(to: store)
        let paneB = appendTabbedPane(to: store)
        #expect(await store.flushAsync() == .persisted)
        let workspaceId = store.identityAtom.workspaceId
        try databases.writeRawPresentationRow(
            workspaceId: workspaceId, ownerPaneId: paneA.id, ratioSQL: "9e999", zoomSide: "bridge")
        try databases.writeRawPresentationRow(
            workspaceId: workspaceId, ownerPaneId: paneB.id, ratioSQL: "0.3", zoomSide: "sideways")

        let restored = try await databases.bootStore()

        #expect(
            restored.paneAtom.drawerPresentationPreference(forOwner: paneA.id)
                == DrawerPresentationPreference(normalHeightRatio: 0.8, zoomSide: .bridge)
        )
        #expect(
            restored.paneAtom.drawerPresentationPreference(forOwner: paneB.id)
                == DrawerPresentationPreference(normalHeightRatio: 0.3, zoomSide: .terminal)
        )
    }

    private func appendTabbedPane(to store: WorkspaceStore) -> Pane {
        let pane = store.createPane()
        store.appendTab(Tab(paneId: pane.id))
        return pane
    }
}

/// File-backed core and local databases reopened by each simulated boot.
@MainActor
private struct DrawerPresentationDatabases {
    let directory: URL
    var coreDatabaseURL: URL { directory.appending(path: "core.sqlite") }
    var localDatabaseURL: URL { directory.appending(path: "local.sqlite") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "agentstudio-drawer-presentation-\(UUIDv7.generate().uuidString)"
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func bootStore(legacySource: LegacyDrawerPresentationSource? = nil) async throws -> WorkspaceStore {
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL,
            legacyDrawerPresentationSource: legacySource
        ).makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            throw DrawerPresentationTestFailure.databasesNotPrepared
        }
        let store = WorkspaceStore(sqliteDatastore: datastore, startsObserving: false)
        switch await store.loadCanonicalComposition() {
        case .loaded, .initializedDefaultWorkspace:
            return store
        case let other:
            throw DrawerPresentationTestFailure.loadFailed(String(describing: other))
        }
    }

    func storedOwnerPaneIds(workspaceId: UUID) throws -> Set<UUID> {
        let queue = try DatabaseQueue(path: localDatabaseURL.path)
        let ids = try queue.read { database in
            try String.fetchAll(
                database,
                sql: "SELECT owner_pane_id FROM local_drawer_presentation WHERE workspace_id = ?",
                arguments: [workspaceId.uuidString]
            )
        }
        return Set(ids.compactMap(UUID.init(uuidString:)))
    }

    /// Returns the local database to its exact pre-upgrade shape: every other
    /// local row stays, only the drawer presentation schema step is undone.
    func rewindLocalSchemaBeforeDrawerPresentation() throws {
        let queue = try DatabaseQueue(path: localDatabaseURL.path)
        try queue.write { database in
            try database.execute(sql: "DROP TABLE local_drawer_presentation")
            try database.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                arguments: [WorkspaceLocalMigrations.drawerPresentationMigrationIdentifier]
            )
        }
    }

    func writeRawPresentationRow(workspaceId: UUID, ownerPaneId: UUID, ratioSQL: String, zoomSide: String) throws {
        let queue = try DatabaseQueue(path: localDatabaseURL.path)
        try queue.write { database in
            try database.execute(
                sql: """
                    INSERT OR REPLACE INTO local_drawer_presentation(
                        workspace_id, owner_pane_id, normal_height_ratio, zoom_side, updated_at
                    )
                    VALUES (?, ?, \(ratioSQL), ?, 0)
                    """,
                arguments: [workspaceId.uuidString, ownerPaneId.uuidString, zoomSide]
            )
        }
    }
}

private enum DrawerPresentationTestFailure: Error {
    case databasesNotPrepared
    case loadFailed(String)
}

/// Stand-in for the retired defaults key, so tests never touch a real defaults domain.
private final class LegacyHeightValueBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Double?

    init(value: Double?) {
        storedValue = value
    }

    var value: Double? {
        lock.withLock { storedValue }
    }

    var source: LegacyDrawerPresentationSource {
        LegacyDrawerPresentationSource(
            readHeightRatio: { [self] in lock.withLock { storedValue } },
            clear: { [self] in lock.withLock { storedValue = nil } }
        )
    }
}

private actor DrawerPresentationSaveGate {
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var pausedContinuation: CheckedContinuation<Void, Never>?
    private var didPause = false

    func pauseFirstSave() async {
        guard !didPause else { return }
        didPause = true
        await withCheckedContinuation { continuation in
            pauseContinuation = continuation
            pausedContinuation?.resume()
            pausedContinuation = nil
        }
    }

    func waitUntilFirstSavePaused() async {
        guard !didPause else { return }
        await withCheckedContinuation { continuation in
            pausedContinuation = continuation
        }
    }

    func releaseFirstSave() {
        pauseContinuation?.resume()
        pauseContinuation = nil
    }
}
