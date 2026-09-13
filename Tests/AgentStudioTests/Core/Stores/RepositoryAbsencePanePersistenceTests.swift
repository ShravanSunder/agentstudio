import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("Repository absence pane persistence")
struct RepositoryAbsencePanePersistenceTests {
    @Test("unavailability clears every workspace's optional facets and rejects stale facet re-entry")
    func unavailabilityClearsInactiveWorkspacesAndStaleSnapshots() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let path = URL(fileURLWithPath: "/tmp/persisted-unavailable-repository")
        var topology = WorkspaceCoreRepository.RepositoryTopologyRecord(
            watchedPaths: [],
            repos: [
                .init(
                    id: repositoryID, name: "repository", repoPath: path, createdAt: Date(timeIntervalSince1970: 100),
                    worktrees: [
                        .init(id: worktreeID, repoId: repositoryID, name: "main", path: path, isMainWorktree: true)
                    ]
                )
            ],
            unavailableRepoIds: []
        )
        try repository.replaceRepositoryTopology(topology)
        let workspaceIDs = [UUIDv7.generate(), UUIDv7.generate()]
        var originalGraphs: [UUID: WorkspaceCoreRepository.PaneGraphRecord] = [:]
        var tabIDs: [UUID: UUID] = [:]
        for workspaceID in workspaceIDs {
            try repository.upsertWorkspace(
                .init(
                    id: workspaceID, name: "workspace", createdAt: Date(timeIntervalSince1970: 100),
                    updatedAt: Date(timeIntervalSince1970: 100)
                ))
            let paneID = UUIDv7.generate()
            let tabID = UUIDv7.generate()
            try fixture.insertPane(workspaceId: workspaceID, paneId: paneID, cwd: path)
            try fixture.insertTabShell(workspaceId: workspaceID, tabId: tabID)
            try fixture.insertTabPane(tabId: tabID, paneId: paneID)
            var graph = try repository.fetchPaneGraph(workspaceId: workspaceID)
            graph.panes[0].metadata.durableFacets.repoId = repositoryID
            graph.panes[0].metadata.durableFacets.worktreeId = worktreeID
            try repository.replacePaneGraph(workspaceId: workspaceID, graph: graph)
            originalGraphs[workspaceID] = graph
            tabIDs[workspaceID] = tabID
        }

        topology.absenceRecords = .init(
            repositories: [repositoryID: .unconfirmed], worktrees: [worktreeID: .unconfirmed])
        try repository.replaceRepositoryTopology(topology)

        for workspaceID in workspaceIDs {
            let original = try #require(originalGraphs[workspaceID])
            var expected = original
            expected.panes[0].metadata.durableFacets.repoId = nil
            expected.panes[0].metadata.durableFacets.worktreeId = nil
            #expect(try repository.fetchPaneGraph(workspaceId: workspaceID) == expected)
            // A previously captured workspace snapshot must not restore unavailable context.
            try repository.replacePaneGraph(workspaceId: workspaceID, graph: original)
            #expect(try repository.fetchPaneGraph(workspaceId: workspaceID) == expected)
            let tabID = try #require(tabIDs[workspaceID])
            #expect(try fixture.fetchTabPaneCount(tabId: tabID, paneId: original.panes[0].id) == 1)
        }
        #expect(try fixture.fetchPaneContentRouteCounts().terminal == 2)
        #expect(try repository.fetchRepositoryTopology().repos == topology.repos)
    }
}
