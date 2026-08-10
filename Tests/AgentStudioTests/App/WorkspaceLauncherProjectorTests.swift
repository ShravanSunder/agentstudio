import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInboxNotification
@testable import AgentStudioTestSupport

@Suite(.serialized)
@MainActor
struct WorkspaceLauncherProjectorTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    private func makeStore(atoms: AtomRegistry) -> WorkspaceStore {
        atoms.core.repoCache.clear()
        atoms.core.applicationEntityRecency.clear()
        let store = WorkspaceStore(
            identityAtom: atoms.core.workspaceIdentity,
            windowMemoryAtom: atoms.core.workspaceWindowMemory,
            repositoryTopologyAtom: atoms.core.workspaceRepositoryTopology,
            paneAtom: atoms.core.workspacePane,
            tabLayoutAtom: atoms.core.workspaceTabLayout,
            mutationCoordinator: atoms.core.workspaceMutationCoordinator)
        return store
    }

    private func recordWorktreeRecency(
        atoms: AtomRegistry,
        worktree: Worktree,
        at timestamp: Date = Date(timeIntervalSince1970: 100)
    ) throws {
        atoms.core.applicationEntityRecency.record(
            try ApplicationEntityRecency(
                entity: .worktree(worktreeStableKey: worktree.stableKey),
                interaction: .opened,
                lastInteractedAt: timestamp
            )
        )
    }

    @Test
    func project_noRepos_returnsFolderIntakeState() {
        withWorkspaceLauncherAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.core.workspaceIdentity,
                windowMemoryAtom: atoms.core.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.core.workspaceRepositoryTopology,
                paneAtom: atoms.core.workspacePane,
                tabLayoutAtom: atoms.core.workspaceTabLayout,
                mutationCoordinator: atoms.core.workspaceMutationCoordinator
            )
            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.kind == .noFolders)
            #expect(result.recentCards.isEmpty)
            #expect(result.showsOpenAll == false)
        }
    }

    @Test
    func project_scanningWithoutRepos_returnsScanningState() {
        withWorkspaceLauncherAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            atoms.core.welcome.beginFolderScan(URL(fileURLWithPath: "/tmp/scanning-root"))

            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.kind == .scanning(URL(fileURLWithPath: "/tmp/scanning-root")))
            #expect(result.recentCards.isEmpty)
        }
    }

    @Test
    func project_emptyFolderScanWithoutRepos_returnsEmptyScanState() {
        withWorkspaceLauncherAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            atoms.core.welcome.completeFolderScan(
                rootPath: URL(fileURLWithPath: "/tmp/empty-root"),
                discoveredRepoCount: 0
            )

            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.kind == .scanEmpty(URL(fileURLWithPath: "/tmp/empty-root")))
            #expect(result.recentCards.isEmpty)
            #expect(result.showsOpenAll == false)
        }
    }

    @Test
    func project_emptyFolderScanWithRepos_returnsLauncherState() {
        withWorkspaceLauncherAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            _ = store.mutationCoordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            atoms.core.welcome.completeFolderScan(
                rootPath: URL(fileURLWithPath: "/tmp/empty-root"),
                discoveredRepoCount: 0
            )

            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.kind == .launcher)
        }
    }

    @Test
    func project_choosingFolderWithoutRepos_returnsChoosingFolderState() {
        withWorkspaceLauncherAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            atoms.core.welcome.beginChoosingFolder()

            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.kind == .choosingFolder)
            #expect(result.recentCards.isEmpty)
        }
    }

    @Test
    func project_scanningOutranksChoosingFolderWhenReposAreEmpty() {
        withWorkspaceLauncherAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            atoms.core.welcome.beginChoosingFolder()
            atoms.core.welcome.beginFolderScan(URL(fileURLWithPath: "/tmp/scanning-root"))

            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.kind == .scanning(URL(fileURLWithPath: "/tmp/scanning-root")))
        }
    }

    @Test
    func project_launcherWinsWhenReposExistEvenIfChoosingFolderIsTrue() {
        withWorkspaceLauncherAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            _ = store.mutationCoordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            atoms.core.welcome.beginChoosingFolder()

            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.kind == .launcher)
        }
    }

    @Test
    func project_reposButNoTabs_returnsLauncherStateWithEnrichedCards() throws {
        try withWorkspaceLauncherAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.core.workspaceIdentity,
                windowMemoryAtom: atoms.core.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.core.workspaceRepositoryTopology,
                paneAtom: atoms.core.workspacePane,
                tabLayoutAtom: atoms.core.workspaceTabLayout,
                mutationCoordinator: atoms.core.workspaceMutationCoordinator
            )
            let repo = store.mutationCoordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
                Issue.record("Expected main worktree")
                return
            }

            atoms.core.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    branch: "main"
                )
            )
            atoms.core.repoCache.setPullRequestCount(3, for: worktree.id)
            let approvalPaneId = UUID()
            atoms.inboxNotification.append(
                InboxNotification(
                    id: UUID(),
                    timestamp: Date(timeIntervalSince1970: 1),
                    kind: .approvalRequested,
                    title: "Approval",
                    body: nil,
                    source: .pane(
                        .init(
                            paneId: approvalPaneId,
                            worktreeId: worktree.id,
                            worktreeName: worktree.name
                        )
                    ),
                    claimKey: .init(
                        paneId: approvalPaneId,
                        lane: .actionNeeded,
                        semantic: .approvalRequested,
                        sessionId: nil
                    ),
                    isRead: false,
                    isDismissedFromPaneInbox: false
                )
            )
            let securityPaneId = UUID()
            atoms.inboxNotification.append(
                InboxNotification(
                    id: UUID(),
                    timestamp: Date(timeIntervalSince1970: 2),
                    kind: .securityEvent,
                    title: "Security",
                    body: nil,
                    source: .pane(
                        .init(
                            paneId: securityPaneId,
                            worktreeId: worktree.id,
                            worktreeName: worktree.name
                        )
                    ),
                    claimKey: .init(
                        paneId: securityPaneId,
                        lane: .safety,
                        semantic: .securityEvent,
                        sessionId: nil
                    ),
                    isRead: false,
                    isDismissedFromPaneInbox: false
                )
            )
            try recordWorktreeRecency(atoms: atoms, worktree: worktree)

            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.kind == .launcher)
            #expect(result.recentCards.count == 1)
            #expect(result.recentCards[0].title == worktree.name)
            #expect(result.recentCards[0].detail == "main")
            #expect(result.recentCards[0].checkoutIconKind == .mainCheckout)
            #expect(result.recentCards[0].iconColorHex == RepoPresentationGrouping.automaticPaletteHexes[0])
            #expect(result.recentCards[0].statusChips?.branchStatus.prCount == 3)
            #expect(result.recentCards[0].statusChips?.notificationCount == 2)
            #expect(result.showsOpenAll == false)
        }
    }

    @Test
    func project_reposAndTabsPresent_returnsEmptyLauncherModel() throws {
        try withWorkspaceLauncherAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.core.workspaceIdentity,
                windowMemoryAtom: atoms.core.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.core.workspaceRepositoryTopology,
                paneAtom: atoms.core.workspacePane,
                tabLayoutAtom: atoms.core.workspaceTabLayout,
                mutationCoordinator: atoms.core.workspaceMutationCoordinator
            )
            let repo = store.mutationCoordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
                Issue.record("Expected main worktree")
                return
            }

            let pane = store.paneAtom.createPane(
                launchDirectory: worktree.path,
                title: "Terminal",
                zmxSessionID: .generateUUIDv7(),
                facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
            )
            store.tabLayoutAtom.appendTab(Tab(paneId: pane.id))
            try recordWorktreeRecency(atoms: atoms, worktree: worktree)

            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.kind == .launcher)
            #expect(result.recentCards.isEmpty)
            #expect(result.showsOpenAll == false)
        }
    }

    @Test
    func project_launcherCapsAtFifteenAndShowsOpenAllForTwoOrMoreTargets() throws {
        try withWorkspaceLauncherAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            let repo = store.mutationCoordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            let worktrees = (0..<20).map { index in
                Worktree(
                    repoId: repo.id,
                    name: "worktree-\(index)",
                    path: repo.repoPath.appending(path: "worktree-\(index)")
                )
            }
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: repo.worktrees + worktrees)

            for (index, worktree) in worktrees.enumerated() {
                try recordWorktreeRecency(
                    atoms: atoms,
                    worktree: worktree,
                    at: Date(timeIntervalSince1970: TimeInterval(index))
                )
            }

            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.recentCards.count == 15)
            #expect(result.showsOpenAll == true)
        }
    }

    @Test
    func project_applicationWorktreeRecency_usesLiveTopologyPresentation() throws {
        try withWorkspaceLauncherAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/live-recency-repo"))
            let originalWorktree = try #require(store.repo(repo.id)?.worktrees.first)
            let recency = try ApplicationEntityRecency(
                entity: .worktree(worktreeStableKey: originalWorktree.stableKey),
                interaction: .opened,
                lastInteractedAt: Date(timeIntervalSince1970: 500)
            )
            atoms.core.applicationEntityRecency.record(recency)
            let liveWorktree = Worktree(
                id: originalWorktree.id,
                repoId: repo.id,
                name: "live-worktree-name",
                path: originalWorktree.path,
                isMainWorktree: originalWorktree.isMainWorktree
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [liveWorktree])

            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.recentCards.count == 1)
            #expect(
                result.recentCards[0].target
                    == .worktree(worktreeStableKey: liveWorktree.stableKey)
            )
            #expect(result.recentCards[0].title == "live-worktree-name")
        }
    }

    @Test
    func project_applicationRepositoryRecency_resolvesLiveCanonicalDefaultWorktree() throws {
        try withWorkspaceLauncherAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            let repo = store.addRepo(at: URL(fileURLWithPath: "/tmp/live-repository-recency"))
            let secondary = Worktree(
                repoId: repo.id,
                name: "secondary",
                path: repo.repoPath.appending(path: "secondary")
            )
            let main = Worktree(
                repoId: repo.id,
                name: "main",
                path: repo.repoPath,
                isMainWorktree: true
            )
            store.reconcileDiscoveredWorktrees(repo.id, worktrees: [secondary, main])
            atoms.core.applicationEntityRecency.record(
                try ApplicationEntityRecency(
                    entity: .repository(repositoryStableKey: repo.stableKey),
                    interaction: .opened,
                    lastInteractedAt: Date(timeIntervalSince1970: 600)
                )
            )

            let result = WorkspaceLauncherProjector.project(
                store: store,
                inboxAtom: atoms.inboxNotification
            )
            let activationWorktree = WorkspaceLauncherProjector.resolveActivationWorktree(
                target: .repository(repositoryStableKey: repo.stableKey),
                repositoryTopology: store.repositoryTopologyAtom
            )

            #expect(result.recentCards.count == 1)
            #expect(result.recentCards[0].title == repo.name)
            #expect(activationWorktree?.stableKey == main.stableKey)
            #expect(activationWorktree?.isMainWorktree == true)
        }
    }

    @Test
    func staleApplicationRecency_resolvesNoActivationAndPrunesWithoutRecording() throws {
        try withWorkspaceLauncherAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            _ = store.addRepo(at: URL(fileURLWithPath: "/tmp/current-repository"))
            let staleTarget = ApplicationRecentEntity.worktree(
                worktreeStableKey: StableKey.fromPath(
                    URL(fileURLWithPath: "/tmp/missing-worktree")
                )
            )
            atoms.core.applicationEntityRecency.record(
                try ApplicationEntityRecency(
                    entity: staleTarget,
                    interaction: .opened,
                    lastInteractedAt: Date(timeIntervalSince1970: 700)
                )
            )

            let activationWorktree = WorkspaceLauncherProjector.resolveActivationWorktree(
                target: staleTarget,
                repositoryTopology: store.repositoryTopologyAtom
            )
            let recencyCountBeforePrune = atoms.core.applicationEntityRecency.recentEntities.count
            WorkspaceLauncherProjector.pruneStaleTarget(
                staleTarget,
                applicationRecency: atoms.core.applicationEntityRecency
            )

            #expect(activationWorktree == nil)
            #expect(recencyCountBeforePrune == 1)
            #expect(atoms.core.applicationEntityRecency.recentEntities.isEmpty)
        }
    }

    @Test
    func unavailableRepositoryRecency_projectsNoCardsAndResolvesNoActivation() throws {
        try withWorkspaceLauncherAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            let repository = store.addRepo(at: URL(filePath: "/tmp/unavailable-recent-repository"))
            let worktree = try #require(repository.worktrees.first)
            try atoms.core.applicationEntityRecency.recordOpened(
                repositoryStableKey: repository.stableKey,
                worktreeStableKey: worktree.stableKey,
                at: Date(timeIntervalSince1970: 800)
            )
            store.markRepoUnavailable(repository.id)

            let result = WorkspaceLauncherProjector.project(
                store: store,
                inboxAtom: atoms.inboxNotification
            )
            let repositoryActivation = WorkspaceLauncherProjector.resolveActivationWorktree(
                target: .repository(repositoryStableKey: repository.stableKey),
                repositoryTopology: store.repositoryTopologyAtom
            )
            let worktreeActivation = WorkspaceLauncherProjector.resolveActivationWorktree(
                target: .worktree(worktreeStableKey: worktree.stableKey),
                repositoryTopology: store.repositoryTopologyAtom
            )

            #expect(result.recentCards.isEmpty)
            #expect(repositoryActivation == nil)
            #expect(worktreeActivation == nil)
        }
    }
}

@MainActor
private func withWorkspaceLauncherAtomRegistry<T>(
    _ body: (AtomRegistry) throws -> T
) rethrows -> T {
    let atomRegistry = makeTestAtomRegistry()
    return try withTestCoreAtoms(using: atomRegistry.core) { _ in
        try body(atomRegistry)
    }
}
