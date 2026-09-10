import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

#if DEBUG
    struct SidebarPerformanceProofHistoricalActivitySeed: Equatable, Sendable {
        let repositoryIDs: [UUID]
        let commit: RepositoryLocalActivityCommit
    }

    extension SidebarPerformanceProofFixture {
        static var strictWatchedRootURLs: [URL] {
            AppPolicies.SidebarPerformanceProof.strictWatchedRootURLs.map(\.standardizedFileURL)
        }

        static func registerStrictWatchedRoots(
            store: WorkspaceStore,
            controlRootURL: URL
        ) -> [WatchedPath]? {
            let rootURLs = strictWatchedRootURLs
            let registrationRootURLs = rootURLs + [controlRootURL]
            guard rootURLs.count == 2,
                Set(registrationRootURLs.map(\.standardizedFileURL)).count
                    == registrationRootURLs.count,
                registrationRootURLs.allSatisfy({
                    var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory)
                        && isDirectory.boolValue
                })
            else { return nil }

            let watchedPaths = registrationRootURLs.compactMap { rootURL in
                store.mutationCoordinator.addWatchedPath(rootURL)
            }
            guard watchedPaths.count == registrationRootURLs.count else { return nil }
            return watchedPaths
        }

        @discardableResult
        static func populateStrictPaneFleet(
            store: WorkspaceStore,
            viewRegistry: ViewRegistry,
            placeholderFileURL: URL
        ) -> Bool {
            let requiredTabCount = AppPolicies.SidebarPerformanceProof.strictTabCount
            let requiredPaneCount = AppPolicies.SidebarPerformanceProof.strictPaneModelCount
            guard store.tabLayoutAtom.tabs.count <= requiredTabCount,
                store.paneAtom.graphAtom.paneIDs.count <= requiredPaneCount
            else { return false }

            while store.tabLayoutAtom.tabs.count < requiredTabCount {
                guard let pane = makeStrictNonterminalPane(store: store, fileURL: placeholderFileURL)
                else { return false }
                viewRegistry.ensureSlot(for: pane.id)
                store.tabLayoutAtom.appendTab(Tab(paneId: pane.id, name: "Load Tab"))
            }

            var nextTabIndex = 0
            while store.paneAtom.graphAtom.paneIDs.count < requiredPaneCount {
                let tabs = store.tabLayoutAtom.tabs
                guard !tabs.isEmpty else { return false }
                let tab = tabs[nextTabIndex % tabs.count]
                nextTabIndex += 1
                guard let targetPaneID = tab.activePaneIds.first else { return false }
                guard let pane = makeStrictNonterminalPane(store: store, fileURL: placeholderFileURL)
                else { return false }
                viewRegistry.ensureSlot(for: pane.id)
                guard
                    store.tabLayoutAtom.insertPane(
                        pane.id,
                        inTab: tab.id,
                        at: targetPaneID,
                        direction: .horizontal,
                        position: .after,
                        sizingMode: .halveTarget
                    )
                else { return false }
            }

            return store.tabLayoutAtom.tabs.count == requiredTabCount
                && store.paneAtom.graphAtom.paneIDs.count == requiredPaneCount
        }

        private static func makeStrictNonterminalPane(
            store: WorkspaceStore,
            fileURL: URL
        ) -> Pane? {
            store.paneAtom.createPane(
                content: .codeViewer(
                    CodeViewerState(filePath: fileURL, scrollToLine: nil)
                ),
                metadata: PaneMetadata(contentType: .codeViewer, title: "Load Pane")
            )
        }

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

        @concurrent nonisolated static func makeHistoricalInactiveActivitySeed(
            classificationInput: RepositoryActivityClassificationInput,
            repositoryPathsByID: [UUID: URL],
            watchedRootSummary: WatchedFolderRefreshSummary,
            rootURLs: [URL]
        ) async -> SidebarPerformanceProofHistoricalActivitySeed? {
            let activity = RepositoryActivityClassifier.classify(classificationInput)
            let eligibleRepositoryPaths = Set(
                rootURLs.flatMap { watchedRootSummary.repoPaths(in: $0).map(\.standardizedFileURL) }
            )
            let eligibleUnknownRepositories = classificationInput.repositories
                .filter { repository in
                    repositoryPathsByID[repository.repositoryID].map(\.standardizedFileURL)
                        .map(eligibleRepositoryPaths.contains) == true
                        && activity.unknownRepositoryIDs.contains(repository.repositoryID)
                        && Set(repository.worktreeStableKeysByID.keys)
                            .isDisjoint(with: classificationInput.openWorktreeIDs)
                        && classificationInput.repositoryLocalActivityByStableKey[
                            repository.repositoryStableKey
                        ]?.lastQualifyingActivityAt == nil
                }
                .sorted { $0.repositoryStableKey < $1.repositoryStableKey }
            guard eligibleUnknownRepositories.count >= 2 else { return nil }

            let seededRepositoryCount = max(1, eligibleUnknownRepositories.count / 2)
            let seededRepositories = Array(
                eligibleUnknownRepositories.prefix(
                    min(seededRepositoryCount, eligibleUnknownRepositories.count - 1)
                )
            )
            // This is prepared fixture history. It establishes representative
            // continuous negative coverage; it does not claim the live process
            // actually observed sixty days elapse.
            let historicalCoverageStartedAt = classificationInput.referenceDate.addingTimeInterval(
                -classificationInput.inactivityHorizon - 1
            )
            guard
                let commit = try? RepositoryLocalActivityCommit(
                    repositoryUpdates: seededRepositories.map { repository in
                        RepositoryLocalActivityUpdate(
                            repositoryStableKey: repository.repositoryStableKey,
                            coverageChange: .restart(at: historicalCoverageStartedAt)
                        )
                    },
                    updatedAt: classificationInput.referenceDate
                )
            else { return nil }
            return SidebarPerformanceProofHistoricalActivitySeed(
                repositoryIDs: seededRepositories.map(\.repositoryID),
                commit: commit
            )
        }

        @MainActor
        static func captureRepositoryActivityInput(
            store: WorkspaceStore,
            repositoryLocalActivity: RepositoryLocalActivityAtom,
            referenceDate: Date
        ) -> RepositoryActivityClassificationInput {
            let topology = store.repositoryTopologyAtom
            let paneGraph = store.paneAtom.graphAtom
            let associationsByPaneID = Dictionary(
                uniqueKeysWithValues: paneGraph.repositoryAssociationPaneIds.compactMap { paneID in
                    paneGraph.repositoryAssociation(for: paneID).map { (paneID, $0) }
                }
            )
            let openWorktreeIDs = paneGraph.activeRepositoryAssociationWorktreeIDs(
                in: associationsByPaneID
            )
            let repositories = topology.repositoryIdsInOrder.compactMap { repositoryID in
                topology.repo(repositoryID).map { repository in
                    RepositoryActivityTopology(
                        repositoryID: repositoryID,
                        repositoryStableKey: repository.stableKey,
                        worktreeStableKeysByID: Dictionary(
                            uniqueKeysWithValues: repository.worktrees.map {
                                ($0.id, $0.stableKey)
                            }
                        )
                    )
                }
            }
            let repositoryLocalActivityByStableKey = Dictionary(
                uniqueKeysWithValues: repositories.compactMap { repository in
                    repositoryLocalActivity.activity(for: repository.repositoryStableKey).map {
                        (repository.repositoryStableKey, $0)
                    }
                }
            )
            return RepositoryActivityClassificationInput(
                repositories: repositories,
                openWorktreeIDs: openWorktreeIDs,
                localActivityHydrationDisposition: repositoryLocalActivity.hydrationDisposition,
                repositoryLocalActivityByStableKey: repositoryLocalActivityByStableKey,
                referenceDate: referenceDate,
                inactivityHorizon: AppPolicies.EntityRecency.applicationActivityHorizon
            )
        }
    }
#endif
