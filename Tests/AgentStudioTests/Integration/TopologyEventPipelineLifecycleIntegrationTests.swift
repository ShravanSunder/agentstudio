import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

extension TopologyEventPipelineIntegrationTests {
    @Test("partial discovery preserves retained hidden checkouts and their absence dates")
    func partialDiscoveryPreservesHiddenCheckoutRetention() async throws {
        try await withTopologyHarness { harness in
            let root = harness.tempDir.appending(path: "partial-retention")
            let watched = WatchedPath(path: root)
            let mainPath = root.appending(path: "main")
            let keptPath = root.appending(path: "kept")
            let hiddenPath = root.appending(path: "hidden")
            let addedPath = root.appending(path: "added")
            harness.scanResults.setResults([
                watched: [
                    .init(
                        clonePath: mainPath, linkedWorktreePaths: [keptPath, hiddenPath]
                    )
                ]
            ])
            _ = await harness.refreshWatchedFolders([watched])
            await assertEventuallyMain("initial checkouts should be registered") {
                harness.workspaceStore.repos.first?.worktrees.count == 3
            }
            let topology = harness.workspaceStore.repositoryTopologyAtom
            let hidden = try #require(topology.repos.first?.worktrees.first { $0.path == hiddenPath })
            harness.scanResults.setResults([watched: [.init(clonePath: mainPath, linkedWorktreePaths: [keptPath])]])
            _ = await harness.refreshWatchedFolders([watched])
            await assertEventuallyMain("removed checkout should be retained as unavailable") {
                topology.isWorktreeUnavailable(hidden.id)
            }
            let originalAbsence = try #require(topology.absenceRecords.worktrees[hidden.id])

            harness.scanResults.setResults(
                [watched: [.init(clonePath: mainPath, linkedWorktreePaths: [addedPath])]], partial: true)
            _ = await harness.refreshWatchedFolders([watched])
            await assertEventuallyMain("positive checkout should be admitted from the partial scan") {
                topology.repos.first?.worktrees.contains { $0.path == addedPath } == true
            }

            #expect(topology.worktree(hidden.id) != nil)
            #expect(topology.absenceRecords.worktrees[hidden.id] == originalAbsence)
            #expect(topology.repoAndWorktree(containing: keptPath) != nil)
            #expect(topology.repoAndWorktree(containing: addedPath) != nil)
        }
    }

    @Test("a complete scan receipt superseded before publication cannot hide a repository")
    func supersededScanReceiptCannotHideRepository() async throws {
        try await withTopologyHarness { harness in
            await harness.coordinator.shutdown()
            let recorder = RecordingSubscriber(
                stream: await harness.bus.subscribe(
                    policy: .criticalUnbounded, subscriberName: #function
                ))
            let root = harness.tempDir.appending(path: "superseded-receipt")
            let watched = WatchedPath(path: root)
            let repo = harness.workspaceStore.addRepo(at: root.appending(path: "repository"))
            harness.scanResults.setResults([watched: []])
            _ = await harness.refreshWatchedFolders([watched])
            await assertEventuallyAsync("old complete receipt should be recorded") {
                await recorder.snapshot().contains { envelope in
                    if case .system(let system) = envelope,
                        case .topology(.watchedFolderReconciled) = system.event
                    {
                        return true
                    }
                    return false
                }
            }
            let original = await recorder.snapshot().compactMap { envelope -> WatchedFolderTopologyObservation? in
                guard case .system(let system) = envelope,
                    case .topology(.watchedFolderReconciled(let observation)) = system.event
                else { return nil }
                return observation
            }.first
            let oldReceipt = try #require(original)
            harness.scanResults.setResults([watched: [.init(clonePath: repo.repoPath, linkedWorktreePaths: [])]])
            _ = await harness.refreshWatchedFolders([watched])

            await harness.coordinator.consumeWatchedFolderObservation(oldReceipt, sequence: 10)

            #expect(!harness.workspaceStore.isRepoUnavailable(repo.id))
            #expect(harness.workspaceStore.repositoryTopologyAtom.absenceRecords.repositories[repo.id] == nil)
            await recorder.shutdown()
        }
    }

    @Test("authoritative scans through a watched symlink cover canonical repository paths")
    func watchedAliasCoversCanonicalRepositoryPaths() async throws {
        try await withTopologyHarness { harness in
            let realRoot = harness.tempDir.appending(path: "real-watch")
            let aliasRoot = harness.tempDir.appending(path: "alias-watch")
            try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: aliasRoot, withDestinationURL: realRoot)
            let repoPath = realRoot.resolvingSymlinksInPath().appending(path: "repository")
            let repo = harness.workspaceStore.addRepo(at: repoPath)
            let watched = WatchedPath(path: aliasRoot)
            harness.scanResults.setResults([watched: []])

            _ = await harness.refreshWatchedFolders([watched])

            await assertEventuallyMain("canonical child of the watched alias should be hidden after confirmed absence")
            {
                harness.workspaceStore.isRepoUnavailable(repo.id)
            }
        }
    }

}
