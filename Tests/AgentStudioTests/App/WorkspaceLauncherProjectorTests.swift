import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct WorkspaceLauncherProjectorTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    private func makeStore(atoms: AtomRegistry) -> WorkspaceStore {
        atoms.repoCache.clear()
        let store = WorkspaceStore(
            identityAtom: atoms.workspaceIdentity,
            windowMemoryAtom: atoms.workspaceWindowMemory,
            repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
            paneAtom: atoms.workspacePane,
            tabLayoutAtom: atoms.workspaceTabLayout,
            mutationCoordinator: atoms.workspaceMutationCoordinator)
        return store
    }

    @Test
    func project_noRepos_returnsFolderIntakeState() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
            )
            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.kind == .noFolders)
            #expect(result.recentCards.isEmpty)
            #expect(result.showsOpenAll == false)
        }
    }

    @Test
    func project_scanningWithoutRepos_returnsScanningState() {
        withTestAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            atoms.welcome.beginFolderScan(URL(fileURLWithPath: "/tmp/scanning-root"))

            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.kind == .scanning(URL(fileURLWithPath: "/tmp/scanning-root")))
            #expect(result.recentCards.isEmpty)
        }
    }

    @Test
    func project_emptyFolderScanWithoutRepos_returnsEmptyScanState() {
        withTestAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            atoms.welcome.completeFolderScan(
                rootPath: URL(fileURLWithPath: "/tmp/empty-root"),
                discoveredRepoCount: 0
            )

            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.kind == .scanEmpty(URL(fileURLWithPath: "/tmp/empty-root")))
            #expect(result.recentCards.isEmpty)
            #expect(result.showsOpenAll == false)
        }
    }

    @Test
    func project_emptyFolderScanWithRepos_returnsLauncherState() {
        withTestAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            _ = store.mutationCoordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            atoms.welcome.completeFolderScan(
                rootPath: URL(fileURLWithPath: "/tmp/empty-root"),
                discoveredRepoCount: 0
            )

            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.kind == .launcher)
        }
    }

    @Test
    func project_choosingFolderWithoutRepos_returnsChoosingFolderState() {
        withTestAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            atoms.welcome.beginChoosingFolder()

            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.kind == .choosingFolder)
            #expect(result.recentCards.isEmpty)
        }
    }

    @Test
    func project_scanningOutranksChoosingFolderWhenReposAreEmpty() {
        withTestAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            atoms.welcome.beginChoosingFolder()
            atoms.welcome.beginFolderScan(URL(fileURLWithPath: "/tmp/scanning-root"))

            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.kind == .scanning(URL(fileURLWithPath: "/tmp/scanning-root")))
        }
    }

    @Test
    func project_launcherWinsWhenReposExistEvenIfChoosingFolderIsTrue() {
        withTestAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            _ = store.mutationCoordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            atoms.welcome.beginChoosingFolder()

            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.kind == .launcher)
        }
    }

    @Test
    func project_reposButNoTabs_returnsLauncherStateWithEnrichedCards() {
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
            )
            let repo = store.mutationCoordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
                Issue.record("Expected main worktree")
                return
            }

            atoms.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(
                    worktreeId: worktree.id,
                    repoId: repo.id,
                    branch: "main"
                )
            )
            atoms.repoCache.setPullRequestCount(3, for: worktree.id)
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
            atoms.repoCache.recordRecentTarget(.forWorktree(path: worktree.path, worktree: worktree, repo: repo))

            let result = WorkspaceLauncherProjector.project(store: store)

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
        withTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
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
            atoms.repoCache.recordRecentTarget(.forWorktree(path: worktree.path, worktree: worktree, repo: repo))

            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.kind == .launcher)
            #expect(result.recentCards.isEmpty)
            #expect(result.showsOpenAll == false)
        }
    }

    @Test
    func project_launcherCapsAtFifteenAndShowsOpenAllForTwoOrMoreTargets() {
        withTestAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            let repo = store.mutationCoordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))
            guard let worktree = store.repos.first(where: { $0.id == repo.id })?.worktrees.first else {
                Issue.record("Expected main worktree")
                return
            }

            let cache = atoms.repoCache
            for index in 0..<20 {
                cache.recordRecentTarget(
                    .forCwd(
                        worktree.path.appending(path: "nested-\(index)"),
                        title: "nested-\(index)",
                        subtitle: repo.name
                    )
                )
            }

            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.recentCards.count == 15)
            #expect(result.showsOpenAll == true)
        }
    }

    @Test
    func project_unresolvedRecentTarget_isDroppedFromLauncherCards() {
        withTestAtomRegistry { atoms in
            let store = makeStore(atoms: atoms)
            _ = store.mutationCoordinator.addRepo(at: URL(fileURLWithPath: "/tmp/agent-studio"))

            let cache = atoms.repoCache
            cache.recordRecentTarget(.forCwd(URL(fileURLWithPath: "/tmp/missing-project")))

            let result = WorkspaceLauncherProjector.project(store: store)

            #expect(result.kind == .launcher)
            #expect(result.recentCards.isEmpty)
            #expect(result.showsOpenAll == false)
        }
    }
}
