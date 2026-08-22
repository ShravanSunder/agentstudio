import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("RepoExplorer rendered equality")
struct RepoExplorerRenderedEqualityTests {
    @Test("every visible pane field republishes the immutable rendered row")
    func everyVisiblePaneFieldRepublishes() async throws {
        let fixture = PaneEqualityFixture()
        let adapter = RepoExplorerProjectionAdapter()
        defer { adapter.stop() }

        adapter.admit(fixture.request(generation: 1, paneFacts: fixture.initialPaneFacts))
        var previousRevision = try await publishedResult(
            generation: 1,
            from: adapter
        ).materializedRevision

        let changedPaneFacts: [RepoExplorerPaneRowFacts] = [
            fixture.paneFacts(terminalTitle: "build running"),
            fixture.paneFacts(noteText: "Waiting on review"),
            fixture.paneFacts(latestMessageText: "Tests passed"),
            fixture.paneFacts(recencyText: "5m"),
            fixture.paneFacts(recencyTier: .grey),
            fixture.paneFacts(isActive: true),
            fixture.paneFacts(isDrawerPane: true),
        ]

        for (offset, paneFacts) in changedPaneFacts.enumerated() {
            let generation = offset + 2
            adapter.admit(fixture.request(generation: generation, paneFacts: paneFacts))
            let publication = try await publishedResult(generation: generation, from: adapter)

            #expect(publication.materializedRevision == previousRevision + 1)
            previousRevision = publication.materializedRevision
        }
    }

    @Test("group disclosure presentation participates in rendered equality")
    func groupDisclosurePresentationParticipatesInRenderedEquality() {
        let group = RepoPresentationGroup(
            id: "remote:askluna/disclosure-only",
            repoTitle: "disclosure-only",
            organizationName: "askluna",
            repos: []
        )
        let projection = RepoExplorerSidebarProjection.ready(
            RepoExplorerSidebarContent(
                sections: [
                    RepoExplorerSidebarSection(
                        kind: .repositories,
                        resolvedGroups: [group],
                        loadingRepos: []
                    )
                ],
                resolvedGroups: [group],
                loadingRepos: [],
                emptyState: .content
            )
        )
        let snapshot = RepoExplorerSnapshot(
            repos: [],
            repoEnrichmentByRepoId: [:],
            groupingMode: .repo,
            query: ""
        )
        func result(collapsedGroupIDs: Set<String>) -> RepoExplorerProjectionResult {
            let rowIndex = RepoExplorerRowIndex(
                projection: projection,
                collapsedGroupIds: collapsedGroupIDs,
                isFiltering: false
            )
            return RepoExplorerProjectionResult(
                generation: collapsedGroupIDs.isEmpty ? 1 : 2,
                snapshot: snapshot,
                collapsedGroupIds: collapsedGroupIDs,
                isFiltering: false,
                trigger: .dataRefresh,
                projection: projection,
                rowIndex: rowIndex,
                materializationSnapshot: RepoExplorerMaterializationSnapshot.build(
                    rowIndex: rowIndex,
                    inputs: RepoExplorerMaterializationInputs(
                        snapshot: snapshot,
                        projection: projection,
                        branchStatusByWorktreeID: [:],
                        branchNameByWorktreeID: [:],
                        bridgeCommandResolutionByWorktreeID: [:],
                        paneRowFactsByPaneID: [:]
                    )
                ),
                workerDuration: .zero,
                projectionDuration: .zero,
                rowIndexDuration: .zero,
                branchStatusByWorktreeId: [:],
                branchNameByWorktreeId: [:],
                bridgeCommandResolutionByWorktreeId: [:],
                paneRowFactsByPaneId: [:],
                tabGroupFactsByTabId: [:],
                semanticBaselineSequence: nil
            )
        }

        #expect(
            !RepoExplorerProjectionAdapter.hasEqualRenderedContent(
                result(collapsedGroupIDs: []),
                result(collapsedGroupIDs: [group.id])
            )
        )
    }

    private func publishedResult(
        generation: Int,
        from adapter: RepoExplorerProjectionAdapter
    ) async throws -> (result: RepoExplorerProjectionResult, materializedRevision: Int) {
        for _ in 0..<10_000 where adapter.publishedResult?.generation != generation {
            await Task.yield()
        }
        return (
            try #require(adapter.publishedResult),
            try #require(adapter.materializedProjection).revision
        )
    }
}

private struct PaneEqualityFixture {
    let repoId = UUIDv7.generate()
    let worktreeId = UUIDv7.generate()
    let paneId = UUIDv7.generate()
    let tabId = UUIDv7.generate()

    var initialPaneFacts: RepoExplorerPaneRowFacts {
        paneFacts()
    }

    func paneFacts(
        terminalTitle: String = "zsh",
        noteText: String? = nil,
        latestMessageText: String? = nil,
        recencyText: String = "Now",
        recencyTier: RepoExplorerPaneRecencyTier = .strongBlue,
        isActive: Bool = false,
        isDrawerPane: Bool = false
    ) -> RepoExplorerPaneRowFacts {
        RepoExplorerPaneRowFacts(
            terminalTitle: terminalTitle,
            noteText: noteText,
            latestMessageText: latestMessageText,
            recencyReferenceDate: Date(timeIntervalSince1970: 100),
            recencyText: recencyText,
            recencyTier: recencyTier,
            isActive: isActive,
            isDrawerPane: isDrawerPane
        )
    }

    func request(
        generation: Int,
        paneFacts: RepoExplorerPaneRowFacts
    ) -> RepoExplorerProjectionRequest {
        let worktree = Worktree(
            id: worktreeId,
            repoId: repoId,
            name: "main",
            path: URL(fileURLWithPath: "/tmp/repo-explorer-rendered-equality"),
            isMainWorktree: true
        )
        let repo = RepoPresentationItem(
            id: repoId,
            name: "rendered-equality",
            repoPath: worktree.path,
            stableKey: "rendered-equality",
            worktrees: [worktree]
        )
        return RepoExplorerProjectionRequest(
            generation: generation,
            snapshot: RepoExplorerSnapshot(
                repos: [repo],
                repoEnrichmentByRepoId: [repoId: resolvedRemote],
                groupingMode: .pane,
                query: "",
                paneLocationsByWorktreeId: [
                    worktreeId: [
                        WorkspacePaneLocation(
                            paneId: paneId,
                            tabId: tabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ]
                ]
            ),
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .dataRefresh,
            worktreeEnrichmentSnapshot: [
                worktreeId: WorktreeEnrichment(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    branch: "main",
                    isMainWorktree: true,
                    updatedAt: Date(timeIntervalSince1970: 100)
                )
            ],
            paneRowFactsByPaneId: [paneId: paneFacts]
        )
    }

    private var resolvedRemote: RepoEnrichment {
        .resolvedRemote(
            repoId: repoId,
            raw: RawRepoOrigin(origin: "git@github.com:askluna/rendered-equality.git", upstream: nil),
            identity: RepoIdentity(
                groupKey: "remote:askluna/rendered-equality",
                remoteSlug: "askluna/rendered-equality",
                organizationName: "askluna",
                displayName: "rendered-equality"
            ),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }
}
