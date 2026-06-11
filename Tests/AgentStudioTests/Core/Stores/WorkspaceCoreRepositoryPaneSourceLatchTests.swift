import Foundation
import GRDB
import Testing

@testable import AgentStudio

/// Characterizes the workspace save latch (2026-06-11 debug investigation):
/// save-time pane-graph validation rejects pane states the live runtime model
/// legally produces. Each test documents CURRENT behavior; T5 of the
/// zmx-session-anchor plan flips these to assert the save succeeds.
@Suite("WorkspaceCoreRepositoryPaneSourceLatchTests")
struct WorkspaceCoreRepositoryPaneSourceLatchTests {
    private let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
    private let repoId = UUID(uuidString: "00000000-0000-0000-0000-00000000A101")!
    private let worktreeAId = UUID(uuidString: "00000000-0000-0000-0000-00000000A201")!
    private let worktreeBId = UUID(uuidString: "00000000-0000-0000-0000-00000000A202")!
    private let paneId = UUID(uuidString: "00000000-0000-0000-0000-00000000A301")!

    private func makeFixtureWithTopology(
        worktreeIds: [UUID]
    ) throws -> WorkspaceCoreTopologyRepositoryFixture {
        let fixture = try makeWorkspaceCoreRepositoryFixture()
        try fixture.repository.upsertWorkspace(
            .init(
                id: workspaceId,
                name: "Latch",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try fixture.repository.replaceRepositoryTopology(
            workspaceId: workspaceId,
            topology: .init(
                watchedPaths: [],
                repos: [
                    .init(
                        id: repoId,
                        name: "repo",
                        repoPath: URL(fileURLWithPath: "/tmp/agentstudio/latch-repo"),
                        createdAt: Date(timeIntervalSince1970: 200),
                        worktrees: worktreeIds.enumerated().map { index, worktreeId in
                            .init(
                                id: worktreeId,
                                repoId: repoId,
                                name: index == 0 ? "main" : "wt-\(index)",
                                path: URL(fileURLWithPath: "/tmp/agentstudio/latch-repo-\(index)"),
                                isMainWorktree: index == 0
                            )
                        }
                    )
                ],
                unavailableRepoIds: []
            )
        )
        return fixture
    }

    private func makeWorktreeSourcedPane(
        sourceWorktreeId: UUID,
        facetWorktreeId: UUID?,
        residency: WorkspaceCoreRepository.PaneResidencyRecord
    ) -> WorkspaceCoreRepository.PaneRecord {
        .init(
            id: paneId,
            content: .terminal(provider: .zmx, lifetime: .persistent),
            metadata: .init(
                source: .worktree(
                    repoId: repoId,
                    worktreeId: sourceWorktreeId,
                    launchDirectory: URL(fileURLWithPath: "/tmp/agentstudio/latch-repo-0")
                ),
                executionBackend: .local,
                createdAt: Date(timeIntervalSince1970: 300),
                title: "Terminal",
                durableFacets: .init(
                    repoId: facetWorktreeId == nil ? nil : repoId,
                    worktreeId: facetWorktreeId,
                    cwd: URL(fileURLWithPath: "/tmp/agentstudio/latch-repo-0")
                )
            ),
            residency: residency,
            placement: .layout,
            drawer: nil,
            updatedAt: Date(timeIntervalSince1970: 400)
        )
    }

    @Test("orphaned pane whose source worktree left the topology poisons the save")
    func orphanedPaneWithRemovedSourceWorktreePoisonsSave() throws {
        // Arrange — topology only contains worktree A; pane was born in
        // worktree B (since removed) and was correctly orphaned by the
        // runtime, which keeps `source` for later restoration.
        let fixture = try makeFixtureWithTopology(worktreeIds: [worktreeAId])
        let graph = WorkspaceCoreRepository.PaneGraphRecord(
            panes: [
                makeWorktreeSourcedPane(
                    sourceWorktreeId: worktreeBId,
                    facetWorktreeId: nil,
                    residency: .orphaned(worktreePath: "/tmp/agentstudio/latch-repo-removed")
                )
            ]
        )

        // Act & Assert — CURRENT behavior: every save attempt throws, and
        // because the in-memory state never changes, the workspace can never
        // be saved again until app restart ("Workspace save failed" storm).
        #expect(throws: WorkspaceCoreRepositoryError.worktreeNotFoundInWorkspace(worktreeBId, workspaceId)) {
            try fixture.repository.replacePaneGraph(workspaceId: workspaceId, graph: graph)
        }
    }

    @Test("roamed pane with live facet pointing at another worktree poisons the save")
    func roamedPaneWithFacetWorktreeMismatchPoisonsSave() throws {
        // Arrange — both worktrees exist. Pane was born in A; the user cd'd
        // its terminal into B, so the live facet rewrite
        // (WorkspacePaneGraphAtom.updatePaneCWDAndResolvedContext) moved
        // facets.worktreeId to B while frozen `source` still points at A.
        let fixture = try makeFixtureWithTopology(worktreeIds: [worktreeAId, worktreeBId])
        let graph = WorkspaceCoreRepository.PaneGraphRecord(
            panes: [
                makeWorktreeSourcedPane(
                    sourceWorktreeId: worktreeAId,
                    facetWorktreeId: worktreeBId,
                    residency: .active
                )
            ]
        )

        // Act & Assert — CURRENT behavior: deterministic validation throw on
        // every save attempt for legal roaming state.
        #expect(
            throws: WorkspaceCoreRepositoryError.paneSourceFacetWorktreeMismatch(
                paneId: paneId,
                sourceWorktreeId: worktreeAId,
                facetWorktreeId: worktreeBId
            )
        ) {
            try fixture.repository.replacePaneGraph(workspaceId: workspaceId, graph: graph)
        }
    }

    @Test("active pane sourced from a worktree missing from topology poisons the save")
    func activePaneWithDanglingSourceWorktreePoisonsSave() throws {
        // Arrange — orphaning can be skipped entirely (no effect handler
        // registered: WorkspaceCacheCoordinator "pane orphaning skipped").
        // The pane stays active while its source worktree is gone.
        let fixture = try makeFixtureWithTopology(worktreeIds: [worktreeAId])
        let graph = WorkspaceCoreRepository.PaneGraphRecord(
            panes: [
                makeWorktreeSourcedPane(
                    sourceWorktreeId: worktreeBId,
                    facetWorktreeId: worktreeBId,
                    residency: .active
                )
            ]
        )

        // Act & Assert
        #expect(throws: WorkspaceCoreRepositoryError.self) {
            try fixture.repository.replacePaneGraph(workspaceId: workspaceId, graph: graph)
        }
    }
}
