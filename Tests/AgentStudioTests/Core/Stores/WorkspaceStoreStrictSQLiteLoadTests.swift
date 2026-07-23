import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceStore strict SQLite load", .serialized)
struct WorkspaceStoreStrictSQLiteLoadTests {
    @Test("valid SQLite composition loads persisted authoritative repository topology")
    func validSQLiteCompositionLoadsPersistedAuthoritativeRepositoryTopology() async throws {
        let harness = try StrictSQLiteCompositionLoadHarness.make(testName: "valid-composition")
        defer { harness.removeTemporaryFiles() }
        let fixture = try await PersistedAuthoritativeTopologyFixture.seed(in: harness)
        let repositoryTopologyAtom = RepositoryTopologyAtom()
        let store = harness.makeStore(repositoryTopologyAtom: repositoryTopologyAtom)

        let result = await store.loadCanonicalComposition()

        guard case .loaded(let acceptance) = result else {
            Issue.record("Expected loaded result, got \(result)")
            return
        }
        #expect(store.workspaceId == fixture.workspaceID)
        #expect(store.workspaceName == fixture.snapshot.name)
        #expect(store.panes == [fixture.paneID: fixture.pane])
        #expect(store.tabs == [fixture.tab])
        #expect(store.activeTabId == fixture.tab.id)
        #expect(UUIDv7.isV7(acceptance.contentMountCohort.generation.id))
        #expect(acceptance.terminalActivationInput.entries.count == 1)
        let activation = try #require(acceptance.terminalActivationInput.entries.first)
        #expect(activation.paneID.uuid == fixture.paneID)
        guard case .terminal(let activationTerminalState) = activation.pane.content else {
            Issue.record("expected restored terminal pane content")
            return
        }
        #expect(activationTerminalState.zmxSessionID == fixture.storedZmxSessionID)
        #expect(activationTerminalState.provider == .zmx)
        #expect(activation.hostPlacement == .tab(tabID: fixture.tab.id))
        #expect(store.panes[fixture.paneID]?.drawer?.drawerId == fixture.drawerID)
        #expect(store.tabs.single?.id == fixture.tabID)
        #expect(store.tabs.single?.activeArrangement.id == fixture.arrangementID)
        let restoredRepository = try #require(repositoryTopologyAtom.repos.single)
        #expect(restoredRepository.id == fixture.repositoryID)
        #expect(restoredRepository.name == "Persisted repository")
        #expect(restoredRepository.repoPath == fixture.repositoryPath.standardizedFileURL)
        #expect(restoredRepository.worktrees.single?.id == fixture.worktreeID)
        #expect(repositoryTopologyAtom.unavailableRepoIds == [fixture.repositoryID])
        #expect(
            repositoryTopologyAtom.watchedPaths.single?.path.path
                == fixture.repositoryPath.deletingLastPathComponent().standardizedFileURL.path
        )
    }

    @Test("pristine SQLite initializes one UUIDv7 default workspace that reloads")
    func pristineSQLiteInitializesOneUUIDv7DefaultWorkspaceThatReloads() async throws {
        let harness = try StrictSQLiteCompositionLoadHarness.make(testName: "default-workspace")
        defer { harness.removeTemporaryFiles() }
        let probeRecorder = StrictStartupProbeRecorder()
        let firstStore = harness.makeStore(
            datastore: harness.makeDatastore(probe: { event in
                await probeRecorder.record(event)
            })
        )

        let firstResult = await firstStore.loadCanonicalComposition()

        guard case .initializedDefaultWorkspace(let acceptance) = firstResult else {
            Issue.record("Expected initializedDefaultWorkspace result, got \(firstResult)")
            return
        }
        #expect(UUIDv7.isV7(firstStore.workspaceId))
        #expect(firstStore.workspaceName == "Default Workspace")
        #expect(firstStore.panes.isEmpty)
        #expect(firstStore.tabs.isEmpty)
        #expect(acceptance.terminalActivationInput.entries.isEmpty)
        #expect(await probeRecorder.count(of: .saveWorkspaceSnapshot) == 1)
        #expect(await probeRecorder.count(of: .loadWorkspaceSnapshot) == 2)

        let reloadedStore = harness.makeStore()
        let reloadResult = await reloadedStore.loadCanonicalComposition()

        guard case .loaded = reloadResult else {
            Issue.record("Expected loaded result on reload, got \(reloadResult)")
            return
        }
        #expect(reloadedStore.workspaceId == firstStore.workspaceId)
        #expect(reloadedStore.workspaceName == firstStore.workspaceName)
        #expect(reloadedStore.panes.isEmpty)
        #expect(reloadedStore.tabs.isEmpty)
    }

    @Test("default workspace rejects a mismatched persisted reread without canonical mutation")
    func defaultWorkspaceRejectsMismatchedPersistedRereadWithoutCanonicalMutation() async throws {
        let harness = try StrictSQLiteCompositionLoadHarness.make(testName: "default-workspace-reread-mismatch")
        defer { harness.removeTemporaryFiles() }
        let coreDatabaseURL = harness.coreDatabaseURL
        let mutationOutcome = StrictStartupProbeMutationOutcome()
        let probeRecorder = StrictStartupProbeRecorder(onFirstSuccessfulSave: {
            do {
                let databasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
                    at: coreDatabaseURL,
                    label: "AgentStudio.sqlite.strict-restore.default-reread-mismatch"
                )
                try await databasePool.write { database in
                    try database.execute(
                        sql: "UPDATE workspace SET name = ?",
                        arguments: ["Persisted mismatch"]
                    )
                }
                try databasePool.close()
            } catch {
                await mutationOutcome.recordFailure()
            }
        })
        let initialWorkspaceID = UUIDv7.generate()
        let identityAtom = WorkspaceIdentityAtom(
            workspaceId: initialWorkspaceID,
            workspaceName: "Initial identity",
            createdAt: Date(timeIntervalSince1970: 40)
        )
        let store = harness.makeStore(
            identityAtom: identityAtom,
            datastore: harness.makeDatastore(probe: { event in
                await probeRecorder.record(event)
            })
        )

        let result = await store.loadCanonicalComposition()

        #expect(result == .failed(.defaultWorkspacePersistenceMismatch))
        #expect(await mutationOutcome.failureCount == 0)
        #expect(await probeRecorder.count(of: .saveWorkspaceSnapshot) == 1)
        #expect(await probeRecorder.count(of: .loadWorkspaceSnapshot) == 2)
        #expect(store.workspaceId == initialWorkspaceID)
        #expect(store.workspaceName == "Initial identity")
        #expect(store.panes.isEmpty)
        #expect(store.tabs.isEmpty)
    }

    @Test("invalid local active tab is ignored while authoritative core loads")
    func invalidLocalActiveTabIsIgnoredWhileAuthoritativeCoreLoads() async throws {
        let harness = try StrictSQLiteCompositionLoadHarness.make(testName: "invalid-composition")
        defer { harness.removeTemporaryFiles() }
        let workspaceID = UUIDv7.generate()
        let validSnapshot = WorkspaceSQLiteSnapshot.emptyFixture(
            id: workspaceID,
            name: "Invalid cursor source"
        )
        try await harness.datastore.saveWorkspaceSnapshotBundle(.emptyTopologyFixture(workspace: validSnapshot))
        let missingActiveTabID = UUIDv7.generate()
        let localDatabase = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: harness.localDatabaseURL(),
            label: "AgentStudio.sqlite.strict-restore.invalid-local"
        )
        try await localDatabase.write { database in
            try database.execute(
                sql: "UPDATE local_workspace_cursor SET active_tab_id = ? WHERE workspace_id = ?",
                arguments: [missingActiveTabID.uuidString, workspaceID.uuidString]
            )
        }
        try localDatabase.close()
        let store = harness.makeStore(datastore: harness.makeFreshDatastore())

        let result = await store.loadCanonicalComposition()

        guard case .loaded = result else {
            Issue.record("Expected loaded result, got \(result)")
            return
        }
        #expect(store.workspaceId == workspaceID)
        #expect(store.workspaceName == validSnapshot.name)
        #expect(store.panes.isEmpty)
        #expect(store.tabs.isEmpty)
        #expect(store.activeTabId == nil)
    }

    @Test("legacy workspace JSON beside pristine SQLite is ignored and left untouched")
    func legacyWorkspaceJSONBesidePristineSQLiteIsIgnoredAndLeftUntouched() async throws {
        let harness = try StrictSQLiteCompositionLoadHarness.make(testName: "legacy-json-ignored")
        defer { harness.removeTemporaryFiles() }
        let legacyWorkspaceID = UUIDv7.generate()
        let legacyDirectory = harness.rootDirectory.appending(path: "legacy-workspaces")
        let legacyURL = legacyDirectory.appending(
            path: "\(legacyWorkspaceID.uuidString).workspace.state.json"
        )
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        let sentinel = Data("legacy JSON must not be read, rewritten, or archived".utf8)
        try sentinel.write(to: legacyURL)
        let store = harness.makeStore()

        let result = await store.loadCanonicalComposition()

        guard case .initializedDefaultWorkspace = result else {
            Issue.record("Expected SQLite default initialization, got \(result)")
            return
        }
        #expect(store.workspaceId != legacyWorkspaceID)
        #expect(try Data(contentsOf: legacyURL) == sentinel)
        let remainingNames = try FileManager.default.contentsOfDirectory(
            at: legacyDirectory,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent)
        #expect(remainingNames == [legacyURL.lastPathComponent])
    }

    @Test("legacy per-workspace local SQLite sidecar is ignored and left untouched")
    func legacyWorkspaceLocalSQLiteSidecarIsIgnoredAndLeftUntouched() async throws {
        let harness = try StrictSQLiteCompositionLoadHarness.make(testName: "legacy-local-sidecar-ignored")
        defer { harness.removeTemporaryFiles() }
        let legacyWorkspaceID = UUIDv7.generate()
        let legacyDirectory = harness.rootDirectory.appending(path: "workspaces")
        let legacyURL = legacyDirectory.appending(
            path: "\(legacyWorkspaceID.uuidString).local.sqlite"
        )
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        let sentinel = Data("legacy local SQLite must not be opened, rewritten, or archived".utf8)
        try sentinel.write(to: legacyURL)
        let originalAttributes = try FileManager.default.attributesOfItem(atPath: legacyURL.path)
        let store = harness.makeStore()

        let result = await store.loadCanonicalComposition()

        guard case .initializedDefaultWorkspace = result else {
            Issue.record("Expected SQLite default initialization, got \(result)")
            return
        }
        #expect(store.workspaceId != legacyWorkspaceID)
        #expect(try Data(contentsOf: legacyURL) == sentinel)
        let currentAttributes = try FileManager.default.attributesOfItem(atPath: legacyURL.path)
        #expect(currentAttributes[.modificationDate] as? Date == originalAttributes[.modificationDate] as? Date)
        let remainingNames = try FileManager.default.contentsOfDirectory(
            at: legacyDirectory,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent)
        #expect(remainingNames == [legacyURL.lastPathComponent])
    }

    @Test("unavailable SQLite returns typed failure without mutation")
    func unavailableSQLiteReturnsTypedFailureWithoutMutation() async throws {
        let harness = try StrictSQLiteCompositionLoadHarness.make(testName: "sqlite-unavailable")
        defer { harness.removeTemporaryFiles() }
        let blockingFileURL = harness.rootDirectory.appending(path: "not-a-directory")
        try Data("block nested sqlite path".utf8).write(to: blockingFileURL)
        let unavailableDatastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: blockingFileURL.appending(path: "core.sqlite"),
            localDatabaseURL: blockingFileURL.appending(path: "local.sqlite")
        ).makeDatastore()
        let initialWorkspaceID = UUIDv7.generate()
        let identityAtom = WorkspaceIdentityAtom(
            workspaceId: initialWorkspaceID,
            workspaceName: "Unchanged identity",
            createdAt: Date(timeIntervalSince1970: 30)
        )
        let store = harness.makeStore(
            identityAtom: identityAtom,
            datastore: unavailableDatastore
        )

        let result = await store.loadCanonicalComposition()

        guard case .failed(.sqliteUnavailable(let failure)) = result else {
            Issue.record("Expected sqliteUnavailable failure, got \(result)")
            return
        }
        #expect(!failure.description.isEmpty)
        #expect(store.workspaceId == initialWorkspaceID)
        #expect(store.workspaceName == "Unchanged identity")
        #expect(store.panes.isEmpty)
        #expect(store.tabs.isEmpty)
    }
}

