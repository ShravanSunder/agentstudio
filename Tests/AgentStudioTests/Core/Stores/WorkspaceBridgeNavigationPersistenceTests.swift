import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

/// Receiver navigation persistence against real file-backed core and local
/// SQLite databases: ordinary restart, close/undo retention and the ordered
/// legacy `BridgePaneState.source` conversion on populated data.
@MainActor
@Suite("Bridge navigation persistence", .serialized)
struct WorkspaceBridgeNavigationPersistenceTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("receiver records survive an ordinary restart exactly")
    func recordsSurviveRestart() async throws {
        // Arrange
        let fixture = try BridgeNavigationPersistenceFixture()
        defer { fixture.remove() }
        let first = try await fixture.openStore(expectInitialization: true)
        let bridgePane = first.store.createPane(
            content: .bridgePanel(BridgePaneState(panelKind: .fileViewer)),
            metadata: fixture.paneMetadata(title: "Files")
        )
        first.store.appendTab(Tab(paneId: bridgePane.id))
        let terminalPane = first.store.createPane(launchDirectory: fixture.root)
        first.store.appendTab(Tab(paneId: terminalPane.id))
        let backend = UUIDv7.generate()
        let frontend = UUIDv7.generate()
        let notes = try #require(BridgeDocumentLocation(canonicalPath: "/private/tmp/feature-notes.md"))
        let backendFile = try #require(BridgeDocumentLocation(canonicalPath: "/repos/backend/App.swift"))
        let standaloneRecord = BridgeNavigationRecord(
            openedDocuments: [
                backendFile: BridgeOpenedDocumentEntry(
                    provenance: BridgeKnownWorktreeProvenance(
                        repoId: UUIDv7.generate(),
                        worktreeId: backend,
                        relativePath: "App.swift"
                    ),
                    sortKey: UUIDv7.generate(milliseconds: 1_700_000_000_001)
                ),
                notes: BridgeOpenedDocumentEntry(
                    provenance: nil, sortKey: UUIDv7.generate(milliseconds: 1_700_000_000_002)),
            ],
            committedMemberLinks: testCommittedMemberLinks([backend, frontend]),
            filesFilter: .member(worktreeId: frontend),
            selectedFilesDocument: notes,
            reviewSelection: .member(worktreeId: frontend),
            surface: .review,
            reviewComparisonsByWorktreeId: [
                backend: .branch(name: "main", basis: .branchTip),
                frontend: .staged,
            ]
        )
        let terminalRecord = BridgeNavigationRecord(
            openedDocuments: [
                notes: BridgeOpenedDocumentEntry(
                    provenance: nil, sortKey: UUIDv7.generate(milliseconds: 1_700_000_000_001))
            ],
            committedMemberLinks: testCommittedMemberLinks([backend]),
            reviewSelection: .importedUnavailable(
                BridgeImportedReviewQuery(variant: .commit, originalPayloadJSON: #"{"commit":{"sha":"abc"}}"#)
            )
        )
        #expect(await first.store.flushAsync() == .persisted)
        let workspaceID = first.store.identityAtom.workspaceId
        let standaloneReceiver = BridgeReceiver.standalone(bridgePane.id)
        let terminalReceiver = BridgeReceiver.terminal(terminalPane.id)
        let standaloneTopology = try receiverTopologySnapshot(
            for: standaloneReceiver, knownWorktreeRoots: [backend: "/tmp/backend", frontend: "/tmp/frontend"])
        let terminalTopology = try receiverTopologySnapshot(
            for: terminalReceiver, knownWorktreeRoots: [backend: "/tmp/backend"])
        for worktreeID in [backend, frontend] {
            _ = try await first.datastore.commitBridgeMemberAddition(
                context: BridgeLinkMutationContext(
                    workspaceID: workspaceID, receiver: standaloneReceiver,
                    generation: first.store.bridgeWriteSequencer.nextTicket().value,
                    topologySnapshot: standaloneTopology),
                worktreeID: worktreeID, contributor: .app,
                addedAt: Date(timeIntervalSince1970: 1_700_000_000))
        }
        _ = try await first.datastore.commitBridgeMemberAddition(
            context: BridgeLinkMutationContext(
                workspaceID: workspaceID, receiver: terminalReceiver,
                generation: first.store.bridgeWriteSequencer.nextTicket().value,
                topologySnapshot: terminalTopology),
            worktreeID: backend, contributor: .app,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000))
        first.store.bridgeNavigationAtom.setRecord(standaloneRecord, for: .standalone(bridgePane.id))
        first.store.bridgeNavigationAtom.setRecord(terminalRecord, for: .terminal(terminalPane.id))
        _ = first.store.bridgeWriteSequencer.nextTicket()

        // Act
        #expect(await first.store.flushAsync() == .persisted)
        let second = try await fixture.openStore(expectInitialization: false)

        // Assert
        #expect(
            second.store.bridgeNavigationAtom.recordsSnapshot() == [
                .standalone(bridgePane.id): standaloneRecord,
                .terminal(terminalPane.id): terminalRecord,
            ]
        )
        #expect(
            second.store.bridgeNavigationAtom.openedDocumentEntry(
                for: standaloneReceiver, at: notes) == standaloneRecord.openedDocument(at: notes))
        #expect(
            second.store.bridgeNavigationAtom.preparedFilesBinding(
                for: standaloneReceiver)?.openedDocuments == [backendFile, notes])
    }

    @Test("startup reconciliation save takes a generation above restored receiver rows")
    func reconciliationSaveAdvancesRestoredGeneration() async throws {
        let fixture = try BridgeNavigationPersistenceFixture()
        defer { fixture.remove() }
        let first = try await fixture.openStore(expectInitialization: true)
        let repository = first.store.addRepo(at: fixture.root)
        let worktree = try #require(first.store.repo(repository.id)?.worktrees.first)
        let pane = first.store.createPane(
            content: .bridgePanel(.init(panelKind: .fileViewer)),
            metadata: PaneMetadata(
                contentType: .diff, launchDirectory: fixture.root,
                title: "Reconcile association",
                facets: PaneContextFacets(cwd: fixture.root)))
        first.store.appendTab(Tab(paneId: pane.id))
        first.store.bridgeNavigationAtom.setRecord(.init(surface: .review), for: .standalone(pane.id))
        #expect(await first.store.flushAsync() == .persisted)
        try await RepositoryTopologyStore(
            atom: first.store.repositoryTopologyAtom,
            sqliteDatastore: first.datastore
        ).flushAsync()
        try fixture.executeLocal("UPDATE bridge_receiver_state SET generation = 100")

        // The pane's known association is backfilled during load, which issues
        // the startup reconciliation save after hydration seeds the floor.
        let restored = try await fixture.openStore(expectInitialization: false)
        #expect(restored.store.paneAtom.pane(pane.id)?.worktreeId == worktree.id)
        #expect(restored.store.bridgeWriteSequencer.nextTicket().value >= 102)
    }

    @Test("close/undo retains the receiver row; expiry and permanent removal make it eligible cleanup")
    func undoRetentionAndCleanup() async throws {
        // Arrange
        let fixture = try BridgeNavigationPersistenceFixture()
        defer { fixture.remove() }
        let first = try await fixture.openStore(expectInitialization: true)
        let closedPane = first.store.createPane(
            content: .bridgePanel(BridgePaneState(panelKind: .diffViewer)),
            metadata: fixture.paneMetadata(title: "Closed")
        )
        let closedTab = Tab(paneId: closedPane.id)
        first.store.appendTab(closedTab)
        let livePane = first.store.createPane(
            content: .bridgePanel(BridgePaneState(panelKind: .fileViewer)),
            metadata: fixture.paneMetadata(title: "Live")
        )
        first.store.appendTab(Tab(paneId: livePane.id))
        // A pane whose tab is later removed permanently, not for undo.
        let removedPane = first.store.createPane(launchDirectory: fixture.root)
        let removedTab = Tab(paneId: removedPane.id)
        first.store.appendTab(removedTab)
        let record = BridgeNavigationRecord(surface: .review)
        for receiver in [
            BridgeReceiver.standalone(closedPane.id), .standalone(livePane.id), .terminal(removedPane.id),
        ] {
            first.store.bridgeNavigationAtom.setRecord(record, for: receiver)
        }
        let closeTime = WorkspaceUndoJournalTime(
            utc: Date(timeIntervalSince1970: 100),
            bootID: "bridge-navigation-undo",
            uptimeNanoseconds: 100_000_000_000
        )

        // Act — close one pane for undo and permanently remove another.
        try await first.store.closeForUndo(
            tabID: closedTab.id, paneID: nil, closeID: UUIDv7.generate(), time: closeTime,
            willPublish: { _, _ in }, didPublish: { _, _ in }
        )
        first.store.removeTab(removedTab.id)
        first.store.removePane(removedPane.id)
        #expect(await first.store.flushAsync() == .persisted)
        let afterClose = try await fixture.openStore(expectInitialization: false)

        // Assert — undo keeps the closed receiver; the removed pane's row is cleaned up.
        #expect(
            Set(afterClose.store.bridgeNavigationAtom.recordsSnapshot().keys) == [
                .standalone(closedPane.id), .standalone(livePane.id),
            ]
        )

        // Act — undo expiry ends the closed receiver's eligibility.
        let expiry = WorkspaceUndoJournalTime(
            utc: Date(timeIntervalSince1970: 100_000),
            bootID: "bridge-navigation-undo",
            uptimeNanoseconds: 100_000_000_000_000
        )
        _ = try await afterClose.store.expireUndoCloses(time: expiry)
        #expect(await afterClose.store.flushAsync() == .persisted)
        let afterExpiry = try await fixture.openStore(expectInitialization: false)

        // Assert
        #expect(Set(afterExpiry.store.bridgeNavigationAtom.recordsSnapshot().keys) == [.standalone(livePane.id)])
    }

    @Test("populated legacy database: ordered local import then core rewrite, never re-imported")
    func legacySourceConversionOnPopulatedDatabase() async throws {
        // Arrange — a real workspace whose Bridge payloads still carry legacy sources.
        let fixture = try BridgeNavigationPersistenceFixture()
        defer { fixture.remove() }
        let seeded = try await fixture.seedLegacyWorkspace()

        // Act
        let converted = try await fixture.openStore(expectInitialization: false)

        // Assert — the known root imports as a member with its exact comparison.
        let reviewRecord = try #require(
            converted.store.bridgeNavigationAtom.record(for: .standalone(seeded.reviewPaneID))
        )
        #expect(reviewRecord.committedMemberWorktreeIds == [seeded.worktreeID])
        #expect(reviewRecord.reviewSelection == .member(worktreeId: seeded.worktreeID))
        #expect(
            reviewRecord.reviewComparisonsByWorktreeId == [
                seeded.worktreeID: .branch(name: "develop", basis: .branchTip)
            ]
        )
        #expect(reviewRecord.surface == .review)
        // A dormant variant stays an identifiable unavailable value with its payload.
        let commitRecord = try #require(
            converted.store.bridgeNavigationAtom.record(for: .standalone(seeded.commitPaneID))
        )
        #expect(commitRecord.committedMemberWorktreeIds.isEmpty)
        #expect(
            commitRecord.reviewSelection
                == .importedUnavailable(
                    BridgeImportedReviewQuery(variant: .commit, originalPayloadJSON: #"{"commit":{"sha":"abc123"}}"#)
                )
        )
        #expect(commitRecord.surface == .files)
        #expect(converted.store.bridgeNavigationAtom.conversionUnavailablePaneIds.isEmpty)
        // The core payloads no longer carry a competing source field.
        for paneID in [seeded.reviewPaneID, seeded.commitPaneID] {
            let state = try fixture.corePayloadState(paneID: paneID)
            #expect(state["source"] == nil)
        }
        #expect(try fixture.localNavigationRecordCount() == 2)
        #expect(try fixture.hasLocalNavigationRecord(forPaneID: seeded.reviewPaneID))
        #expect(try fixture.hasLocalNavigationRecord(forPaneID: seeded.commitPaneID))

        // Act — a later change and restart never re-imports over the local record.
        var edited = reviewRecord
        edited.surface = .files
        converted.store.bridgeNavigationAtom.setRecord(edited, for: .standalone(seeded.reviewPaneID))
        #expect(await converted.store.flushAsync() == .persisted)
        let restarted = try await fixture.openStore(expectInitialization: false)

        // Assert
        #expect(restarted.store.bridgeNavigationAtom.record(for: .standalone(seeded.reviewPaneID)) == edited)
    }

    @Test("failed local import keeps the legacy payload intact through ordinary saves until a later import")
    func failedImportPreservesLegacyPayload() async throws {
        // Arrange
        let fixture = try BridgeNavigationPersistenceFixture()
        defer { fixture.remove() }
        let seeded = try await fixture.seedLegacyWorkspace()
        let legacyPayload = try fixture.corePayloadJSON(paneID: seeded.reviewPaneID)
        try fixture.executeLocal(
            """
            CREATE TRIGGER block_bridge_navigation_import
            BEFORE INSERT ON bridge_receiver_state
            BEGIN SELECT RAISE(ABORT, 'import blocked'); END
            """
        )

        // Act
        let blocked = try await fixture.openStore(expectInitialization: false)
        let saveOutcome = await blocked.store.flushAsync()

        // Assert — no record, unavailable presentation, and the exact legacy bytes survive a save.
        #expect(blocked.store.bridgeNavigationAtom.record(for: .standalone(seeded.reviewPaneID)) == nil)
        #expect(
            blocked.store.bridgeNavigationAtom.conversionUnavailablePaneIds.isSuperset(of: [seeded.reviewPaneID])
        )
        #expect(saveOutcome == .persisted)
        #expect(try fixture.corePayloadJSON(paneID: seeded.reviewPaneID) == legacyPayload)

        // Act — once the local database accepts the import, the next start converts.
        try fixture.executeLocal("DROP TRIGGER block_bridge_navigation_import")
        let recovered = try await fixture.openStore(expectInitialization: false)

        // Assert
        #expect(
            recovered.store.bridgeNavigationAtom.record(for: .standalone(seeded.reviewPaneID))?
                .committedMemberWorktreeIds
                == [seeded.worktreeID]
        )
        #expect(try fixture.corePayloadState(paneID: seeded.reviewPaneID)["source"] == nil)
    }

    @Test("core rewrite failure after the local commit retries only the core step on restart")
    func coreRewriteFailureRetriesOnlyCoreStep() async throws {
        // Arrange
        let fixture = try BridgeNavigationPersistenceFixture()
        defer { fixture.remove() }
        let seeded = try await fixture.seedLegacyWorkspace()
        let legacyPayload = try fixture.corePayloadJSON(paneID: seeded.reviewPaneID)
        try fixture.executeCore(
            """
            CREATE TRIGGER block_bridge_payload_rewrite
            BEFORE UPDATE OF payload_json ON pane_content_payload
            BEGIN SELECT RAISE(ABORT, 'rewrite blocked'); END
            """
        )

        // Act — the local record commits, the core rewrite fails.
        let firstStart = try await fixture.openStore(expectInitialization: false)
        let imported = try #require(
            firstStart.store.bridgeNavigationAtom.record(for: .standalone(seeded.reviewPaneID))
        )
        #expect(try fixture.corePayloadJSON(paneID: seeded.reviewPaneID) == legacyPayload)
        // Change the committed local record out of band so a re-import would be visible.
        var marker = imported
        marker.surface = .files
        try fixture.replaceLocalRecord(marker, receiver: .standalone(seeded.reviewPaneID))
        try fixture.executeCore("DROP TRIGGER block_bridge_payload_rewrite")
        let secondStart = try await fixture.openStore(expectInitialization: false)

        // Assert — the imported record was not overwritten; only the core step ran.
        #expect(secondStart.store.bridgeNavigationAtom.record(for: .standalone(seeded.reviewPaneID)) == marker)
        #expect(try fixture.corePayloadState(paneID: seeded.reviewPaneID)["source"] == nil)
    }
}

