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
        let store = WorkspaceStore(
            identityAtom: atoms.core.workspaceIdentity,
            windowMemoryAtom: atoms.core.workspaceWindowMemory,
            repositoryTopologyAtom: atoms.core.workspaceRepositoryTopology,
            paneAtom: atoms.core.workspacePane,
            tabLayoutAtom: atoms.core.workspaceTabLayout,
            mutationCoordinator: atoms.core.workspaceMutationCoordinator)
        return store
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
    func project_reposButNoTabs_returnsLauncherStateWithEnrichedCards() {
        withWorkspaceLauncherAtomRegistry { atoms in
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
            atoms.core.repoCache.recordRecentTarget(.forWorktree(path: worktree.path, worktree: worktree, repo: repo))

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
    func project_reposAndTabsPresent_returnsEmptyLauncherModel() {
        withWorkspaceLauncherAtomRegistry { atoms in
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
            atoms.core.repoCache.recordRecentTarget(.forWorktree(path: worktree.path, worktree: worktree, repo: repo))

            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.kind == .launcher)
            #expect(result.recentCards.isEmpty)
            #expect(result.showsOpenAll == false)
        }
    }

    @Test
    func project_launcherCapsAtFifteenAndShowsOpenAllForTwoOrMoreTargets() {
        withWorkspaceLauncherAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            let repo = store.mutationCoordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
                Issue.record("Expected main worktree")
                return
            }

            let cache = atoms.core.repoCache
            for index in 0..<20 {
                cache.recordRecentTarget(
                    .forCwd(
                        worktree.path.appending(path: "nested-\(index)"),
                        title: "nested-\(index)",
                        subtitle: repo.name
                    )
                )
            }

            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.recentCards.count == 15)
            #expect(result.showsOpenAll == true)
        }
    }

    @Test
    func project_unresolvedRecentTarget_isDroppedFromLauncherCards() {
        withWorkspaceLauncherAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            _ = store.mutationCoordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))

            let cache = atoms.core.repoCache
            cache.recordRecentTarget(.forCwd(URL(fileURLWithPath: "/tmp/missing-project")))

            let result = WorkspaceLauncherProjector.project(store: store, inboxAtom: atoms.inboxNotification)

            #expect(result.kind == .launcher)
            #expect(result.recentCards.isEmpty)
            #expect(result.showsOpenAll == false)
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
