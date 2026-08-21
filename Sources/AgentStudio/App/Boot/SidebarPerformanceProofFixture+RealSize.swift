import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

#if DEBUG
    extension SidebarPerformanceProofFixture {
        static func populateRealSizeTopology(
            store: WorkspaceStore,
            repositoryRoot: URL
        ) {
            store.mutationCoordinator.performBatchedTopologyMutation {
                while store.repositoryTopologyAtom.repositoryIdsInOrder.count
                    < AppPolicies.SidebarPerformanceProof.repositoryCount
                {
                    let index = store.repositoryTopologyAtom.repositoryIdsInOrder.count
                    let path = repositoryRoot.appendingPathComponent(
                        "agentstudio-sidebar-load-repo-\(index)",
                        isDirectory: true
                    )
                    _ = store.mutationCoordinator.addRepo(
                        at: path,
                        stableKey: "sidebar-performance-repository-\(index)"
                    )
                }

                var nextRepositoryIndex = 0
                while store.repositoryTopologyAtom.worktreeIdsInOrder.count
                    < AppPolicies.SidebarPerformanceProof.worktreeCount
                {
                    let repositories = store.repositoryTopologyAtom.repos
                    let repository = repositories[nextRepositoryIndex % repositories.count]
                    nextRepositoryIndex += 1
                    guard
                        let mainWorktree = repository.worktrees.first(where: \.isMainWorktree),
                        let mainStableKey = store.repositoryTopologyAtom.worktreeStableKey(for: mainWorktree.id)
                    else { continue }

                    let linkedIndex = repository.worktrees.count
                    let linkedPath = repository.repoPath.appendingPathComponent(
                        "linked-\(linkedIndex)",
                        isDirectory: true
                    )
                    let existingLinked = repository.worktrees
                        .filter { !$0.isMainWorktree }
                        .compactMap { worktree -> RepositoryScannedLinkedWorktree? in
                            guard
                                let stableKey = store.repositoryTopologyAtom.worktreeStableKey(
                                    for: worktree.id
                                )
                            else { return nil }
                            return RepositoryScannedLinkedWorktree(
                                name: worktree.name,
                                path: worktree.path,
                                stableKey: stableKey
                            )
                        }
                    _ = store.mutationCoordinator.reconcileScannedWorktrees(
                        repository.id,
                        scannedWorktrees: RepositoryScannedWorktrees(
                            main: RepositoryScannedMainWorktree(
                                name: mainWorktree.name,
                                path: mainWorktree.path,
                                stableKey: mainStableKey
                            ),
                            linked: existingLinked + [
                                RepositoryScannedLinkedWorktree(
                                    name: linkedPath.lastPathComponent,
                                    path: linkedPath,
                                    stableKey: "sidebar-performance-worktree-\(repository.id.uuidString)-\(linkedIndex)"
                                )
                            ]
                        ),
                        traceId: UUIDv7.generate()
                    )
                }
            }
        }

        static func populateRealSizePaneFleet(store: WorkspaceStore) {
            while store.tabLayoutAtom.tabs.count < AppPolicies.SidebarPerformanceProof.tabCount {
                let remainingPaneCount =
                    AppPolicies.SidebarPerformanceProof.paneCount
                    - store.paneAtom.graphAtom.paneIDs.count
                let remainingTabCount =
                    AppPolicies.SidebarPerformanceProof.tabCount
                    - store.tabLayoutAtom.tabs.count
                let paneCountForTab = max(
                    1,
                    Int(ceil(Double(remainingPaneCount) / Double(remainingTabCount)))
                )
                let firstPane = store.paneAtom.createPane(
                    title: "Load Pane",
                    lifetime: .temporary,
                    zmxSessionID: .generateUUIDv7()
                )
                store.tabLayoutAtom.appendTab(Tab(paneId: firstPane.id, name: "Load Tab"))
                guard let tabId = store.tabLayoutAtom.tabs.last?.id else { return }
                for _ in 1..<paneCountForTab {
                    let pane = store.paneAtom.createPane(
                        title: "Load Pane",
                        lifetime: .temporary,
                        zmxSessionID: .generateUUIDv7()
                    )
                    _ = store.tabLayoutAtom.insertPane(
                        pane.id,
                        inTab: tabId,
                        at: firstPane.id,
                        direction: .horizontal,
                        position: .after,
                        sizingMode: .halveTarget
                    )
                }
            }
        }
    }
#endif