@Suite("Bridge receiver typed row codec")
struct BridgeReceiverTypedRowCodecTests {
    @Test("every state and contribution kind round trips through typed columns")
    func typedRowsRoundTrip() throws {
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let member = UUIDv7.generate()
        let document = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/typed-row.swift"))
        let pullRequest = try ForgePullRequestIdentity(
            host: "github.com", owner: "Team", repository: "Repo", number: 42)
        var record = BridgeNavigationRecord(
            openedDocuments: [
                document: .init(
                    provenance: .init(repoId: UUIDv7.generate(), worktreeId: member, relativePath: "typed-row.swift"),
                    sortKey: UUIDv7.generate(milliseconds: 1_700_000_000_001))
            ],
            committedMemberLinks: [
                .init(
                    worktreeId: member,
                    contributions: [.init(addedBy: .person, addedAt: Date(timeIntervalSince1970: 1_700_000_000))])
            ],
            pullRequestLinks: [
                .init(
                    identity: pullRequest,
                    contributions: [.init(addedBy: .app, addedAt: Date(timeIntervalSince1970: 1_700_000_000))])
            ],
            filesFilter: .member(worktreeId: member), selectedFilesDocument: document,
            reviewSelection: .member(worktreeId: member), surface: .review,
            reviewComparisonsByWorktreeId: [member: .branch(name: "main", basis: .branchTip)]
        )
        let derivedOnlyMember = UUIDv7.generate()
        record.derivedCurrentCWDWorktreeId = derivedOnlyMember
        let states = BridgeReceiverRecordRows.states(record, receiver: receiver, generation: 7)
        let items = BridgeReceiverRecordRows.items(record, receiver: receiver, generation: 7)
        let decoded = try BridgeReceiverRecordRows.record(states: states, items: items)
        #expect(decoded.committedMemberWorktreeIds == [member])
        #expect(decoded.derivedCurrentCWDWorktreeId == nil)
        #expect(record.effectiveMemberWorktreeIds == [member, derivedOnlyMember])
        #expect(
            Set(states.map(\.kind)) == [
                "filesFilter", "selectedFilesDocument", "reviewSelection", "surface", "reviewComparison", "itemOrder",
                "openedDocument",
            ])
        #expect(Set(items.map(\.kind)) == ["member", "prReference"])
    }

    @Test("typed identity mismatch is rejected on read")
    func malformedIdentityFailsClosed() throws {
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let member = UUIDv7.generate()
        let record = BridgeNavigationRecord(committedMemberLinks: testCommittedMemberLinks([member]))
        var items = BridgeReceiverRecordRows.items(record, receiver: receiver, generation: 1)
        items[0].worktreeID = UUIDv7.generate()
        #expect(throws: BridgeReceiverStorageError.malformedRow("member identity")) {
            try BridgeReceiverRecordRows.record(
                states: BridgeReceiverRecordRows.states(record, receiver: receiver, generation: 1), items: items)
        }
        var states = BridgeReceiverRecordRows.states(.empty, receiver: receiver, generation: 1)
        let surfaceIndex = try #require(states.firstIndex { $0.kind == "surface" })
        states[surfaceIndex].worktreeID = member
        #expect(throws: BridgeReceiverStorageError.malformedRow("state kind columns")) {
            try BridgeReceiverRecordRows.record(states: states, items: [])
        }
    }
}

