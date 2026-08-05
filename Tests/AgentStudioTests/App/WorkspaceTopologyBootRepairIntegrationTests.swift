import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Workspace topology boot repair integration", .serialized)
struct WorkspaceTopologyBootRepairIntegrationTests {
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
        let cacheCoordinator = WorkspaceCacheCoordinator(
            bus: EventBus<RuntimeEnvelope>(),
            workspaceStore: workspaceStore,
            repoCache: RepoCacheAtom(),
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
