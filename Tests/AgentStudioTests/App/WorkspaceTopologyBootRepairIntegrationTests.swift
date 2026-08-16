import Foundation
import GRDB
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Workspace topology boot repair integration", .serialized)
struct WorkspaceTopologyBootRepairIntegrationTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("boot association sweep repairs soft references, persists them, and reloads idempotently")
    func bootAssociationSweepPersistsAndReloadsIdempotently() async throws {
        let fixture = try await WorkspacePaneAssociationBootFixture.make()
        defer { fixture.removeTemporaryFiles() }
        var firstBootSummaries: [PaneAssociationBootReconciliationSummary] = []

        let firstStore = try await fixture.loadStore { summary in
            firstBootSummaries.append(summary)
        }
        fixture.assertRepairedAssociations(in: firstStore)
        #expect(
            firstBootSummaries == [
                PaneAssociationBootReconciliationSummary(
                    paneCount: 2,
                    retainedKnownCount: 0,
                    backfilledCount: 1,
                    danglingClearedCount: 1,
                    freeNilCount: 0,
                    changedCount: 2
                )
            ]
        )

        var secondBootSummaries: [PaneAssociationBootReconciliationSummary] = []

        let reloadedStore = try await fixture.loadStore { summary in
            secondBootSummaries.append(summary)
        }
        fixture.assertRepairedAssociations(in: reloadedStore)
        #expect(
            secondBootSummaries == [
                PaneAssociationBootReconciliationSummary(
                    paneCount: 2,
                    retainedKnownCount: 1,
                    backfilledCount: 0,
                    danglingClearedCount: 0,
                    freeNilCount: 1,
                    changedCount: 0
                )
            ]
        )
    }

    @Test("boot association sweep remains non-fatal when repaired soft references cannot persist")
    func bootAssociationSweepPersistenceFailureIsNonFatal() async throws {
        let fixture = try await WorkspacePaneAssociationBootFixture.make()
        defer { fixture.removeTemporaryFiles() }
        try fixture.installAssociationPersistenceFailureTrigger()
        var persistenceReasons: [PaneTopologyPersistenceReason] = []

        let store = try await fixture.loadStore(persistenceReasonReporter: { reason in
            persistenceReasons.append(reason)
        })

        fixture.assertRepairedAssociations(in: store)
        #expect(persistenceReasons.contains(.workspaceSaveDatabaseFailed))
        try fixture.assertPersistedRowsRemainUnrepaired()
    }

    @Test("boot association sweep retains a known pair while its repository is unavailable")
    func bootAssociationSweepRetainsKnownPairDuringTemporaryUnavailability() async throws {
        let fixture = try await WorkspacePaneAssociationBootFixture.make(
            unavailableKnownAssociation: true
        )
        defer { fixture.removeTemporaryFiles() }
        var summaries: [PaneAssociationBootReconciliationSummary] = []

        let store = try await fixture.loadStore { summary in
            summaries.append(summary)
        }

        let retainedFacets = store.paneAtom.graphAtom
            .paneState(fixture.legacyPaneID)?.durableContextFacets
        #expect(retainedFacets?.repoId == fixture.repositoryID)
        #expect(retainedFacets?.worktreeId == fixture.worktreeID)
        #expect(
            summaries == [
                PaneAssociationBootReconciliationSummary(
                    paneCount: 2,
                    retainedKnownCount: 1,
                    backfilledCount: 0,
                    danglingClearedCount: 1,
                    freeNilCount: 0,
                    changedCount: 1
                )
            ]
        )
    }

    @Test("boot association sweep retains a known pair when unavailable topology omits its worktree")
    func bootAssociationSweepRetainsKnownPairWhenUnavailableWorktreeIsOmitted() async throws {
        let fixture = try await WorkspacePaneAssociationBootFixture.make(
            unavailableKnownAssociation: true,
            omitUnavailableWorktree: true
        )
        defer { fixture.removeTemporaryFiles() }
        var summaries: [PaneAssociationBootReconciliationSummary] = []

        let store = try await fixture.loadStore { summary in
            summaries.append(summary)
        }

        let retainedFacets = store.paneAtom.graphAtom
            .paneState(fixture.legacyPaneID)?.durableContextFacets
        #expect(retainedFacets?.repoId == fixture.repositoryID)
        #expect(retainedFacets?.worktreeId == fixture.worktreeID)
        #expect(
            summaries == [
                PaneAssociationBootReconciliationSummary(
                    paneCount: 2,
                    retainedKnownCount: 1,
                    backfilledCount: 0,
                    danglingClearedCount: 1,
                    freeNilCount: 0,
                    changedCount: 1
                )
            ]
        )
    }

    @Test("exact-root repair persists and heals CWD-derived pane association after degraded boot")
    func exactRootRepairPersistsAndHealsDerivedAssociation() async throws {
        // Arrange: persist a production-shaped workspace whose repository has no root worktree.
        let fixture = try await WorkspaceTopologyBootRepairFixture.make()
        defer { fixture.removeTemporaryFiles() }
        var bootReasons: [PaneTopologyPersistenceReason] = []
        let bootDatastore = fixture.makeDatastore()
        guard case .prepared = await bootDatastore.prepareDatabasesForBoot() else {
            Issue.record("expected missing-main boot fixture to prepare")
            return
        }
        let topologyAtom = RepositoryTopologyAtom()
        let workspaceStore = WorkspaceStore(
            repositoryTopologyAtom: topologyAtom,
            sqliteDatastore: bootDatastore,
            persistenceReasonReporter: { reason in
                bootReasons.append(reason)
            },
            startsObserving: false
        )

        // Act: load and durably cross the normalized/degraded boot barrier.
        guard case .loaded = await workspaceStore.loadCanonicalComposition() else {
            Issue.record("expected missing-main boot fixture to load as degraded")
            return
        }
        let topologyStore = RepositoryTopologyStore(atom: topologyAtom, sqliteDatastore: bootDatastore)
        topologyStore.startObserving()
        try await topologyStore.flushAsync()

        // Assert: degradation is observable, persisted, and excluded from association authority.
        let degradedRepository = try #require(topologyAtom.repo(fixture.repositoryID))
        #expect(topologyAtom.isRepoUnavailable(fixture.repositoryID))
        #expect(!AppDelegate.hasValidMainWorktree(degradedRepository))
        #expect(topologyAtom.repoAndWorktree(containing: fixture.paneCWD) == nil)
        #expect(workspaceStore.pane(fixture.paneID)?.repoId == nil)
        #expect(workspaceStore.pane(fixture.paneID)?.worktreeId == nil)
        #expect(bootReasons.count(where: { $0 == .topologyRestoreMissingMainDegraded }) == 1)
        try await fixture.assertPersistedTopologyIsDegraded()

        // Act: validate the exact root and compose repair through the production owners.
        let scanResult = await RepoScanner().scan(
            in: fixture.repositoryPath,
            maxDepth: 0,
            discoveryProvider: fixture.exactRootDiscoveryProvider()
        )
        let repairedWorktrees = try #require(
            AppDelegate.repairedWorktrees(for: degradedRepository, from: scanResult)
        )
        let surfaceCoordinator = makeTestWorkspaceSurfaceCoordinator(
            store: workspaceStore,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: workspaceStore),
            surfaceManager: MockFilesystemCoordinatorSurfaceManager(),
            runtimeRegistry: RuntimeRegistry()
        )
        defer { Task { await surfaceCoordinator.shutdown() } }
        let cacheCoordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: RepoCacheAtom(),
            topologyEffectHandler: surfaceCoordinator,
            scopeSyncHandler: { _ in }
        )
        guard
            case .accepted = cacheCoordinator.reassociateRepo(
                repoId: fixture.repositoryID,
                to: RepoScanner.canonicalURL(fixture.repositoryPath),
                discoveredWorktrees: repairedWorktrees
            )
        else {
            Issue.record("expected authoritative exact-root repair to be accepted")
            return
        }
        try await topologyStore.flushAsync()

        // Assert: the live projection heals, then a fresh boot restores the same authority.
        let repairedRepository = try #require(topologyAtom.repo(fixture.repositoryID))
        let repairedMainWorktree = try #require(
            repairedRepository.worktrees.first(where: { $0.isMainWorktree })
        )
        #expect(!topologyAtom.isRepoUnavailable(fixture.repositoryID))
        #expect(AppDelegate.hasValidMainWorktree(repairedRepository))
        #expect(repairedMainWorktree.path == RepoScanner.canonicalURL(fixture.repositoryPath))
        #expect(workspaceStore.pane(fixture.paneID)?.repoId == fixture.repositoryID)
        #expect(workspaceStore.pane(fixture.paneID)?.worktreeId == repairedMainWorktree.id)
        try await fixture.assertFreshReloadIsRepaired(expectedMainWorktreeID: repairedMainWorktree.id)
    }
}

