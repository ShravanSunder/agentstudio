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
        let paneA = appendPreUpgradeTabbedPane(to: store)
        let paneB = appendPreUpgradeTabbedPane(to: store)
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
        #expect(legacyValue.importCutoff == nil)
    }

    @Test("the legacy height boot step waits for a successful owner capture, then becomes a no-op")
    func legacyImportWaitsForSuccessfulOwnerCapture() async throws {
        // Arrange: a populated pre-upgrade database and a legacy global height.
        let databases = try DrawerPresentationDatabases()
        defer { databases.remove() }
        let store = try await databases.bootStore()
        let paneA = appendPreUpgradeTabbedPane(to: store)
        let paneB = appendPreUpgradeTabbedPane(to: store)
        #expect(await store.flushAsync() == .persisted)
        try databases.rewindLocalSchemaBeforeDrawerPresentation()
        let workspaceId = store.identityAtom.workspaceId
        let legacyValue = LegacyHeightValueBox(value: 0.45)
        let configuration = WorkspaceSQLiteDatastoreConfiguration(
            coreDatabaseURL: databases.coreDatabaseURL,
            localDatabaseURL: databases.localDatabaseURL,
            legacyDrawerPresentationSource: legacyValue.source
        )

        // Act 1: owner enumeration fails.
        let failedCapture = LegacyDrawerPresentationImportCapture.capture(
            source: legacyValue.source,
            now: Date(),
            enumerateOwners: { throw CocoaError(.fileReadUnknown) }
        )
        _ = try WorkspaceSQLiteDatastoreActor.openConfiguredLocalRepository(
            workspaceId: UUIDv7.generate(),
            configuration: configuration,
            legacyDrawerPresentationCapture: failedCapture
        )

        // Assert 1: the schema is migrated, nothing is imported, and the key
        // stays as the pending marker.
        #expect(failedCapture == .ownerEnumerationFailed)
        #expect(legacyValue.value == 0.45)
        #expect(try databases.storedOwnerPaneIds(workspaceId: workspaceId).isEmpty)

        // Act 2: a later boot captures the real persisted owners.
        let coreRepository = WorkspaceCoreRepository(
            databaseWriter: try DatabaseQueue(path: databases.coreDatabaseURL.path)
        )
        let capture = LegacyDrawerPresentationImportCapture.capture(
            source: legacyValue.source,
            now: Date(),
            enumerateOwners: { try coreRepository.fetchOwningLayoutPaneIDsByWorkspace() }
        )
        _ = try WorkspaceSQLiteDatastoreActor.openConfiguredLocalRepository(
            workspaceId: UUIDv7.generate(),
            configuration: configuration,
            legacyDrawerPresentationCapture: capture
        )

        // Assert 2: every owning pane is imported at the legacy height; the key is cleared.
        #expect(capture.importToApply != nil)
        #expect(try databases.storedOwnerPaneIds(workspaceId: workspaceId) == [paneA.id, paneB.id])
        #expect(try databases.storedRatio(workspaceId: workspaceId, ownerPaneId: paneA.id) == 0.45)
        #expect(legacyValue.value == nil)
        #expect(legacyValue.importCutoff == nil)

        // Act 3: a later save changes a row, then a boot with no key runs the step.
        try databases.writeRawPresentationRow(
            workspaceId: workspaceId, ownerPaneId: paneA.id, ratioSQL: "0.7", zoomSide: "bridge")
        let noKeyCapture = LegacyDrawerPresentationImportCapture.capture(
            source: legacyValue.source,
            now: Date(),
            enumerateOwners: { try coreRepository.fetchOwningLayoutPaneIDsByWorkspace() }
        )
        _ = try WorkspaceSQLiteDatastoreActor.openConfiguredLocalRepository(
            workspaceId: UUIDv7.generate(),
            configuration: configuration,
            legacyDrawerPresentationCapture: noKeyCapture
        )

        // Assert 3: nothing is imported or overwritten.
        #expect(noKeyCapture == .noLegacyValue)
        #expect(try databases.storedRatio(workspaceId: workspaceId, ownerPaneId: paneA.id) == 0.7)
        #expect(try databases.storedOwnerPaneIds(workspaceId: workspaceId) == [paneA.id, paneB.id])
    }

    @Test("a retried legacy import reaches only owners created before the first attempt's cutoff")
    func retriedLegacyImportSkipsOwnersCreatedAfterCutoff() async throws {
        // Arrange: a populated pre-upgrade database with a v7 owner and an
        // owner whose id predates UUIDv7, plus a legacy global height.
        let databases = try DrawerPresentationDatabases()
        defer { databases.remove() }
        let preUpgradeStore = try await databases.bootStore()
        let oldOwner = appendPreUpgradeTabbedPane(to: preUpgradeStore)
        // Historical ids of any UUID version stay valid pane identities.
        let historicalOwner = appendTabbedPane(withId: UUID(), to: preUpgradeStore)
        #expect(await preUpgradeStore.flushAsync() == .persisted)
        try databases.rewindLocalSchemaBeforeDrawerPresentation()
        let workspaceId = preUpgradeStore.identityAtom.workspaceId
        let legacyValue = LegacyHeightValueBox(value: 0.45)
        let configuration = WorkspaceSQLiteDatastoreConfiguration(
            coreDatabaseURL: databases.coreDatabaseURL,
            localDatabaseURL: databases.localDatabaseURL,
            legacyDrawerPresentationSource: legacyValue.source
        )

        // Act 1: the upgrade boot's owner capture fails.
        let failedCapture = LegacyDrawerPresentationImportCapture.capture(
            source: legacyValue.source,
            now: Date(),
            enumerateOwners: { throw CocoaError(.fileReadUnknown) }
        )
        _ = try WorkspaceSQLiteDatastoreActor.openConfiguredLocalRepository(
            workspaceId: UUIDv7.generate(),
            configuration: configuration,
            legacyDrawerPresentationCapture: failedCapture
        )

        // Assert 1: the cutoff is recorded next to the still-pending key.
        #expect(failedCapture == .ownerEnumerationFailed)
        #expect(legacyValue.value == 0.45)
        let recordedCutoff = try #require(legacyValue.importCutoff)

        // Act 2: a retry an hour later fails again.
        let failedRetry = LegacyDrawerPresentationImportCapture.capture(
            source: legacyValue.source,
            now: Date(timeIntervalSinceNow: 3600),
            enumerateOwners: { throw CocoaError(.fileReadUnknown) }
        )

        // Assert 2: the retry does not move the cutoff.
        #expect(failedRetry == .ownerEnumerationFailed)
        #expect(legacyValue.importCutoff == recordedCutoff)

        // Act 3: the app runs, creates a pane through production creation, and
        // saves it ordinarily; then the next boot imports successfully.
        let runningStore = try await databases.bootStore()
        let newOwner = appendTabbedPane(to: runningStore)
        #expect(await runningStore.flushAsync() == .persisted)
        let restored = try await databases.bootStore(legacySource: legacyValue.source)

        // Assert 3: owners created before the cutoff get the legacy height; the
        // new owner keeps its default; the key and the cutoff are cleared together.
        #expect(
            restored.paneAtom.drawerPresentationPreference(forOwner: oldOwner.id)
                == DrawerPresentationPreference(normalHeightRatio: 0.45, zoomSide: .terminal)
        )
        #expect(
            restored.paneAtom.drawerPresentationPreference(forOwner: historicalOwner.id)
                == DrawerPresentationPreference(normalHeightRatio: 0.45, zoomSide: .terminal)
        )
        #expect(
            restored.paneAtom.drawerPresentationPreference(forOwner: newOwner.id)
                == DrawerPresentationPreference(normalHeightRatio: 0.8, zoomSide: .terminal)
        )
        #expect(try databases.storedRatio(workspaceId: workspaceId, ownerPaneId: newOwner.id) == nil)
        #expect(legacyValue.value == nil)
        #expect(legacyValue.importCutoff == nil)
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

    /// An owner that existed before the upgrade: its UUIDv7 id was minted an
    /// hour before the upgrade boot records the import cutoff.
    private func appendPreUpgradeTabbedPane(to store: WorkspaceStore) -> Pane {
        appendTabbedPane(withId: UUIDv7.generate(timestamp: Date(timeIntervalSinceNow: -3600)), to: store)
    }

    private func appendTabbedPane(withId paneId: UUID, to store: WorkspaceStore) -> Pane {
        let pane = makePane(id: paneId, launchDirectory: FileManager.default.temporaryDirectory)
        store.paneAtom.addPane(pane)
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

    func storedRatio(workspaceId: UUID, ownerPaneId: UUID) throws -> Double? {
        let queue = try DatabaseQueue(path: localDatabaseURL.path)
        return try queue.read { database in
            try Double.fetchOne(
                database,
                sql: """
                    SELECT normal_height_ratio FROM local_drawer_presentation
                    WHERE workspace_id = ? AND owner_pane_id = ?
                    """,
                arguments: [workspaceId.uuidString, ownerPaneId.uuidString]
            )
        }
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

/// Stand-in for the retired defaults key and its import cutoff, so tests never
/// touch a real defaults domain.
private final class LegacyHeightValueBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Double?
    private var storedImportCutoff: Date?

    init(value: Double?) {
        storedValue = value
    }

    var value: Double? {
        lock.withLock { storedValue }
    }

    var importCutoff: Date? {
        lock.withLock { storedImportCutoff }
    }

    var source: LegacyDrawerPresentationSource {
        LegacyDrawerPresentationSource(
            readHeightRatio: { [self] in lock.withLock { storedValue } },
            readImportCutoff: { [self] in lock.withLock { storedImportCutoff } },
            writeImportCutoff: { [self] importCutoff in lock.withLock { storedImportCutoff = importCutoff } },
            clear: { [self] in
                lock.withLock {
                    storedValue = nil
                    storedImportCutoff = nil
                }
            }
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
