import AgentStudioCore
import Foundation

@MainActor
extension BridgePaneController {
    static func diffStats(from summary: BridgeReviewPackageSummary) -> DiffStats {
        DiffStats(
            filesChanged: summary.filesChanged,
            insertions: summary.additions,
            deletions: summary.deletions
        )
    }

    func makeReviewPipelineRequest(
        artifact: DiffArtifact,
        reviewGeneration: BridgeReviewGeneration
    ) -> BridgeReviewPipelineRequest {
        let repoId = reviewRepoId(for: artifact)
        let endpoints = makeReviewEndpoints(
            for: artifact,
            repoId: repoId
        )
        let query = BridgeReviewQuery(
            queryId: reviewSourceIdentity(for: artifact),
            queryKind: .compare,
            repoId: repoId,
            worktreeId: artifact.worktreeId,
            baseEndpointId: endpoints.base.endpointId,
            headEndpointId: endpoints.head.endpointId,
            comparisonSemantics: endpoints.comparisonSemantics,
            pathScope: endpoints.pathScope,
            fileTarget: nil,
            viewFilter: BridgeViewFilter(
                showHiddenFiles: true,
                showBinaryFiles: true,
                showLargeFiles: true
            ),
            grouping: BridgeChangeGrouping(kind: .flat),
            provenanceFilter: BridgeProvenanceFilter()
        )
        return BridgeReviewPipelineRequest(
            packageId: "package-\(artifact.diffId.uuidString)",
            query: query,
            baseEndpoint: endpoints.base,
            headEndpoint: endpoints.head,
            checkpointIds: [],
            reviewGeneration: reviewGeneration,
            generatedAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    func reviewSourceIdentity(for artifact: DiffArtifact) -> String {
        "query-\(artifact.diffId.uuidString)"
    }

    func reviewProtocolStreamId() -> String {
        "review:\(paneId.uuidString)"
    }

    func shouldRefreshReviewPackage(for event: PaneFilesystemContextEvent) -> Bool {
        guard let currentPackage = paneState.diff.packageMetadata else { return false }
        let context: PaneFilesystemContext
        switch event {
        case .cwdSubtreeChanged(let eventContext, let paths, _):
            guard !paths.isEmpty else { return false }
            context = eventContext
        case .gitWorkingTreeInCwd(let eventContext, _, _, _):
            context = eventContext
        }
        return context.paneId.uuid == paneId
            && context.worktreeId == currentPackage.query.worktreeId
    }

    func reviewRepoId(for artifact: DiffArtifact) -> UUID {
        runtime.metadata.facets.repoId ?? artifact.worktreeId
    }
}
