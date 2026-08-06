import Foundation
import Testing

@testable import AgentStudioCore

@Suite("WorkspaceCoreRepository pane CWD persistence")
struct WorkspaceCoreRepositoryPaneSourceLatchTests {
    @Test("pane CWD remains saveable after its topology is removed")
    func paneCWDRemainsSaveableAfterTopologyRemoval() throws {
        // Arrange
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
        let paneID = UUID(uuidString: "00000000-0000-0000-0000-00000000A301")!
        let cwd = URL(
            filePath: "/tmp/agentstudio/latch-repo/Sources",
            directoryHint: .isDirectory
        )
        try fixture.repository.upsertWorkspace(
            .init(
                id: workspaceID,
                name: "CWD only",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try fixture.repository.replaceRepositoryTopology(
            .init(watchedPaths: [], repos: [], unavailableRepoIds: [])
        )
        let graph = WorkspaceCoreRepository.PaneGraphRecord(
            panes: [
                .init(
                    id: paneID,
                    content: .terminal(
                        provider: .zmx,
                        lifetime: .persistent,
                        zmxSessionID: .generateUUIDv7()
                    ),
                    metadata: .init(
                        launchDirectory: cwd,
                        executionBackend: .local,
                        createdAt: Date(timeIntervalSince1970: 300),
                        title: "Terminal",
                        durableFacets: .init(cwd: cwd)
                    ),
                    residency: .active,
                    placement: .layout,
                    drawer: nil,
                    updatedAt: Date(timeIntervalSince1970: 400)
                )
            ]
        )

        // Act
        try fixture.repository.replacePaneGraph(workspaceId: workspaceID, graph: graph)

        // Assert
        #expect(try fixture.repository.fetchPaneGraph(workspaceId: workspaceID) == graph)
    }
}
