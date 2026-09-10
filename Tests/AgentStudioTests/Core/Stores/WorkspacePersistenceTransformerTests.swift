import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Workspace persistence transformer")
struct WorkspacePersistenceTransformerTests {
    @Test("topology bridge preserves repository and worktree metadata")
    func topologyBridgePreservesMetadata() throws {
        // Arrange
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let topologyAtom = RepositoryTopologyAtom()
        let snapshot = RepositoryTopologySQLiteSnapshot(
            repos: [
                CanonicalRepo(
                    id: repositoryID,
                    name: "agent-studio",
                    repoPath: URL(filePath: "/tmp/agent-studio-metadata"),
                    isFavorite: true,
                    note: "repository note",
                    tags: ["client"]
                )
            ],
            worktrees: [
                CanonicalWorktree(
                    id: worktreeID,
                    repoId: repositoryID,
                    name: "main",
                    path: URL(filePath: "/tmp/agent-studio-metadata"),
                    isMainWorktree: true,
                    note: "worktree note"
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        // Act
        WorkspacePersistenceTransformer.hydrateRepositoryTopology(
            snapshot,
            repositoryTopologyAtom: topologyAtom
        )

        // Assert
        #expect(topologyAtom.repo(repositoryID)?.isFavorite == true)
        #expect(topologyAtom.repo(repositoryID)?.note == "repository note")
        #expect(topologyAtom.repo(repositoryID)?.tags == ["client"])
        #expect(topologyAtom.worktree(worktreeID)?.note == "worktree note")
    }

    @Test("topology hydration preserves stored stable identity instead of hashing paths")
    func topologyHydrationPreservesStoredStableIdentity() {
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let watchedPathID = UUIDv7.generate()
        let repositoryPath = URL(filePath: "/tmp/agent-studio-persisted-stable-identity")
        let storedRepositoryKey = "stored-repo-key"
        let storedWatchedPathKey = "stored-watch-key"
        let snapshot = RepositoryTopologySQLiteSnapshot(
            repos: [
                CanonicalRepo(
                    id: repositoryID,
                    name: "persisted-stable-identity",
                    repoPath: repositoryPath,
                    stableKey: storedRepositoryKey
                )
            ],
            worktrees: [
                CanonicalWorktree(
                    id: worktreeID,
                    repoId: repositoryID,
                    name: "main",
                    path: repositoryPath,
                    stableKey: storedRepositoryKey,
                    isMainWorktree: true
                )
            ],
            watchedPaths: [
                WatchedPath(
                    id: watchedPathID,
                    path: URL(filePath: "/tmp/agent-studio-persisted-watched")
                )
            ],
            watchedPathStableKeysByID: [watchedPathID: storedWatchedPathKey],
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let topologyAtom = RepositoryTopologyAtom()

        WorkspacePersistenceTransformer.hydrateRepositoryTopology(
            snapshot,
            repositoryTopologyAtom: topologyAtom
        )

        #expect(topologyAtom.repositoryStableKey(for: repositoryID) == storedRepositoryKey)
        #expect(topologyAtom.worktreeStableKey(for: worktreeID) == storedRepositoryKey)
        #expect(topologyAtom.repo(stableKey: storedRepositoryKey)?.id == repositoryID)
        #expect(topologyAtom.watchedPath(stableKey: storedWatchedPathKey)?.id == watchedPathID)
        #expect(topologyAtom.repo(stableKey: StableKey.fromPath(repositoryPath)) == nil)
    }

    @Test("topology restore promotes the unique repository-root worktree without changing identity")
    func topologyRestorePromotesUniqueRepositoryRootWorktree() async throws {
        let repositoryID = UUIDv7.generate()
        let rootWorktreeID = UUIDv7.generate()
        let linkedWorktreeID = UUIDv7.generate()
        let repositoryPath = URL(filePath: "/tmp/agent-studio-normalized-main")
        let snapshot = RepositoryTopologySQLiteSnapshot(
            repos: [
                CanonicalRepo(id: repositoryID, name: "normalized-main", repoPath: repositoryPath)
            ],
            worktrees: [
                CanonicalWorktree(
                    id: rootWorktreeID,
                    repoId: repositoryID,
                    name: "root",
                    path: repositoryPath,
                    isMainWorktree: false,
                    note: "root note survives promotion"
                ),
                CanonicalWorktree(
                    id: linkedWorktreeID,
                    repoId: repositoryID,
                    name: "linked",
                    path: URL(filePath: "/tmp/agent-studio-normalized-main-linked"),
                    isMainWorktree: true
                ),
            ],
            unavailableRepoIds: [repositoryID],
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        let preparation = await WorkspacePersistenceTransformer.prepareRepositoryTopologyOffMain(snapshot)
        let reasons = await WorkspacePersistenceTransformer.topologyRestoreReasonsOffMain(snapshot)

        guard case .prepared(let replacement) = preparation else {
            Issue.record("Expected stored topology normalization to be accepted")
            return
        }
        let normalizedRepository = try #require(replacement.repositories.single)
        #expect(normalizedRepository.worktrees.first(where: { $0.id == rootWorktreeID })?.isMainWorktree == true)
        #expect(
            normalizedRepository.worktrees.first(where: { $0.id == rootWorktreeID })?.note
                == "root note survives promotion"
        )
        #expect(normalizedRepository.worktrees.first(where: { $0.id == linkedWorktreeID })?.isMainWorktree == false)
        #expect(replacement.unavailableRepositoryIDs.contains(repositoryID))
        #expect(reasons == [.topologyRestoreMainRoleRepaired])
    }

    @Test("topology restore marks a repository without a root worktree unavailable")
    func topologyRestoreMarksMissingRootWorktreeUnavailable() async {
        let repositoryID = UUIDv7.generate()
        let repositoryPath = URL(filePath: "/tmp/agent-studio-missing-main")
        let snapshot = RepositoryTopologySQLiteSnapshot(
            repos: [
                CanonicalRepo(id: repositoryID, name: "missing-main", repoPath: repositoryPath)
            ],
            worktrees: [
                CanonicalWorktree(
                    id: UUIDv7.generate(),
                    repoId: repositoryID,
                    name: "linked",
                    path: URL(filePath: "/tmp/agent-studio-missing-main-linked"),
                    isMainWorktree: false
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        let preparation = await WorkspacePersistenceTransformer.prepareRepositoryTopologyOffMain(snapshot)
        let reasons = await WorkspacePersistenceTransformer.topologyRestoreReasonsOffMain(snapshot)

        guard case .prepared(let replacement) = preparation else {
            Issue.record("Expected degraded stored topology to remain loadable")
            return
        }
        #expect(replacement.unavailableRepositoryIDs.contains(repositoryID))
        #expect(reasons == [.topologyRestoreMissingMainDegraded])
    }

    @Test("topology restore discards every ambiguous root while preserving linked worktrees")
    func topologyRestoreDiscardsAmbiguousRootsAsUnavailable() async throws {
        let repositoryID = UUIDv7.generate()
        let firstWorktreeID = UUIDv7.generate()
        let secondWorktreeID = UUIDv7.generate()
        let linkedWorktreeID = UUIDv7.generate()
        let repositoryPath = URL(filePath: "/tmp/agent-studio-duplicate-root-restore")
        let linkedWorktreePath = URL(filePath: "/tmp/agent-studio-duplicate-root-restore-linked")
        let snapshot = RepositoryTopologySQLiteSnapshot(
            repos: [
                CanonicalRepo(
                    id: repositoryID,
                    name: repositoryPath.lastPathComponent,
                    repoPath: repositoryPath,
                    stableKey: "persisted-repository-identity"
                )
            ],
            worktrees: [
                CanonicalWorktree(
                    id: firstWorktreeID,
                    repoId: repositoryID,
                    name: "root-one",
                    path: repositoryPath,
                    stableKey: "persisted-root-one-identity",
                    isMainWorktree: true
                ),
                CanonicalWorktree(
                    id: secondWorktreeID,
                    repoId: repositoryID,
                    name: "root-two",
                    path: repositoryPath,
                    stableKey: "persisted-root-two-identity",
                    isMainWorktree: false
                ),
                CanonicalWorktree(
                    id: linkedWorktreeID,
                    repoId: repositoryID,
                    name: "linked",
                    path: linkedWorktreePath,
                    stableKey: "persisted-linked-identity",
                    isMainWorktree: false,
                    note: "linked note survives"
                ),
            ],
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        let preparation = await WorkspacePersistenceTransformer.prepareRepositoryTopologyOffMain(snapshot)
        let reasons = await WorkspacePersistenceTransformer.topologyRestoreReasonsOffMain(snapshot)

        guard case .prepared(let replacement) = preparation else {
            Issue.record("expected duplicate roots to degrade without rejecting startup")
            return
        }
        let restoredRepository = try #require(replacement.repositories.single)
        let preservedLinkedWorktree = try #require(restoredRepository.worktrees.single)
        #expect(preservedLinkedWorktree.id == linkedWorktreeID)
        #expect(preservedLinkedWorktree.path == linkedWorktreePath)
        #expect(preservedLinkedWorktree.note == "linked note survives")
        #expect(!preservedLinkedWorktree.isMainWorktree)
        #expect(replacement.unavailableRepositoryIDs == [repositoryID])
        #expect(
            reasons
                == [
                    .paneTopologyAssociationAmbiguous,
                    .topologyRestoreMissingMainDegraded,
                ]
        )
    }

    @Test("boot pane reconciliation retires legacy orphaned residency from canonical ownership")
    func bootPaneReconciliationRetiresLegacyOrphanedResidencyFromCanonicalOwnership() async throws {
        // Arrange
        let ownedPaneID = UUIDv7.generate()
        let ownedDrawerPaneID = UUIDv7.generate()
        let unownedPaneID = UUIDv7.generate()
        let drawerID = UUIDv7.generate()
        let missingRoot = URL(filePath: "/deleted/worktree", directoryHint: .isDirectory)
        let terminalContent = PaneContent.terminal(
            TerminalState(
                provider: .zmx,
                lifetime: .persistent,
                zmxSessionID: .generateUUIDv7()
            )
        )
        let ownedPane = Pane(
            id: ownedPaneID,
            content: terminalContent,
            metadata: PaneMetadata(launchDirectory: missingRoot, facets: PaneContextFacets(cwd: missingRoot)),
            residency: .orphaned(reason: .worktreeNotFound(path: missingRoot.path)),
            kind: .layout(
                drawer: Drawer(
                    drawerId: drawerID,
                    parentPaneId: ownedPaneID,
                    paneIds: [ownedDrawerPaneID]
                )
            )
        )
        let ownedDrawerPane = Pane(
            id: ownedDrawerPaneID,
            content: terminalContent,
            metadata: PaneMetadata(launchDirectory: missingRoot, facets: PaneContextFacets(cwd: missingRoot)),
            residency: .orphaned(reason: .worktreeNotFound(path: missingRoot.path)),
            kind: .drawerChild(parentPaneId: ownedPaneID)
        )
        let unownedPane = Pane(
            id: unownedPaneID,
            content: terminalContent,
            metadata: PaneMetadata(launchDirectory: missingRoot, facets: PaneContextFacets(cwd: missingRoot)),
            residency: .orphaned(reason: .worktreeNotFound(path: missingRoot.path))
        )
        let arrangement = PaneArrangement(
            layout: Layout(paneId: ownedPaneID),
            drawerViews: [
                drawerID: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: ownedDrawerPaneID))
                )
            ]
        )
        let tab = Tab(
            name: "Recovered",
            allPaneIds: [ownedPaneID, ownedDrawerPaneID],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id
        )
        let workspace = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            panes: [ownedPane, ownedDrawerPane, unownedPane],
            tabs: [tab],
            activeTabId: tab.id
        )
        let topologyPreparation = WorkspacePersistenceTransformer.prepareRepositoryTopology(
            RepositoryTopologySQLiteSnapshot(updatedAt: Date(timeIntervalSince1970: 1))
        )
        guard case .prepared(let topology) = topologyPreparation else {
            Issue.record("expected empty repository topology to prepare")
            return
        }

        // Act
        let result = await WorkspacePersistenceTransformer.reconcilePanesForBootOffMain(
            in: workspace,
            topology: topology
        )

        // Assert
        let panesByID = Dictionary(uniqueKeysWithValues: result.workspace.panes.map { ($0.id, $0) })
        #expect(panesByID[ownedPaneID]?.residency == .active)
        #expect(panesByID[ownedDrawerPaneID]?.residency == .active)
        #expect(panesByID[unownedPaneID]?.residency == .backgrounded)
        #expect(result.repairedLegacyOrphanedResidencyCount == 3)
        #expect(result.didChange)

        let repeatedResult = await WorkspacePersistenceTransformer.reconcilePanesForBootOffMain(
            in: result.workspace,
            topology: topology
        )
        #expect(repeatedResult.repairedLegacyOrphanedResidencyCount == 0)
        #expect(!repeatedResult.didChange)
    }

    @Test("composition conversion excludes repository topology")
    func compositionConversionExcludesRepositoryTopology() {
        // Arrange
        let pane = Pane(
            id: UUIDv7.generate(),
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )),
            metadata: PaneMetadata(title: "Exact")
        )
        let tab = Tab(paneId: pane.id, name: "Exact tab")
        let snapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            name: "Exact workspace",
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 321,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        // Act
        let bundle = WorkspaceSQLiteSaveBundle(workspace: snapshot)

        // Assert
        #expect(bundle.workspace == snapshot)
    }
}