// MARK: - Fixture

@MainActor
private struct BridgeNavigationPersistenceFixture {
    struct OpenedStore {
        let store: WorkspaceStore
        let datastore: WorkspaceSQLiteDatastoreActor
    }

    struct LegacyWorkspace {
        let worktreeID: UUID
        let reviewPaneID: UUID
        let commitPaneID: UUID
    }

    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "bridge-navigation-persistence-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var worktreeRoot: URL { root.appending(path: "worktree", directoryHint: .isDirectory) }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func openStore(expectInitialization: Bool) async throws -> OpenedStore {
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: root.appending(path: "core.sqlite"),
            localDatabaseURL: root.appending(path: "local.sqlite")
        ).makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            throw FixtureFailure.preparationFailed
        }
        let store = WorkspaceStore(sqliteDatastore: datastore, startsObserving: false)
        switch await store.loadCanonicalComposition() {
        case .initializedDefaultWorkspace where expectInitialization, .loaded where !expectInitialization:
            return OpenedStore(store: store, datastore: datastore)
        default:
            throw FixtureFailure.unexpectedLoad
        }
    }

    func paneMetadata(title: String) -> PaneMetadata {
        PaneMetadata(
            contentType: .diff,
            launchDirectory: root,
            title: title,
            facets: PaneContextFacets(cwd: root)
        )
    }

    /// Persist a real workspace plus topology, then rewrite two Bridge payloads
    /// to the exact legacy shape an older build stored.
    func seedLegacyWorkspace() async throws -> LegacyWorkspace {
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        let opened = try await openStore(expectInitialization: true)
        let repo = opened.store.addRepo(at: worktreeRoot)
        let worktree = try #require(opened.store.repo(repo.id)?.worktrees.first)
        let reviewPane = opened.store.createPane(
            content: .bridgePanel(BridgePaneState(panelKind: .diffViewer)),
            metadata: paneMetadata(title: "Legacy Review")
        )
        opened.store.appendTab(Tab(paneId: reviewPane.id))
        let commitPane = opened.store.createPane(
            content: .bridgePanel(BridgePaneState(panelKind: .fileViewer)),
            metadata: paneMetadata(title: "Legacy commit")
        )
        opened.store.appendTab(Tab(paneId: commitPane.id))
        #expect(await opened.store.flushAsync() == .persisted)
        try await RepositoryTopologyStore(
            atom: opened.store.repositoryTopologyAtom,
            sqliteDatastore: opened.datastore
        ).flushAsync()
        try rewriteCorePayload(
            paneID: reviewPane.id,
            json: """
                {"state":{"panelKind":"diffViewer","source":{"workspace":{"comparisonTarget":\
                {"basis":"branchTip","kind":"branch","name":"develop"},"rootPath":"\(worktree.path.path)"}}},\
                "type":"bridgePanel","version":3}
                """
        )
        try rewriteCorePayload(
            paneID: commitPane.id,
            json: """
                {"state":{"panelKind":"fileViewer","source":{"commit":{"sha":"abc123"}}},\
                "type":"bridgePanel","version":3}
                """
        )
        #expect(try localNavigationRecordCount() == 0, "legacy panes start without local records")
        return LegacyWorkspace(worktreeID: worktree.id, reviewPaneID: reviewPane.id, commitPaneID: commitPane.id)
    }

    func corePayloadJSON(paneID: UUID) throws -> String {
        try withPool(database: "core.sqlite") { database in
            try #require(
                try String.fetchOne(
                    database,
                    sql: "SELECT payload_json FROM pane_content_payload WHERE pane_id = ?",
                    arguments: [paneID.uuidString]
                )
            )
        }
    }

    func corePayloadState(paneID: UUID) throws -> [String: Any] {
        let payload = try corePayloadJSON(paneID: paneID)
        let object = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        return try #require(object["state"] as? [String: Any])
    }

    func localNavigationRecordCount() throws -> Int {
        try withPool(database: "local.sqlite") { database in
            try Int.fetchOne(
                database, sql: "SELECT COUNT(DISTINCT receiver_pane_id) FROM bridge_receiver_state WHERE is_deleted = 0"
            ) ?? 0
        }
    }

    func hasLocalNavigationRecord(forPaneID paneID: UUID) throws -> Bool {
        try withPool(database: "local.sqlite") { database in
            try Int.fetchOne(
                database,
                sql: "SELECT 1 FROM bridge_receiver_state WHERE receiver_pane_id = ? AND is_deleted = 0 LIMIT 1",
                arguments: [paneID.uuidString]
            ) != nil
        }
    }

    func replaceLocalRecord(_ record: BridgeNavigationRecord, receiver: BridgeReceiver) throws {
        try withPool(database: "local.sqlite", write: true) { database in
            try database.execute(
                sql:
                    "UPDATE bridge_receiver_state SET text_value = ?, generation = generation + 1 WHERE receiver_pane_id = ? AND kind = 'surface'",
                arguments: [record.surface.rawValue, receiver.paneId.uuidString]
            )
        }
    }

    func executeLocal(_ sql: String) throws {
        try withPool(database: "local.sqlite", write: true) { try $0.execute(sql: sql) }
    }

    func executeCore(_ sql: String) throws {
        try withPool(database: "core.sqlite", write: true) { try $0.execute(sql: sql) }
    }

    private func rewriteCorePayload(paneID: UUID, json: String) throws {
        try withPool(database: "core.sqlite", write: true) { database in
            try database.execute(
                sql: "UPDATE pane_content_payload SET payload_json = ? WHERE pane_id = ?",
                arguments: [json, paneID.uuidString]
            )
            #expect(database.changesCount == 1)
        }
    }

    private func withPool<Output>(
        database name: String,
        write: Bool = false,
        _ body: (Database) throws -> Output
    ) throws -> Output {
        let pool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: root.appending(path: name),
            label: "AgentStudio.sqlite.bridge-navigation-fixture"
        )
        defer { try? pool.close() }
        return write ? try pool.write(body) : try pool.read(body)
    }

    enum FixtureFailure: Error {
        case preparationFailed
        case unexpectedLoad
    }
}
