import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct TopologyEventPipelineIntegrationTests {
    private func withTopologyHarness(
        _ body: @escaping @MainActor (GitTopologyPipelineHarness) async throws -> Void
    ) async rethrows {
        let harness = await GitTopologyPipelineHarness.make()
        do {
            try await body(harness)
            await harness.shutdown()
        } catch {
            await harness.shutdown()
            throw error
        }
    }

    private func settleTopologyHarness(_ harness: GitTopologyPipelineHarness) async {
        await Task.yield()
        await waitForBusSubscriberCount(harness.bus, atLeast: 1, maxTurns: 1000)
    }

    @Test("authoritative grouped discovery creates one canonical family and syncs roots")
    func groupedDiscoveryCreatesCanonicalFamilyAndSyncsRoots() async {
        await withTopologyHarness { harness in
            await settleTopologyHarness(harness)

            let watchedFolder = harness.tempDir.appending(path: "topology-watched-\(UUID().uuidString)")
            let clonePath = watchedFolder.appending(path: "agent-studio")
            let featurePath = watchedFolder.appending(path: "agent-studio-feature")
            let hotfixPath = watchedFolder.appending(path: "agent-studio-hotfix")
            let watchedPath = WatchedPath(path: watchedFolder)

            harness.scanResults.setResults([
                watchedPath: [
                    RepoScanner.RepoScanGroup(
                        clonePath: clonePath,
                        linkedWorktreePaths: [featurePath, hotfixPath]
                    )
                ]
            ])

            let summary = await harness.refreshWatchedFolders([watchedPath])
            let scanState = await harness.discoveryActor.watchedFolderScanState
            #expect(scanState.registrationsBySourceID.count == 1)
            #expect(scanState.latestDemandCoverageBySourceID.count == 1)
            #expect(scanState.appliedDemandCoverageBySourceID.count == 1)
            #expect(
                scanState.inventoryBySourceID.values.first?.repoGroups.map(\.clonePath)
                    == [clonePath]
            )
            #expect(summary.repoPaths(in: watchedFolder) == [clonePath])

            await assertEventuallyMain("store should converge to one repo family") {
                guard harness.workspaceStore.repos.count == 1 else { return false }
                let worktreePaths = Set(harness.workspaceStore.repos[0].worktrees.map(\.path))
                return worktreePaths == Set([clonePath, featurePath, hotfixPath])
            }

            await assertEventuallyAsync("filesystem sync should register all worktree roots") {
                let snapshot = await harness.filesystemSnapshot()
                let registeredPaths = Set(snapshot.registeredRoots.values)
                return registeredPaths == Set([clonePath, featurePath, hotfixPath])
            }
        }
    }

    @Test("authoritative removal prunes cache orphans panes and unregisters removed root")
    func authoritativeRemovalPrunesCacheOrphansPanesAndUnregistersRoot() async {
        await withTopologyHarness { harness in
            await settleTopologyHarness(harness)

            let watchedFolder = harness.tempDir.appending(path: "topology-remove-\(UUID().uuidString)")
            let clonePath = watchedFolder.appending(path: "agent-studio")
            let keepPath = watchedFolder.appending(path: "agent-studio-feature")
            let removePath = watchedFolder.appending(path: "agent-studio-hotfix")
            let watchedPath = WatchedPath(path: watchedFolder)

            harness.scanResults.setResults([
                watchedPath: [
                    RepoScanner.RepoScanGroup(
                        clonePath: clonePath,
                        linkedWorktreePaths: [keepPath, removePath]
                    )
                ]
            ])
            _ = await harness.refreshWatchedFolders([watchedPath])

            await assertEventuallyMain("initial family should exist") {
                harness.workspaceStore.repos.first?.worktrees.count == 3
            }
            await harness.workspaceSurfaceCoordinator.waitForFilesystemRootsAndActivitySyncIdle()

            guard let repo = harness.workspaceStore.repos.first,
                let removedWorktree = repo.worktrees.first(where: { $0.path == removePath })
            else {
                Issue.record("expected initial removed worktree to exist")
                return
            }

            let pane = harness.workspaceStore.createPane(
                launchDirectory: removedWorktree.path,
                facets: PaneContextFacets(
                    repoId: repo.id,
                    worktreeId: removedWorktree.id,
                    cwd: removedWorktree.path
                )
            )
            let tab = Tab(paneId: pane.id)
            harness.workspaceStore.appendTab(tab)

            harness.repoCache.setWorktreeEnrichment(
                WorktreeEnrichment(
                    worktreeId: removedWorktree.id,
                    repoId: repo.id,
                    branch: "hotfix"
                )
            )
            harness.repoCache.setPullRequestCount(4, for: removedWorktree.id)

            let baselineSnapshot = await harness.filesystemSnapshot()

            harness.scanResults.setResults([
                watchedPath: [
                    RepoScanner.RepoScanGroup(
                        clonePath: clonePath,
                        linkedWorktreePaths: [keepPath]
                    )
                ]
            ])
            _ = await harness.refreshWatchedFolders([watchedPath])

            await assertEventuallyMain("removed worktree should leave canonical store") {
                let currentPaths = Set(harness.workspaceStore.repos.first?.worktrees.map(\.path) ?? [])
                return currentPaths == Set([clonePath, keepPath])
            }

            await assertEventuallyMain("removed worktree cache should be pruned") {
                harness.repoCache.worktreeEnrichmentByWorktreeId[removedWorktree.id] == nil
                    && harness.repoCache.pullRequestCountByWorktreeId[removedWorktree.id] == nil
            }

            await assertEventuallyMain("pane should become orphaned for removed worktree") {
                guard let updatedPane = harness.workspaceStore.pane(pane.id) else { return false }
                return updatedPane.residency == .orphaned(reason: .worktreeNotFound(path: removePath.path))
            }

            await harness.workspaceSurfaceCoordinator.waitForFilesystemRootsAndActivitySyncIdle()
            let syncedSnapshot = await harness.filesystemSnapshot()
            let syncedPaths = Set(syncedSnapshot.registeredRoots.values)
            #expect(syncedPaths == Set([clonePath, keepPath]))
            #expect(syncedSnapshot.unregisterLog.contains(removedWorktree.id))
            #expect(syncedSnapshot.registerLog.count >= baselineSnapshot.registerLog.count)
        }
    }

    @Test("boot replay notScanned preserves existing family without destructive reconciliation")
    func bootReplayNotScannedPreservesExistingFamily() async {
        await withTopologyHarness { harness in
            await settleTopologyHarness(harness)

            let repoPath = URL(fileURLWithPath: "/tmp/topology-boot-\(UUID().uuidString)")
            let keepPath = URL(fileURLWithPath: "/tmp/topology-boot-feature")
            let removePath = URL(fileURLWithPath: "/tmp/topology-boot-hotfix")

            let repo = harness.workspaceStore.addRepo(at: repoPath)
            guard let mainWorktree = repo.worktrees.first else {
                Issue.record("expected main worktree")
                return
            }
            harness.workspaceStore.reconcileDiscoveredWorktrees(
                repo.id,
                worktrees: [
                    mainWorktree,
                    Worktree(repoId: repo.id, name: keepPath.lastPathComponent, path: keepPath),
                    Worktree(repoId: repo.id, name: removePath.lastPathComponent, path: removePath),
                ]
            )

            harness.workspaceSurfaceCoordinator.topologyDidChange(
                WorktreeTopologyDelta(
                    repoId: repo.id,
                    addedWorktreeIds: harness.workspaceStore.repos[0].worktrees.map(\.id),
                    removedWorktrees: [],
                    preservedWorktreeIds: [],
                    didChange: true,
                    traceId: nil
                )
            )

            await assertEventuallyAsync("initial registration should converge") {
                let snapshot = await harness.filesystemSnapshot()
                return Set(snapshot.registeredRoots.values) == Set([repoPath, keepPath, removePath])
            }

            let beforePaths = Set(harness.workspaceStore.repos[0].worktrees.map(\.path))
            let beforeSnapshot = await harness.filesystemSnapshot()

            await harness.postTopology(
                .repoDiscovered(
                    repoPath: repoPath,
                    parentPath: repoPath.deletingLastPathComponent(),
                    linkedWorktrees: .notScanned
                ),
                source: .builtin(.coordinator)
            )

            await assertEventuallyMain("boot replay should not mutate family") {
                let afterPaths = Set(harness.workspaceStore.repos[0].worktrees.map(\.path))
                return afterPaths == beforePaths
            }

            let afterSnapshot = await harness.filesystemSnapshot()
            #expect(afterSnapshot.registeredRoots == beforeSnapshot.registeredRoots)
            #expect(afterSnapshot.unregisterLog == beforeSnapshot.unregisterLog)
        }
    }

    @Test("fsevent-triggered watched-folder removal emits repoRemoved and marks repo unavailable")
    func watchedFolderFSEventRemovalEmitsRepoRemovedAndMarksRepoUnavailable() async throws {
        try await withTopologyHarness { harness in
            await settleTopologyHarness(harness)

            let subscriber = await harness.bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
            let recorder = RecordingSubscriber(stream: subscriber)

            let watchedFolder = harness.tempDir.appending(
                path: "topology-fsevent-remove-\(UUID().uuidString)"
            )
            let clonePath = watchedFolder.appending(path: "agent-studio")
            let watchedPath = WatchedPath(path: watchedFolder)
            harness.scanResults.setResults([
                watchedPath: [
                    RepoScanner.RepoScanGroup(clonePath: clonePath, linkedWorktreePaths: [])
                ]
            ])
            _ = await harness.refreshWatchedFolders([watchedPath])

            let syntheticId = try #require(harness.fseventClient.registeredWorktreeIds.first)

            harness.scanResults.setResults([watchedPath: []])
            harness.fseventClient.send(
                FSEventBatch(
                    worktreeId: syntheticId,
                    paths: ["\(clonePath.path)/.git/HEAD"]
                )
            )

            await assertEventuallyAsync("repoRemoved should be emitted after watched-folder FSEvent") {
                let envelopes = await recorder.snapshot()
                return RuntimeEnvelopeHarness.systemEvents(from: envelopes).contains {
                    if case .topology(.repoRemoved(let repoPath)) = $0.event {
                        return repoPath.standardizedFileURL == clonePath.standardizedFileURL
                    }
                    return false
                }
            }

            await assertEventuallyMain("repo should be marked unavailable after repoRemoved") {
                guard let repo = harness.workspaceStore.repos.first(where: { $0.repoPath == clonePath }) else {
                    return false
                }
                return harness.workspaceStore.isRepoUnavailable(repo.id)
            }
            await recorder.shutdown()
        }
    }

    @Test("fsevent-triggered watched-folder addition registers the new linked worktree root end-to-end")
    func watchedFolderFSEventAdditionRegistersNewLinkedWorktreeRoot() async throws {
        try await withTopologyHarness { harness in
            await settleTopologyHarness(harness)

            let watchedFolder = harness.tempDir.appending(
                path: "topology-fsevent-add-\(UUID().uuidString)"
            )
            let clonePath = watchedFolder.appending(path: "agent-studio")
            let initialLinked = watchedFolder.appending(path: "agent-studio-feature-a")
            let addedLinked = watchedFolder.appending(path: "agent-studio-feature-b")
            let watchedPath = WatchedPath(path: watchedFolder)

            harness.scanResults.setResults([
                watchedPath: [
                    RepoScanner.RepoScanGroup(
                        clonePath: clonePath,
                        linkedWorktreePaths: [initialLinked]
                    )
                ]
            ])
            _ = await harness.refreshWatchedFolders([watchedPath])

            let syntheticId = try #require(harness.fseventClient.registeredWorktreeIds.first)
            let subscriber = await harness.bus.subscribe(
                policy: .criticalUnbounded,
                subscriberName: #function
            )
            let recorder = RecordingSubscriber(stream: subscriber)

            harness.scanResults.setResults([
                watchedPath: [
                    RepoScanner.RepoScanGroup(
                        clonePath: clonePath,
                        linkedWorktreePaths: [initialLinked, addedLinked]
                    )
                ]
            ])
            harness.fseventClient.send(
                FSEventBatch(
                    worktreeId: syntheticId,
                    paths: ["\(clonePath.path)/.git/worktrees/feature-b/HEAD"]
                )
            )

            _ = await recorder.firstEvent { envelope in
                guard
                    case .system(let systemEnvelope) = envelope,
                    case .topology(
                        .reposDiscovered(let parentPath, let repositories)
                    ) = systemEnvelope.event,
                    parentPath.standardizedFileURL == watchedFolder.standardizedFileURL
                else { return false }

                return repositories.contains { repository in
                    guard
                        repository.repoPath.standardizedFileURL
                            == clonePath.standardizedFileURL,
                        case .scanned(let linkedWorktreePaths) = repository.linkedWorktrees
                    else { return false }
                    return Set(linkedWorktreePaths.map(\.standardizedFileURL))
                        == Set([
                            initialLinked.standardizedFileURL,
                            addedLinked.standardizedFileURL,
                        ])
                }
            }

            await assertEventuallyMain("new linked worktree should appear in canonical store") {
                let paths = Set(harness.workspaceStore.repos.first?.worktrees.map(\.path) ?? [])
                return paths == Set([clonePath, initialLinked, addedLinked])
            }

            await harness.workspaceSurfaceCoordinator.waitForFilesystemRootsAndActivitySyncIdle()
            await assertEventuallyAsync("new linked worktree root should be registered") {
                let snapshot = await harness.filesystemSnapshot()
                return Set(snapshot.registeredRoots.values) == Set([clonePath, initialLinked, addedLinked])
            }
            await recorder.shutdown()
        }
    }

    @Test("global remove dedup keeps repo available when another watched folder still references clone")
    func globalRemoveDedupKeepsRepoAvailableWhenAnotherFolderStillReferencesClone() async {
        await withTopologyHarness { harness in
            await settleTopologyHarness(harness)

            let subscriber = await harness.bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
            let recorder = RecordingSubscriber(stream: subscriber)

            let folderA = harness.tempDir.appending(path: "topology-dedup-a-\(UUID().uuidString)")
            let folderB = harness.tempDir.appending(path: "topology-dedup-b-\(UUID().uuidString)")
            let sharedClone = harness.tempDir.appending(
                path: "topology-shared-clone-\(UUID().uuidString)"
            )
            let watchedPaths = [WatchedPath(path: folderA), WatchedPath(path: folderB)]

            harness.scanResults.setResults([
                watchedPaths[0]: [RepoScanner.RepoScanGroup(clonePath: sharedClone, linkedWorktreePaths: [])],
                watchedPaths[1]: [RepoScanner.RepoScanGroup(clonePath: sharedClone, linkedWorktreePaths: [])],
            ])
            _ = await harness.refreshWatchedFolders(watchedPaths)
            let initialEventCount = await recorder.snapshot().count

            harness.scanResults.setResults([
                watchedPaths[0]: [],
                watchedPaths[1]: [RepoScanner.RepoScanGroup(clonePath: sharedClone, linkedWorktreePaths: [])],
            ])
            _ = await harness.refreshWatchedFolders(watchedPaths)

            for _ in 0..<50 {
                await Task.yield()
            }

            let envelopes = await recorder.snapshot()
            let newEvents = Array(envelopes.dropFirst(initialEventCount))
            let repoRemovedEvents = RuntimeEnvelopeHarness.systemEvents(from: newEvents).filter {
                if case .topology(.repoRemoved(let repoPath)) = $0.event {
                    return repoPath.standardizedFileURL == sharedClone.standardizedFileURL
                }
                return false
            }
            #expect(repoRemovedEvents.isEmpty)
            #expect(harness.workspaceStore.isRepoUnavailable(harness.workspaceStore.repos[0].id) == false)
            await recorder.shutdown()
        }
    }

    @Test("authoritative empty scan removes all linked worktrees end-to-end")
    func authoritativeEmptyScanRemovesAllLinkedWorktreesEndToEnd() async {
        await withTopologyHarness { harness in
            await settleTopologyHarness(harness)

            let watchedFolder = harness.tempDir.appending(path: "topology-empty-\(UUID().uuidString)")
            let clonePath = watchedFolder.appending(path: "agent-studio")
            let featurePath = watchedFolder.appending(path: "agent-studio-feature")
            let hotfixPath = watchedFolder.appending(path: "agent-studio-hotfix")
            let watchedPath = WatchedPath(path: watchedFolder)

            harness.scanResults.setResults([
                watchedPath: [
                    RepoScanner.RepoScanGroup(
                        clonePath: clonePath,
                        linkedWorktreePaths: [featurePath, hotfixPath]
                    )
                ]
            ])
            _ = await harness.refreshWatchedFolders([watchedPath])

            await assertEventuallyMain("initial linked family should exist") {
                guard harness.workspaceStore.repos.count == 1 else { return false }
                return Set(harness.workspaceStore.repos[0].worktrees.map(\.path))
                    == Set([clonePath, featurePath, hotfixPath])
            }

            harness.scanResults.setResults([
                watchedPath: [
                    RepoScanner.RepoScanGroup(
                        clonePath: clonePath,
                        linkedWorktreePaths: []
                    )
                ]
            ])
            _ = await harness.refreshWatchedFolders([watchedPath])

            await assertEventuallyMain("authoritative empty scan should converge to main-only") {
                harness.workspaceStore.repos.count == 1
                    && harness.workspaceStore.repos[0].worktrees.map(\.path) == [clonePath]
            }
        }
    }
}