@MainActor
private struct WorkspacePaneAssociationBootFixture {
    let rootDirectory: URL
    let coreDatabaseURL: URL
    let localDatabaseURL: URL
    let datastore: WorkspaceSQLiteDatastore
    let repositoryID: UUID
    let worktreeID: UUID
    let legacyPaneID: UUID
    let danglingPaneID: UUID
    let worktreePath: URL

    static func make(
        unavailableKnownAssociation: Bool = false,
        omitUnavailableWorktree: Bool = false
    ) async throws -> Self {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "agentstudio-pane-association-boot-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        let localDatabaseURL = rootDirectory.appending(path: "local.sqlite")
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        ).makeDatastore()
        let fixture = Self(
            rootDirectory: rootDirectory,
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL,
            datastore: datastore,
            repositoryID: UUIDv7.generate(),
            worktreeID: UUIDv7.generate(),
            legacyPaneID: UUIDv7.generate(),
            danglingPaneID: UUIDv7.generate(),
            worktreePath: rootDirectory.appending(path: "repository", directoryHint: .isDirectory)
        )
        try await fixture.seed(
            unavailableKnownAssociation: unavailableKnownAssociation,
            omitUnavailableWorktree: omitUnavailableWorktree
        )
        return fixture
    }

    func loadStore(
        associationSummaryReporter: (
            @MainActor @Sendable (
                PaneAssociationBootReconciliationSummary
            ) -> Void
        )? = nil,
        persistenceReasonReporter: (@MainActor @Sendable (PaneTopologyPersistenceReason) -> Void)? = nil
    ) async throws -> WorkspaceStore {
        let freshDatastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        ).makeDatastore()
        guard case .prepared = await freshDatastore.prepareDatabasesForBoot() else {
            throw WorkspacePaneAssociationBootFixtureError.databasePreparationFailed
        }
        let store = WorkspaceStore(
            sqliteDatastore: freshDatastore,
            paneAssociationBootReconciliationReporter: associationSummaryReporter,
            persistenceReasonReporter: persistenceReasonReporter,
            startsObserving: false
        )
        guard case .loaded = await store.loadCanonicalComposition() else {
            throw WorkspacePaneAssociationBootFixtureError.workspaceLoadFailed
        }
        return store
    }

    func assertRepairedAssociations(in store: WorkspaceStore) {
        let legacyFacets = store.paneAtom.graphAtom
            .paneState(legacyPaneID)?.durableContextFacets
        #expect(legacyFacets?.repoId == repositoryID)
        #expect(legacyFacets?.worktreeId == worktreeID)
        let danglingFacets = store.paneAtom.graphAtom
            .paneState(danglingPaneID)?.durableContextFacets
        #expect(danglingFacets?.repoId == nil)
        #expect(danglingFacets?.worktreeId == nil)
    }

    func installAssociationPersistenceFailureTrigger() throws {
        let databasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: coreDatabaseURL,
            label: "AgentStudio.sqlite.pane-association-boot-failure"
        )
        defer { try? databasePool.close() }
        try databasePool.write { database in
            try database.execute(
                sql: """
                    CREATE TRIGGER reject_boot_association_update
                    BEFORE UPDATE OF facet_repo_id, facet_worktree_id ON pane
                    BEGIN
                        SELECT RAISE(ABORT, 'injected pane association persistence failure');
                    END
                    """
            )
        }
    }

    func assertPersistedRowsRemainUnrepaired() throws {
        let databasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: coreDatabaseURL,
            label: "AgentStudio.sqlite.pane-association-boot-rollback"
        )
        defer { try? databasePool.close() }
        try databasePool.read { database in
            let legacyRow = try Row.fetchOne(
                database,
                sql: "SELECT facet_repo_id, facet_worktree_id FROM pane WHERE id = ?",
                arguments: [legacyPaneID.uuidString]
            )
            #expect(legacyRow?["facet_repo_id"] as String? == nil)
            #expect(legacyRow?["facet_worktree_id"] as String? == nil)
            let danglingRow = try Row.fetchOne(
                database,
                sql: "SELECT facet_repo_id, facet_worktree_id FROM pane WHERE id = ?",
                arguments: [danglingPaneID.uuidString]
            )
            #expect(danglingRow?["facet_repo_id"] as String? != nil)
            #expect(danglingRow?["facet_worktree_id"] as String? != nil)
        }
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    private func seed(
        unavailableKnownAssociation: Bool,
        omitUnavailableWorktree: Bool
    ) async throws {
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            throw WorkspacePaneAssociationBootFixtureError.databasePreparationFailed
        }
        let legacyCWD = worktreePath.appending(path: "Sources", directoryHint: .isDirectory)
        let danglingCWD = rootDirectory.appending(path: "outside", directoryHint: .isDirectory)
        let legacyPane = makePane(
            id: legacyPaneID,
            launchDirectory: legacyCWD,
            facets: unavailableKnownAssociation
                ? PaneContextFacets(
                    repoId: repositoryID,
                    worktreeId: worktreeID,
                    cwd: legacyCWD
                )
                : PaneContextFacets(cwd: legacyCWD)
        )
        let danglingPane = makePane(
            id: danglingPaneID,
            launchDirectory: danglingCWD,
            facets: PaneContextFacets(
                repoId: UUIDv7.generate(),
                worktreeId: UUIDv7.generate(),
                cwd: danglingCWD
            )
        )
        let tab = makeTab(paneIds: [legacyPaneID, danglingPaneID], activePaneId: legacyPaneID)
        let workspace = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            name: "Pane association boot fixture",
            panes: [legacyPane, danglingPane],
            tabs: [tab],
            activeTabId: tab.id,
            createdAt: Date(timeIntervalSince1970: 1_700_400_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_400_001)
        )
        try await datastore.saveWorkspaceSnapshotBundle(.emptyTopologyFixture(workspace: workspace))
        try await datastore.saveRepositoryTopologySnapshot(
            RepositoryTopologySQLiteSnapshot(
                repos: [
                    CanonicalRepo(
                        id: repositoryID,
                        name: worktreePath.lastPathComponent,
                        repoPath: worktreePath
                    )
                ],
                worktrees: omitUnavailableWorktree
                    ? []
                    : [
                        CanonicalWorktree(
                            id: worktreeID,
                            repoId: repositoryID,
                            name: worktreePath.lastPathComponent,
                            path: worktreePath,
                            isMainWorktree: true
                        )
                    ],
                unavailableRepoIds: unavailableKnownAssociation ? [repositoryID] : [],
                updatedAt: Date(timeIntervalSince1970: 1_700_400_002)
            )
        )
    }
}

