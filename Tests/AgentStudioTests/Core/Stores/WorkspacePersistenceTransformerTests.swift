import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace persistence transformer")
struct WorkspacePersistenceTransformerTests {
    @Test("topology bridge preserves repository and worktree metadata")
    func topologyBridgePreservesMetadata() throws {
        // Arrange
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let topologyAtom = RepositoryTopologyAtom()
        let snapshot = RepositoryTopologySQLiteSnapshot(
            repos: [
                CanonicalRepo(
                    id: repositoryID,
                    name: "agent-studio",
                    repoPath: URL(filePath: "/tmp/agent-studio-metadata"),
                    isFavorite: true,
                    note: "repository note",
                    tags: ["client"]
                )
            ],
            worktrees: [
                CanonicalWorktree(
                    id: worktreeID,
                    repoId: repositoryID,
                    name: "main",
                    path: URL(filePath: "/tmp/agent-studio-metadata"),
                    isMainWorktree: true,
                    note: "worktree note"
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        // Act
        WorkspacePersistenceTransformer.hydrateRepositoryTopology(
            snapshot,
            repositoryTopologyAtom: topologyAtom
        )

        // Assert
        #expect(topologyAtom.repo(repositoryID)?.isFavorite == true)
        #expect(topologyAtom.repo(repositoryID)?.note == "repository note")
        #expect(topologyAtom.repo(repositoryID)?.tags == ["client"])
        #expect(topologyAtom.worktree(worktreeID)?.note == "worktree note")
    }

    @Test("composition conversion excludes repository topology")
    func compositionConversionExcludesRepositoryTopology() {
        // Arrange
        let pane = Pane(
            id: UUIDv7.generate(),
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )),
            metadata: PaneMetadata(title: "Exact")
        )
        let tab = Tab(paneId: pane.id, name: "Exact tab")
        let snapshot = WorkspaceSQLiteSnapshot(
            id: UUIDv7.generate(),
            name: "Exact workspace",
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 321,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        // Act
        let bundle = WorkspaceSQLiteSaveBundle(workspace: snapshot)

        // Assert
        #expect(bundle.workspace == snapshot)
    }
}
