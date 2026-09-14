import CoreServices
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

extension TopologyEventPipelineIntegrationTests {
    enum DirectoryTopologyEvent: CaseIterable, Sendable {
        case renamed
        case removed

        var flags: UInt32 {
            UInt32(kFSEventStreamEventFlagItemIsDir)
                | (self == .renamed
                    ? UInt32(kFSEventStreamEventFlagItemRenamed)
                    : UInt32(kFSEventStreamEventFlagItemRemoved))
        }
    }

    @Test(
        "directory rename or removal without a Git-marker path schedules authoritative reconciliation",
        arguments: DirectoryTopologyEvent.allCases)
    func directoryStructureEventReconcilesMissingRepository(_ event: DirectoryTopologyEvent) async throws {
        try await withTopologyHarness { harness in
            let root = harness.tempDir.appending(path: "directory-topology")
            let watched = WatchedPath(path: root)
            let repositoryPath = root.appending(path: "repository")
            harness.scanResults.setResults([watched: [.init(clonePath: repositoryPath, linkedWorktreePaths: [])]])
            _ = await harness.refreshWatchedFolders([watched])
            await assertEventuallyMain("initial repository is available") {
                harness.workspaceStore.repositoryTopologyAtom.repoAndWorktree(containing: repositoryPath) != nil
            }
            let repository = try #require(harness.workspaceStore.repos.first)
            let sourceID = try #require(harness.fseventClient.registeredWorktreeIds.first)
            harness.scanResults.setResults([watched: []])

            harness.fseventClient.send(
                FSEventBatch(
                    worktreeId: sourceID, paths: [repositoryPath.path],
                    observations: [.init(path: repositoryPath.path, eventID: 42, flags: event.flags)]))

            await assertEventuallyMain("directory topology event must trigger a scan and hide the absent repository") {
                harness.workspaceStore.repositoryTopologyAtom.isRepoUnavailable(repository.id)
            }
            #expect(harness.workspaceStore.repositoryTopologyAtom.absenceRecords.repositories[repository.id] != nil)
        }
    }
}
