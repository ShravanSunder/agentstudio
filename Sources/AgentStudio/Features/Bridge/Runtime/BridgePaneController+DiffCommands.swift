import Foundation
import os.log

private let bridgeDiffCommandLogger = Logger(subsystem: "com.agentstudio", category: "BridgeDiffCommands")

@MainActor
extension BridgePaneController: BridgeRuntimeCommandHandling {
    func handleDiffCommand(
        _ command: DiffCommand,
        commandId: UUID,
        correlationId: UUID?
    ) async -> ActionResult {
        switch command {
        case .loadDiff(let artifact):
            paneState.diff.setStatus(.loading)
            paneState.diff.advanceEpoch()
            paneState.diff.setPackageMetadata(nil)
            paneState.diff.setPackageDelta(nil)
            let reviewGeneration = nextReviewGeneration.next()
            nextReviewGeneration = reviewGeneration
            do {
                let request = makeReviewPipelineRequest(
                    artifact: artifact,
                    reviewGeneration: reviewGeneration
                )
                let result = try await reviewPipeline.loadPackage(request)
                guard reviewGeneration == nextReviewGeneration else {
                    return .failure(.invalidPayload(description: "Stale bridge review load"))
                }
                let delta = try await reviewChangeIndex.ingestExplicitLoad(result.package)
                await reviewContentStore.activate(
                    handles: result.registeredContentHandles,
                    reviewGeneration: reviewGeneration
                )
                paneState.diff.setPackageMetadata(result.package)
                paneState.diff.setPackageDelta(delta)
                paneState.diff.setStatus(.ready)
                ingestRuntimeEvent(
                    .diff(.diffLoaded(stats: Self.diffStats(from: result.package.summary))),
                    commandId: commandId,
                    correlationId: correlationId
                )
                return .success(commandId: commandId)
            } catch BridgeProviderFailure.providerUnavailable {
                paneState.diff.setStatus(.error, error: "providerUnavailable")
                return .failure(.backendUnavailable(backend: "BridgeReviewSourceProvider"))
            } catch {
                bridgeDiffCommandLogger.error(
                    "Bridge review package load failed: \(String(describing: error), privacy: .private)"
                )
                paneState.diff.setStatus(.error, error: "loadFailed")
                return .failure(.invalidPayload(description: "Failed to load bridge review package"))
            }
        }
    }

    private static func diffStats(from summary: BridgeReviewPackageSummary) -> DiffStats {
        DiffStats(
            filesChanged: summary.filesChanged,
            insertions: summary.additions,
            deletions: summary.deletions
        )
    }

    private func makeReviewPipelineRequest(
        artifact: DiffArtifact,
        reviewGeneration: BridgeReviewGeneration
    ) -> BridgeReviewPipelineRequest {
        let endpoints = makeReviewEndpoints(for: artifact)
        let query = BridgeReviewQuery(
            queryId: "query-\(artifact.diffId.uuidString)",
            queryKind: .compare,
            repoId: artifact.worktreeId,
            worktreeId: artifact.worktreeId,
            baseEndpointId: endpoints.base.endpointId,
            headEndpointId: endpoints.head.endpointId,
            comparisonSemantics: endpoints.comparisonSemantics,
            pathScope: endpoints.pathScope,
            fileTarget: nil,
            viewFilter: BridgeViewFilter(),
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

    private func makeReviewEndpoints(
        for artifact: DiffArtifact
    ) -> ReviewEndpointSelection {
        guard case .workspace(_, let baseline) = bridgePaneState.source else {
            return ReviewEndpointSelection(
                base: makeSourceEndpoint(
                    endpointId: "base-\(artifact.diffId.uuidString)",
                    kind: .gitRef,
                    repoId: artifact.worktreeId,
                    worktreeId: artifact.worktreeId,
                    label: "Base",
                    providerIdentity: "base:\(artifact.diffId.uuidString)"
                ),
                head: makeSourceEndpoint(
                    endpointId: "head-\(artifact.diffId.uuidString)",
                    kind: .workingTree,
                    repoId: artifact.worktreeId,
                    worktreeId: artifact.worktreeId,
                    label: "Working tree",
                    providerIdentity: "working-tree:\(artifact.diffId.uuidString)"
                ),
                comparisonSemantics: .workingTreeDelta,
                pathScope: []
            )
        }

        let repoId = artifact.worktreeId
        let base: BridgeSourceEndpoint
        let head: BridgeSourceEndpoint
        let semantics: BridgeReviewQuery.ComparisonSemantics
        switch baseline {
        case .headMinusOne:
            base = makeSourceEndpoint(
                endpointId: "baseline-headMinusOne",
                kind: .gitRef,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "HEAD~1",
                providerIdentity: "HEAD~1"
            )
            head = makeSourceEndpoint(
                endpointId: "working-tree",
                kind: .workingTree,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "Working tree",
                providerIdentity: "working-tree:\(artifact.worktreeId.uuidString)"
            )
            semantics = .workingTreeDelta
        case .staged:
            base = makeSourceEndpoint(
                endpointId: "baseline-head",
                kind: .gitRef,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "HEAD",
                providerIdentity: "HEAD"
            )
            head = makeSourceEndpoint(
                endpointId: "index",
                kind: .index,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "Index",
                providerIdentity: "index:\(artifact.worktreeId.uuidString)"
            )
            semantics = .indexDelta
        case .unstaged:
            base = makeSourceEndpoint(
                endpointId: "index",
                kind: .index,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "Index",
                providerIdentity: "index:\(artifact.worktreeId.uuidString)"
            )
            head = makeSourceEndpoint(
                endpointId: "working-tree",
                kind: .workingTree,
                repoId: repoId,
                worktreeId: artifact.worktreeId,
                label: "Working tree",
                providerIdentity: "working-tree:\(artifact.worktreeId.uuidString)"
            )
            semantics = .workingTreeDelta
        }
        return ReviewEndpointSelection(
            base: base,
            head: head,
            comparisonSemantics: semantics,
            pathScope: []
        )
    }

    private func makeSourceEndpoint(
        endpointId: String,
        kind: BridgeSourceEndpoint.Kind,
        repoId: UUID,
        worktreeId: UUID,
        label: String,
        providerIdentity: String
    ) -> BridgeSourceEndpoint {
        BridgeSourceEndpoint(
            endpointId: endpointId,
            kind: kind,
            repoId: repoId,
            worktreeId: worktreeId,
            label: label,
            createdAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1000),
            contentSetHash: nil,
            providerIdentity: providerIdentity
        )
    }
}

private struct ReviewEndpointSelection {
    let base: BridgeSourceEndpoint
    let head: BridgeSourceEndpoint
    let comparisonSemantics: BridgeReviewQuery.ComparisonSemantics
    let pathScope: [String]
}