@MainActor
private struct PersistedAuthoritativeTopologyFixture {
    let workspaceID: UUID
    let storedZmxSessionID: ZmxSessionID
    let paneID: UUID
    let drawerID: UUID
    let arrangementID: UUID
    let tabID: UUID
    let pane: Pane
    let tab: Tab
    let snapshot: WorkspaceSQLiteSnapshot
    let repositoryID: UUID
    let worktreeID: UUID
    let repositoryPath: URL

    static func seed(in harness: StrictSQLiteCompositionLoadHarness) async throws -> Self {
        let fixture = try makeFixture()
        try await harness.datastore.saveWorkspaceSnapshotBundle(
            .emptyTopologyFixture(workspace: fixture.snapshot)
        )
        try fixture.persistAuthoritativeTopology(to: harness.coreDatabaseURL)
        return fixture
    }

    private static func makeFixture() throws -> Self {
        let workspaceID = UUIDv7.generate()
        let storedZmxSessionID = try #require(
            ZmxSessionID(restoring: "0197F6A4-opaque existing zmx identity ! '$`\\")
        )
        let paneID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let drawerID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        let arrangementID = UUID(uuidString: "10000000-0000-4000-8000-000000000003")!
        let tabID = UUID(uuidString: "10000000-0000-4000-8000-000000000004")!
        let pane = makePane(
            paneID: paneID,
            drawerID: drawerID,
            storedZmxSessionID: storedZmxSessionID
        )
        let tab = makeTab(
            tabID: tabID,
            paneID: paneID,
            arrangementID: arrangementID
        )
        return Self(
            workspaceID: workspaceID,
            storedZmxSessionID: storedZmxSessionID,
            paneID: paneID,
            drawerID: drawerID,
            arrangementID: arrangementID,
            tabID: tabID,
            pane: pane,
            tab: tab,
            snapshot: makeSnapshot(workspaceID: workspaceID, pane: pane, tab: tab),
            repositoryID: UUIDv7.generate(),
            worktreeID: UUIDv7.generate(),
            repositoryPath: URL(filePath: "/tmp/persisted-authoritative-topology")
        )
    }

    private static func makePane(
        paneID: UUID,
        drawerID: UUID,
        storedZmxSessionID: ZmxSessionID
    ) -> Pane {
        Pane(
            id: paneID,
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: storedZmxSessionID
                )
            ),
            metadata: PaneMetadata(
                launchDirectory: URL(filePath: "/tmp/strict-sqlite-composition-load"),
                createdAt: Date(timeIntervalSince1970: 1_700_100_000),
                title: "Stored terminal"
            ),
            residency: .active,
            kind: .layout(drawer: Drawer(drawerId: drawerID, parentPaneId: paneID))
        )
    }

    private static func makeTab(tabID: UUID, paneID: UUID, arrangementID: UUID) -> Tab {
        let arrangement = PaneArrangement(
            id: arrangementID,
            layout: Layout(paneId: paneID),
            activePaneId: paneID
        )
        return Tab(
            id: tabID,
            name: "Stored tab",
            allPaneIds: [paneID],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
    }

    private static func makeSnapshot(workspaceID: UUID, pane: Pane, tab: Tab) -> WorkspaceSQLiteSnapshot {
        WorkspaceSQLiteSnapshot(
            id: workspaceID,
            name: "Stored workspace",
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 344,
            windowFrame: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_100_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_100_001)
        )
    }

    private func persistAuthoritativeTopology(to coreDatabaseURL: URL) throws {
        let coreDatabase = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: coreDatabaseURL,
            label: "AgentStudio.sqlite.strict-restore.persisted-topology"
        )
        defer { try? coreDatabase.close() }
        let coreRepository = WorkspaceCoreRepository(databaseWriter: coreDatabase)
        try coreRepository.replaceRepositoryTopology(
            .init(
                watchedPaths: [
                    .init(
                        id: UUIDv7.generate(),
                        path: repositoryPath.deletingLastPathComponent(),
                        addedAt: Date(timeIntervalSince1970: 1_700_100_002)
                    )
                ],
                repos: [persistedRepository()],
                unavailableRepoIds: [repositoryID]
            )
        )
    }

    private func persistedRepository() -> WorkspaceCoreRepository.RepoRecord {
        WorkspaceCoreRepository.RepoRecord(
            id: repositoryID,
            name: "Persisted repository",
            repoPath: repositoryPath,
            createdAt: Date(timeIntervalSince1970: 1_700_100_003),
            worktrees: [
                WorkspaceCoreRepository.WorktreeRecord(
                    id: worktreeID,
                    repoId: repositoryID,
                    name: "main",
                    path: repositoryPath,
                    isMainWorktree: true
                )
            ]
        )
    }
}

