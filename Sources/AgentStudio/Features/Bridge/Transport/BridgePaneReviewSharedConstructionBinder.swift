import Foundation

struct BridgePaneReviewSharedConstructionBinding: Sendable {
    let result: BridgeReviewPipelineResult
    let artifactPin: BridgeReviewPublicationArtifactPin
}

final class BridgeReviewPublicationArtifactPin: @unchecked Sendable, Equatable {
    let constructionLease: BridgeWorktreeProductConstructionLease

    private let coordinator: BridgeWorktreeProductConstructionCoordinator
    private let lock = NSLock()
    private var releaseTask: Task<BridgeWorktreeProductConstructionLeaseRelease, Never>?

    init(
        coordinator: BridgeWorktreeProductConstructionCoordinator,
        constructionLease: BridgeWorktreeProductConstructionLease
    ) {
        self.coordinator = coordinator
        self.constructionLease = constructionLease
    }

    static func == (left: BridgeReviewPublicationArtifactPin, right: BridgeReviewPublicationArtifactPin)
        -> Bool
    {
        left === right
    }

    func release() {
        lock.withLock {
            guard releaseTask == nil else { return }
            let coordinator = self.coordinator
            let constructionLease = self.constructionLease
            releaseTask = Task {
                await coordinator.release(constructionLease)
            }
        }
    }

    func releaseAndWait() async {
        let backing: BridgeSharedReviewContentBacking? =
            switch constructionLease.artifact {
            case .fileSnapshot:
                nil
            case .reviewTemplate(let template):
                template.backing
            }
        release()
        let task = lock.withLock { releaseTask }
        guard let release = await task?.value,
            release.requiresArtifactCleanupDrain
        else { return }
        await backing?.waitUntilInvalidationCleanupCompletes()
    }
}

struct BridgePaneReviewSharedConstructionBinder: Sendable {
    private let coordinator: BridgeWorktreeProductConstructionCoordinator
    private let pipeline: BridgeReviewPipeline
    private let repositoryPath: URL

    init(
        coordinator: BridgeWorktreeProductConstructionCoordinator,
        pipeline: BridgeReviewPipeline,
        repositoryPath: URL
    ) {
        self.coordinator = coordinator
        self.pipeline = pipeline
        self.repositoryPath = repositoryPath.standardizedFileURL
    }

    func acquire(
        _ request: BridgeReviewPipelineRequest
    ) async throws -> BridgePaneReviewSharedConstructionBinding {
        let worktree = worktreeIdentity(for: request)
        let pipeline = pipeline
        let lease: BridgeWorktreeProductConstructionLease
        let resolvedRequest: BridgeReviewPipelineRequest
        while true {
            let context = try await coordinator.freshnessContext(for: worktree)
            let freshnessKey = gitFreshnessKey(for: context)
            let candidateRequest = try await pipeline.resolveSharedConstructionRequest(
                request,
                freshnessKey: freshnessKey
            )
            let key = try constructionKey(for: candidateRequest)
            do {
                lease = try await coordinator.acquire(
                    key: .review(key),
                    expectedEpoch: context.epoch
                ) { _ in
                    let template = try await pipeline.buildSharedTemplate(
                        request: candidateRequest,
                        baseEndpointKey: key.baseEndpoint,
                        headEndpointKey: key.headEndpoint,
                        freshnessKey: freshnessKey
                    )
                    return .reviewTemplate(template)
                }
                resolvedRequest = candidateRequest
                break
            } catch BridgeWorktreeProductConstructionError.freshnessEpochMismatch {
                try Task.checkCancellation()
                continue
            }
        }
        guard case .reviewTemplate(let template) = lease.artifact else {
            await coordinator.release(lease)
            throw BridgeWorktreeProductConstructionError.artifactKindMismatch
        }
        do {
            let result = try await pipeline.bindSharedTemplate(
                template,
                request: resolvedRequest
            )
            return BridgePaneReviewSharedConstructionBinding(
                result: result,
                artifactPin: BridgeReviewPublicationArtifactPin(
                    coordinator: coordinator,
                    constructionLease: lease
                )
            )
        } catch {
            await coordinator.release(lease)
            throw error
        }
    }

    private func worktreeIdentity(
        for request: BridgeReviewPipelineRequest
    ) -> BridgeWorktreeIdentityKey {
        BridgeWorktreeIdentityKey(
            repoIdentity: request.query.repoId.uuidString,
            worktreeIdentity: request.query.worktreeId.uuidString,
            stableRootIdentity: StableKey.fromPath(repositoryPath)
        )
    }

    private func gitFreshnessKey(
        for context: BridgeWorktreeProductConstructionFreshnessContext
    ) -> BridgeGitReadFreshnessKey {
        BridgeGitReadFreshnessKey(
            token:
                "review-construction:\(context.worktree.worktreeIdentity):epoch:\(context.epoch.rawValue)"
        )
    }

    func release(_ lease: BridgeWorktreeProductConstructionLease) async {
        await coordinator.release(lease)
    }

