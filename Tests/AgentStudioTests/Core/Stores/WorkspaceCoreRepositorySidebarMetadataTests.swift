import Foundation
import Testing

@testable import AgentStudio

@Suite("WorkspaceCoreRepositorySidebarMetadataTests")
struct WorkspaceCoreRepositorySidebarMetadataTests {
    @Test("repo sidebar metadata round trips through repository APIs")
    func repoSidebarMetadataRoundTripsThroughRepositoryAPIs() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000008001")!
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000008101")!
        let worktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000008201")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000008301")!

        try upsertWorkspace(repository, workspaceId: workspaceId, name: "Sidebar metadata")
        try repository.replaceRepositoryTopology(
            .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: repoId,
                        name: "agent-studio",
                        repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
                        createdAt: Date(timeIntervalSince1970: 1),
                        worktrees: [
                            .init(
                                id: worktreeId,
                                repoId: repoId,
                                name: "main",
                                path: URL(fileURLWithPath: "/tmp/agent-studio"),
                                isMainWorktree: true
                            )
                        ]
                    )
                ],
                unavailableRepoIds: []
            )
        )
        try fixture.insertTabShell(workspaceId: workspaceId, tabId: tabId)

        try repository.updateRepoFavorite(repoId: repoId, isFavorite: true)
        try repository.updateRepoNote(repoId: repoId, note: "  repo note  ")
        try repository.updateWorktreeNote(worktreeId: worktreeId, note: " worktree note ")
        try repository.updateTabColorHex(workspaceId: workspaceId, tabId: tabId, colorHex: " #58C4FF ")
        try repository.replaceRepoTags(repoId: repoId, tags: [" client ", "", "favorite"])

        let topology = try repository.fetchRepositoryTopology()
        let shells = try repository.fetchTabShells(workspaceId: workspaceId)
        let tags = try repository.fetchRepoTags(repoId: repoId)

        #expect(topology.repos.first?.isFavorite == true)
        #expect(topology.repos.first?.note == "repo note")
        #expect(topology.repos.first?.worktrees.first?.note == "worktree note")
        #expect(shells.first?.colorHex == "#58C4FF")
        #expect(tags == ["client", "favorite"])
    }

    @Test("repo sidebar metadata survives topology and tab shell replacement")
    func repoSidebarMetadataSurvivesTopologyAndTabShellReplacement() throws {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        let repository = fixture.repository
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000008002")!
        let repoId = UUID(uuidString: "00000000-0000-0000-0000-000000008102")!
        let worktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000008202")!
        let tabId = UUID(uuidString: "00000000-0000-0000-0000-000000008302")!

        try upsertWorkspace(repository, workspaceId: workspaceId, name: "Sidebar metadata")
        let topology = WorkspaceCoreRepository.RepositoryTopologyRecord(
            watchedPaths: [],
            repos: [
                .init(
                    id: repoId,
                    name: "agent-studio",
                    repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
                    createdAt: Date(timeIntervalSince1970: 1),
                    isFavorite: true,
                    note: "repo note",
                    worktrees: [
                        .init(
                            id: worktreeId,
                            repoId: repoId,
                            name: "main",
                            path: URL(fileURLWithPath: "/tmp/agent-studio"),
                            isMainWorktree: true,
                            note: "worktree note"
                        )
                    ]
                )
            ],
            unavailableRepoIds: []
        )

        try repository.replaceRepositoryTopology(topology)
        try fixture.insertTabShell(workspaceId: workspaceId, tabId: tabId)
        try repository.updateTabColorHex(workspaceId: workspaceId, tabId: tabId, colorHex: "#58C4FF")

        try repository.replaceRepositoryTopology(topology)
        try repository.replaceTabShells(
            workspaceId: workspaceId,
            shells: [
                .init(id: tabId, name: "Renamed", colorHex: "#58C4FF")
            ])

        let restoredTopology = try repository.fetchRepositoryTopology()
        let restoredShells = try repository.fetchTabShells(workspaceId: workspaceId)

        #expect(restoredTopology.repos.first?.isFavorite == true)
        #expect(restoredTopology.repos.first?.note == "repo note")
        #expect(restoredTopology.repos.first?.worktrees.first?.note == "worktree note")
        #expect(restoredShells.first == .init(id: tabId, name: "Renamed", colorHex: "#58C4FF"))
    }

    private func upsertWorkspace(
        _ repository: WorkspaceCoreRepository,
        workspaceId: UUID,
        name: String
    ) throws {
        try repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: name,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        )
    }
}