private enum WorkspacePaneAssociationBootFixtureError: Error {
    case databasePreparationFailed
    case workspaceLoadFailed
}

@MainActor
private struct WorkspaceTopologyBootRepairFixture {
    let rootDirectory: URL
    let coreDatabaseURL: URL
    let localDatabaseURL: URL
    let repositoryID: UUID
    let linkedWorktreeID: UUID
    let paneID: UUID
    let repositoryPath: URL
    let linkedWorktreePath: URL
    let paneCWD: URL

    static func make() async throws -> Self {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "agentstudio-topology-boot-repair-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let repositoryPath = rootDirectory.appending(
            path: "repository",
            directoryHint: .isDirectory
        )
        let linkedWorktreePath = rootDirectory.appending(
            path: "linked-worktree",
            directoryHint: .isDirectory
        )
        let paneCWD = repositoryPath.appending(
            path: "Sources",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: repositoryPath.appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: linkedWorktreePath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paneCWD, withIntermediateDirectories: true)
        let fixture = Self(
            rootDirectory: rootDirectory,
            coreDatabaseURL: rootDirectory.appending(path: "core.sqlite"),
            localDatabaseURL: rootDirectory.appending(path: "local.sqlite"),
            repositoryID: UUIDv7.generate(),
            linkedWorktreeID: UUIDv7.generate(),
            paneID: UUIDv7.generate(),
            repositoryPath: repositoryPath,
            linkedWorktreePath: linkedWorktreePath,
            paneCWD: paneCWD
        )
        try await fixture.seedMissingMainTopology()
        return fixture
    }

    func makeDatastore() -> WorkspaceSQLiteDatastore {
        WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        ).makeDatastore()
    }

    func exactRootDiscoveryProvider() -> ExactRootDiscoveryProvider {
        let canonicalRepositoryPath = RepoScanner.canonicalURL(repositoryPath)
        return ExactRootDiscoveryProvider(
            canonicalRepositoryPath: canonicalRepositoryPath,
            entry: RepoScanner.ResolvedGitEntry(
                path: canonicalRepositoryPath,
                kind: .cloneRoot,
                repositoryKey: "workspace-topology-boot-repair"
            )
        )
    }

    func assertPersistedTopologyIsDegraded() async throws {
        let datastore = makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("expected degraded topology datastore to prepare")
            return
        }
        guard case .loaded(let snapshot) = await datastore.loadRepositoryTopologySnapshot() else {
            Issue.record("expected degraded topology snapshot to reload")
            return
        }
        let repository = try #require(snapshot.repos.single)
        #expect(repository.id == repositoryID)
        #expect(snapshot.unavailableRepoIds == [repositoryID])
        #expect(snapshot.worktrees.map(\.id) == [linkedWorktreeID])
        #expect(!snapshot.worktrees.contains(where: { $0.isMainWorktree }))
    }

    func assertFreshReloadIsRepaired(expectedMainWorktreeID: UUID) async throws {
        var reloadReasons: [PaneTopologyPersistenceReason] = []
        let datastore = makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("expected repaired topology datastore to prepare")
            return
        }
        let topologyAtom = RepositoryTopologyAtom()
        let workspaceStore = WorkspaceStore(
            repositoryTopologyAtom: topologyAtom,
            sqliteDatastore: datastore,
            persistenceReasonReporter: { reason in
                reloadReasons.append(reason)
            },
            startsObserving: false
        )
        guard case .loaded = await workspaceStore.loadCanonicalComposition() else {
            Issue.record("expected repaired topology workspace to reload")
            return
        }

        let repository = try #require(topologyAtom.repo(repositoryID))
        let mainWorktree = try #require(
            repository.worktrees.first(where: { $0.isMainWorktree })
        )
        #expect(!topologyAtom.isRepoUnavailable(repositoryID))
        #expect(AppDelegate.hasValidMainWorktree(repository))
        #expect(mainWorktree.id == expectedMainWorktreeID)
        #expect(mainWorktree.path == RepoScanner.canonicalURL(repositoryPath))
        #expect(repository.worktrees.contains(where: { $0.id == linkedWorktreeID }))
        #expect(workspaceStore.pane(paneID)?.repoId == repositoryID)
        #expect(workspaceStore.pane(paneID)?.worktreeId == expectedMainWorktreeID)
        #expect(!reloadReasons.contains(.topologyRestoreMissingMainDegraded))
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    private func seedMissingMainTopology() async throws {
        let datastore = makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("expected boot repair seed databases to prepare")
            return
        }
        try await datastore.saveWorkspaceSnapshotBundle(
            .emptyTopologyFixture(workspace: makeWorkspaceSnapshot())
        )
        try await datastore.saveRepositoryTopologySnapshot(
            RepositoryTopologySQLiteSnapshot(
                repos: [
                    CanonicalRepo(
                        id: repositoryID,
                        name: repositoryPath.lastPathComponent,
                        repoPath: repositoryPath
                    )
                ],
                worktrees: [
                    CanonicalWorktree(
                        id: linkedWorktreeID,
                        repoId: repositoryID,
                        name: linkedWorktreePath.lastPathComponent,
                        path: linkedWorktreePath,
                        isMainWorktree: false,
                        note: "linked worktree survives repair"
                    )
                ],
                unavailableRepoIds: [],
                updatedAt: Date(timeIntervalSince1970: 1_700_300_002)
            )
        )
    }

    private func makeWorkspaceSnapshot() -> WorkspaceSQLiteSnapshot {
        let pane = Pane(
            id: paneID,
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )
            ),
            metadata: PaneMetadata(
                launchDirectory: paneCWD,
                createdAt: Date(timeIntervalSince1970: 1_700_300_000),
                title: "Missing-main repair pane",
                note: "pane survives degraded boot and repair"
            )
        )
        let tab = Tab(paneId: paneID, name: "Boot repair tab")
        return WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            name: "Topology boot repair workspace",
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 320,
            createdAt: Date(timeIntervalSince1970: 1_700_300_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_300_001)
        )
    }
}

private struct ExactRootDiscoveryProvider: RepoScanner.GitRepositoryDiscoveryProvider {
    let canonicalRepositoryPath: URL
    let entry: RepoScanner.ResolvedGitEntry

    func discoveryOutcome(for url: URL) async -> GitRepositoryDiscoveryOutcome {
        RepoScanner.canonicalURL(url) == canonicalRepositoryPath
            ? .validated(entry)
            : .authoritativeNegative(.notAValidWorktree)
    }
}