    private func constructionKey(
        for request: BridgeReviewPipelineRequest
    ) throws -> BridgeReviewConstructionKey {
        BridgeReviewConstructionKey(
            owner: BridgeWorktreeProductOwnerKey(
                repoIdentity: request.query.repoId.uuidString,
                worktreeIdentity: request.query.worktreeId.uuidString,
                stableRootIdentity: StableKey.fromPath(repositoryPath),
                providerIdentity: "agentstudio-git-review-v1"
            ),
            queryKind: try mappedEnum(request.query.queryKind),
            comparisonSemantics: try mappedEnum(request.query.comparisonSemantics),
            canonicalWorkingDirectoryIdentity: StableKey.fromPath(repositoryPath),
            baseEndpoint: try endpointKey(request.baseEndpoint),
            headEndpoint: try endpointKey(request.headEndpoint),
            pathScope: request.query.pathScope,
            fileTarget: request.query.fileTarget,
            viewFilter: viewFilterKey(request.query.viewFilter),
            grouping: BridgeReviewGroupingKey(
                kind: try mappedEnum(request.query.grouping.kind),
                label: request.query.grouping.label
            ),
            provenance: provenanceKey(request.query.provenanceFilter),
            checkpoint: nil
        )
    }

    private func endpointKey(
        _ endpoint: BridgeSourceEndpoint
    ) throws -> BridgeResolvedReviewEndpointKey {
        switch endpoint.kind {
        case .gitRef:
            guard let oid = endpoint.contentSetHash, !oid.isEmpty,
                endpoint.providerIdentity == oid
            else {
                throw BridgeProviderFailure.providerFailed(
                    message: "Git Review endpoint was not resolved to a concrete object"
                )
            }
            return BridgeResolvedReviewEndpointKey(
                kind: .gitObject,
                providerIdentity: "agentstudio-git",
                contentIdentity: oid
            )
        case .workingTree:
            return BridgeResolvedReviewEndpointKey(
                kind: .workingTree,
                providerIdentity: "agentstudio-git",
                contentIdentity: "working-tree"
            )
        case .index:
            return BridgeResolvedReviewEndpointKey(
                kind: .index,
                providerIdentity: "agentstudio-git",
                contentIdentity: "index"
            )
        case .promptCheckpoint, .sessionCheckpoint, .manualCheckpoint,
            .savedTimeWindowCheckpoint:
            throw BridgeProviderFailure.providerFailed(
                message: "Shared Review checkpoint construction is not supported"
            )
        }
    }

    private func viewFilterKey(_ filter: BridgeViewFilter) -> BridgeReviewViewFilterKey {
        BridgeReviewViewFilterKey(
            includedPathGlobs: filter.includedPathGlobs,
            excludedPathGlobs: filter.excludedPathGlobs,
            includedFileClasses: filter.includedFileClasses.map(\.rawValue),
            excludedFileClasses: filter.excludedFileClasses.map(\.rawValue),
            includedExtensions: filter.includedExtensions,
            excludedExtensions: filter.excludedExtensions,
            changeKinds: filter.changeKinds.map(\.rawValue),
            reviewStates: filter.reviewStates.map(\.rawValue),
            showsHiddenFiles: filter.showHiddenFiles,
            showsBinaryFiles: filter.showBinaryFiles,
            showsLargeFiles: filter.showLargeFiles
        )
    }

    private func provenanceKey(
        _ filter: BridgeProvenanceFilter
    ) -> BridgeReviewProvenanceFilterKey {
        BridgeReviewProvenanceFilterKey(
            paneIdentities: filter.paneIds,
            agentSessionIdentities: filter.agentSessionIds,
            promptIdentities: filter.promptIds,
            operationIdentities: filter.operationIds,
            createdAfterUnixMilliseconds: filter.createdAfterUnixMilliseconds,
            createdBeforeUnixMilliseconds: filter.createdBeforeUnixMilliseconds,
            sourceKinds: filter.sourceKinds.map(\.rawValue)
        )
    }

    private func mappedEnum(
        _ kind: BridgeReviewQuery.Kind
    ) throws -> BridgeReviewQueryKindKey {
        guard let mapped = BridgeReviewQueryKindKey(rawValue: kind.rawValue) else {
            throw BridgeProviderFailure.providerFailed(message: "Unsupported Review query kind")
        }
        return mapped
    }

    private func mappedEnum(
        _ semantics: BridgeReviewQuery.ComparisonSemantics
    ) throws -> BridgeReviewComparisonSemanticsKey {
        guard let mapped = BridgeReviewComparisonSemanticsKey(rawValue: semantics.rawValue) else {
            throw BridgeProviderFailure.providerFailed(
                message: "Unsupported Review comparison semantics"
            )
        }
        return mapped
    }

    private func mappedEnum(
        _ kind: BridgeChangeGrouping.Kind
    ) throws -> BridgeReviewGroupingKindKey {
        guard let mapped = BridgeReviewGroupingKindKey(rawValue: kind.rawValue) else {
            throw BridgeProviderFailure.providerFailed(message: "Unsupported Review grouping kind")
        }
        return mapped
    }
}
