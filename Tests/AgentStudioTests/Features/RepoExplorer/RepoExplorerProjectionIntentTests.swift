import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("Repo Explorer pure projection intent")
struct RepoExplorerProjectionIntentTests {
    @Test("delta intent carries latest request scope and structural target only")
    func deltaIntentContainsNoPreparedBaseline() {
        let request = makeProjectionIntentRequest(generation: 1)
        let change = RepoExplorerScopedProjectionChange.repo(request.snapshot.repos[0].id)
        let structuralTarget = RepoExplorerProjectionStructuralTarget(request: request)
        let delta = RepoExplorerProjectionDeltaIntent(
            targetRequest: request,
            changes: [change],
            structuralTarget: structuralTarget
        )

        #expect(delta.targetRequest == request)
        #expect(delta.changes == [change])
        #expect(delta.structuralTarget == structuralTarget)
        #expect(
            Mirror(reflecting: delta).children.map(\.label) == [
                "targetRequest",
                "changes",
                "structuralTarget",
            ])
    }

    @Test("pending B and C combine pure affected scope with latest facts")
    func pendingDeltaIntentsCombineWithoutWork() {
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let pendingRequest = makeProjectionIntentRequest(
            generation: 2,
            repositoryID: repositoryID,
            worktreeID: worktreeID
        )
        let latestRequest = makeProjectionIntentRequest(
            generation: 3,
            repositoryID: repositoryID,
            worktreeID: worktreeID,
            isFavorite: true
        )
        let target = RepoExplorerProjectionStructuralTarget(request: latestRequest)
        let pending = RepoExplorerProjectionIntent.delta(
            RepoExplorerProjectionDeltaIntent(
                targetRequest: pendingRequest,
                changes: [.worktreeFact(worktreeID)],
                structuralTarget: target
            )
        )
        let latest = RepoExplorerProjectionIntent.delta(
            RepoExplorerProjectionDeltaIntent(
                targetRequest: latestRequest,
                changes: [.repo(repositoryID)],
                structuralTarget: target
            )
        )

        let combined = RepoExplorerProjectionIntent.combinePending(pending, latest)
        guard case .delta(let delta) = combined else {
            Issue.record("Expected a combined pure delta intent")
            return
        }

        #expect(delta.targetRequest == latestRequest)
        #expect(delta.changes == [.worktreeFact(worktreeID), .repo(repositoryID)])
        #expect(delta.structuralTarget == target)
    }

    @Test("pending deltas retain latest structural target without MainActor fleet comparison")
    func pendingDeltasRetainLatestStructuralTarget() {
        let pendingRequest = makeProjectionIntentRequest(generation: 2)
        let latestRequest = makeProjectionIntentRequest(generation: 3, query: "changed")
        let pending = RepoExplorerProjectionIntent.delta(
            RepoExplorerProjectionDeltaIntent(
                targetRequest: pendingRequest,
                changes: [.repo(pendingRequest.snapshot.repos[0].id)],
                structuralTarget: RepoExplorerProjectionStructuralTarget(request: pendingRequest)
            )
        )
        let latest = RepoExplorerProjectionIntent.delta(
            RepoExplorerProjectionDeltaIntent(
                targetRequest: latestRequest,
                changes: [.repo(latestRequest.snapshot.repos[0].id)],
                structuralTarget: RepoExplorerProjectionStructuralTarget(request: latestRequest)
            )
        )

        let combined = RepoExplorerProjectionIntent.combinePending(pending, latest)
        guard case .delta(let delta) = combined else {
            Issue.record("Expected structural validation to remain worker-owned")
            return
        }
        #expect(delta.targetRequest == latestRequest)
        #expect(delta.structuralTarget == RepoExplorerProjectionStructuralTarget(request: latestRequest))
        #expect(
            delta.changes == [
                .repo(pendingRequest.snapshot.repos[0].id),
                .repo(latestRequest.snapshot.repos[0].id),
            ]
        )
    }
}

func makeProjectionIntentRequest(
    generation: Int,
    repositoryID: UUID = UUIDv7.generate(),
    worktreeID: UUID = UUIDv7.generate(),
    isFavorite: Bool = false,
    query: String = ""
) -> RepoExplorerProjectionRequest {
    let repository = RepoPresentationItem(
        id: repositoryID,
        name: "agent-studio",
        repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
        stableKey: "agent-studio",
        isFavorite: isFavorite,
        worktrees: [
            Worktree(
                id: worktreeID,
                repoId: repositoryID,
                name: "main",
                path: URL(fileURLWithPath: "/tmp/agent-studio"),
                isMainWorktree: true
            )
        ]
    )
    return RepoExplorerProjectionRequest(
        generation: generation,
        snapshot: RepoExplorerSnapshot(
            repos: [repository],
            repoEnrichmentByRepoId: [:],
            groupingMode: .repo,
            query: query
        ),
        collapsedGroupIds: [],
        isFiltering: !query.isEmpty,
        trigger: .dataRefresh
    )
}
