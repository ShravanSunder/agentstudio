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
        let host = registerProjectionTestMaterializationHost(adapter: adapter)
        defer { host.detach() }

        adapter.admit(
            fixture.request(
                generation: 1,
                paneFacts: fixture.initialPaneFacts,
                referenceDate: fixture.initialReferenceDate
            )
        )
        var previousRevision = try await publishedResult(
            generation: 1,
            from: adapter
        ).materializedRevision

        let scenarios: [(facts: RepoExplorerPaneRowFacts, referenceDate: Date)] = [
            (fixture.paneFacts(terminalTitle: "build running"), fixture.initialReferenceDate),
            (fixture.paneFacts(noteText: "Waiting on review"), fixture.initialReferenceDate),
            (fixture.paneFacts(latestMessageText: "Tests passed"), fixture.initialReferenceDate),
            (
                fixture.paneFacts(
                    recencyReferenceDate: fixture.initialReferenceDate.addingTimeInterval(-5 * 60)
                ),
                fixture.initialReferenceDate
            ),
            (
                fixture.paneFacts(),
                fixture.initialReferenceDate.addingTimeInterval(
                    AppPolicies.EntityRecency.faintBlueDuration + 1
                )
            ),
            (
                fixture.paneFacts(
                    activityAt: fixture.initialReferenceDate.addingTimeInterval(-30)
                ),
                fixture.initialReferenceDate
            ),
            (fixture.paneFacts(isPinned: true), fixture.initialReferenceDate),
            (fixture.paneFacts(isActive: true), fixture.initialReferenceDate),
            (fixture.paneFacts(isDrawerPane: true), fixture.initialReferenceDate),
        ]

        for (offset, scenario) in scenarios.enumerated() {
            let generation = offset + 2
            adapter.admit(
                fixture.request(
                    generation: generation,
                    paneFacts: scenario.facts,
                    referenceDate: scenario.referenceDate
                )
            )
            let publication = try await publishedResult(generation: generation, from: adapter)

            #expect(publication.materializedRevision == previousRevision + 1)
            previousRevision = publication.materializedRevision
        }
    }

    @Test("worker-native plan publishes group disclosure presentation changes")
    func groupDisclosurePresentationParticipatesInNativePlan() async throws {
        let fixture = PaneEqualityFixture()
        let adapter = RepoExplorerProjectionAdapter()
        defer { adapter.stop() }
        let host = registerProjectionTestMaterializationHost(adapter: adapter)
        defer { host.detach() }
        let initialRequest = fixture.request(
            generation: 1,
            paneFacts: fixture.initialPaneFacts,
            referenceDate: fixture.initialReferenceDate
        )

        adapter.admit(initialRequest)
        let initial = try await publishedResult(generation: 1, from: adapter)
        let groupID = try #require(
            initial.result.rowIndex.entries.compactMap { entry -> String? in
                guard case .resolvedGroupHeader(let group) = entry else { return nil }
                return group.id
            }.first
        )
        let collapsedRequest = initialRequest.replacing(collapsedGroupIds: [groupID]).generated(
            generation: 2,
            trigger: .dataRefresh
        )

        adapter.admit(collapsedRequest)
        let collapsed = try await publishedResult(generation: 2, from: adapter)

        #expect(collapsed.materializedRevision == initial.materializedRevision + 1)
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
    let initialReferenceDate = Date(timeIntervalSince1970: 1000)

    var initialPaneFacts: RepoExplorerPaneRowFacts {
        paneFacts()
    }

    func paneFacts(
        terminalTitle: String = "zsh",
        activityAt: Date? = nil,
        isPinned: Bool = false,
        noteText: String? = nil,
        latestMessageText: String? = nil,
        recencyReferenceDate: Date = Date(timeIntervalSince1970: 900),
        isActive: Bool = false,
        isDrawerPane: Bool = false
    ) -> RepoExplorerPaneRowFacts {
        RepoExplorerPaneRowFacts(
            terminalTitle: terminalTitle,
            activityAt: activityAt,
            isPinned: isPinned,
            noteText: noteText,
            latestMessageText: latestMessageText,
            recencyReferenceDate: recencyReferenceDate,
            recencyText: "captured-placeholder",
            recencyTier: .strongBlue,
            isActive: isActive,
            isDrawerPane: isDrawerPane
        )
    }

    func request(
        generation: Int,
        paneFacts: RepoExplorerPaneRowFacts,
        referenceDate: Date
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
                surface: .panes,
                groupingMode: .repo,
                subgroupMode: .activity,
                referenceDate: referenceDate,
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
