import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace persistence transformer")
struct WorkspacePersistenceTransformerTests {
    @Test("topology bridge preserves repository and worktree tags")
    func topologyBridgePreservesTags() throws {
        // Arrange
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let topologyAtom = RepositoryTopologyAtom()
        let snapshot = RepositoryTopologySQLiteSnapshot(
            id: UUIDv7.generate(),
            repos: [
                CanonicalRepo(
                    id: repositoryID,
                    name: "agent-studio",
                    repoPath: URL(filePath: "/tmp/agent-studio-tags"),
                    tags: ["client"]
                )
            ],
            worktrees: [
                CanonicalWorktree(
                    id: worktreeID,
                    repoId: repositoryID,
                    name: "main",
                    path: URL(filePath: "/tmp/agent-studio-tags"),
                    isMainWorktree: true,
                    tags: ["wip"]
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
        #expect(topologyAtom.repo(repositoryID)?.tags == ["client"])
        #expect(topologyAtom.worktree(worktreeID)?.tags == ["wip"])
    }

    @Test("SQLite DTO conversion preserves canonical values exactly")
    func sqliteDTOConversionPreservesCanonicalValuesExactly() {
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
        let state = WorkspacePersistor.PersistableState(
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
        let bundle = WorkspacePersistenceTransformer.sqliteSaveBundle(from: state)
        let roundTrip = WorkspacePersistenceTransformer.persistableState(from: bundle)

        // Assert
        #expect(roundTrip.schemaVersion == state.schemaVersion)
        #expect(roundTrip.id == state.id)
        #expect(roundTrip.name == state.name)
        #expect(roundTrip.repos == state.repos)
        #expect(roundTrip.worktrees == state.worktrees)
        #expect(roundTrip.unavailableRepoIds == state.unavailableRepoIds)
        #expect(roundTrip.panes == state.panes)
        #expect(roundTrip.tabs == state.tabs)
        #expect(roundTrip.activeTabId == state.activeTabId)
        #expect(roundTrip.sidebarWidth == state.sidebarWidth)
        #expect(roundTrip.windowFrame == state.windowFrame)
        #expect(roundTrip.watchedPaths == state.watchedPaths)
        #expect(roundTrip.createdAt == state.createdAt)
        #expect(roundTrip.updatedAt == state.updatedAt)
    }
}