@MainActor
private struct StrictSQLiteCompositionLoadHarness {
    let rootDirectory: URL
    let coreDatabaseURL: URL
    let datastore: WorkspaceSQLiteDatastore

    static func make(testName: String) throws -> Self {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "agentstudio-strict-composition-load-\(testName)-\(UUIDv7.generate().uuidString)"
        )
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        let factory = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: rootDirectory.appending(path: "local.sqlite")
        )
        return Self(
            rootDirectory: rootDirectory,
            coreDatabaseURL: coreDatabaseURL,
            datastore: factory.makeDatastore()
        )
    }

    func localDatabaseURL() -> URL {
        rootDirectory.appending(path: "local.sqlite")
    }

    func makeFreshDatastore() -> WorkspaceSQLiteDatastore {
        makeDatastore()
    }

    func makeDatastore(
        probe: (@Sendable (WorkspaceSQLiteDatastore.ProbeEvent) async -> Void)? = nil
    ) -> WorkspaceSQLiteDatastore {
        let rootDirectory = rootDirectory
        return WorkspaceSQLiteDatastore(
            configuration: WorkspaceSQLiteDatastoreConfiguration(
                coreDatabaseURL: coreDatabaseURL,
                localDatabaseURL: rootDirectory.appending(path: "local.sqlite")
            ),
            probe: probe
        )
    }

    func makeStore(
        identityAtom: WorkspaceIdentityAtom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate()),
        repositoryTopologyAtom: RepositoryTopologyAtom = RepositoryTopologyAtom(),
        datastore: WorkspaceSQLiteDatastore? = nil
    ) -> WorkspaceStore {
        WorkspaceStore(
            identityAtom: identityAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            sqliteDatastore: datastore ?? self.datastore
        )
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}

private actor StrictStartupProbeRecorder {
    private var events: [WorkspaceSQLiteDatastore.ProbeEvent] = []
    private let onFirstSuccessfulSave: (@Sendable () async -> Void)?
    private var didRunSuccessfulSaveAction = false

    init(onFirstSuccessfulSave: (@Sendable () async -> Void)? = nil) {
        self.onFirstSuccessfulSave = onFirstSuccessfulSave
    }

    func record(_ event: WorkspaceSQLiteDatastore.ProbeEvent) async {
        events.append(event)
        guard event == .saveWorkspaceSnapshotSucceeded, !didRunSuccessfulSaveAction else { return }
        didRunSuccessfulSaveAction = true
        await onFirstSuccessfulSave?()
    }

    func count(of event: WorkspaceSQLiteDatastore.ProbeEvent) -> Int {
        events.count { $0 == event }
    }
}

private actor StrictStartupProbeMutationOutcome {
    private(set) var failureCount = 0

    func recordFailure() {
        failureCount += 1
    }
}
