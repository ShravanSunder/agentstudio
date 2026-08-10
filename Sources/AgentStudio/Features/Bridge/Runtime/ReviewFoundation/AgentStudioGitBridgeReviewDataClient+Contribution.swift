import AgentStudioCore
import AgentStudioGit

extension AgentStudioGitBridgeReviewDataClient {
    func reviewComparisonTargets() async throws -> BridgeReviewComparisonTargetCatalog? {
        let catalog = try await loadGitReviewComparisonTargets(
            freshnessKey: BridgeGitReadFreshnessKey(
                token: "\(gitReadContext.scopeKey.token):review-comparison-targets"
            )
        )
        return BridgeReviewComparisonTargetCatalog(
            defaultTarget: catalog.defaultTarget.map(bridgeReviewComparisonBranchTarget),
            branches: catalog.branches.map(bridgeReviewComparisonBranchTarget)
        )
    }

    private func bridgeReviewComparisonBranchTarget(
        _ target: GitReviewComparisonBranchTarget
    ) -> BridgeReviewComparisonBranchTarget {
        switch target {
        case .local(let branchName, let oid):
            .local(branchName: branchName, oid: oid)
        case .remoteTracking(let remoteName, let branchName, let oid):
            .remoteTracking(remoteName: remoteName, branchName: branchName, oid: oid)
        }
    }

    func captureContributionComparison(_ request: BridgeContributionComparisonRequest) async throws
        -> BridgeContributionComparisonCapture
    {
        let reviewGeneration = BridgeReviewGeneration(request.reviewGenerationValue)
        let target = gitRevisionTarget(for: request.symbolicTarget)
        if usesDirectComparison(request.symbolicTarget) {
            let snapshot = try await loadGitDirectReviewComparison(
                GitDirectReviewComparisonRequest(
                    repositoryPath: repositoryPath,
                    target: target
                ),
                freshnessKey: gitReadFreshnessKey(for: reviewGeneration)
            )
            return makeContributionCapture(
                request: request,
                reviewGeneration: reviewGeneration,
                snapshot: ContributionComparisonSnapshot(
                    resolvedTarget: snapshot.resolvedTarget,
                    reviewedHead: snapshot.reviewedHead,
                    baseRole: .selectedTarget,
                    comparisonBase: snapshot.resolvedTarget,
                    diff: snapshot.diff
                )
            )
        }
        let snapshot = try await loadGitContributionDiff(
            GitContributionDiffRequest(
                repositoryPath: repositoryPath,
                target: target
            ),
            freshnessKey: gitReadFreshnessKey(for: reviewGeneration)
        )
        return makeContributionCapture(
            request: request,
            reviewGeneration: reviewGeneration,
            snapshot: ContributionComparisonSnapshot(
                resolvedTarget: snapshot.resolvedTarget,
                reviewedHead: snapshot.reviewedHead,
                baseRole: .commonCommit,
                comparisonBase: snapshot.contributionBase,
                diff: snapshot.diff
            )
        )
    }

    private func makeContributionCapture(
        request: BridgeContributionComparisonRequest,
        reviewGeneration: BridgeReviewGeneration,
        snapshot: ContributionComparisonSnapshot
    ) -> BridgeContributionComparisonCapture {
        let baseEndpoint = BridgeSourceEndpoint(
            endpointId: request.baseEndpoint.endpointId,
            kind: .gitRef,
            repoId: request.baseEndpoint.repoId,
            worktreeId: request.baseEndpoint.worktreeId,
            label: request.baseEndpoint.label,
            createdAtUnixMilliseconds: request.baseEndpoint.createdAtUnixMilliseconds,
            contentSetHash: snapshot.comparisonBase.oid,
            providerIdentity: snapshot.comparisonBase.oid
        )
        let headEndpoint = BridgeSourceEndpoint(
            endpointId: request.headEndpoint.endpointId,
            kind: .workingTree,
            repoId: request.headEndpoint.repoId,
            worktreeId: request.headEndpoint.worktreeId,
            label: request.headEndpoint.label,
            createdAtUnixMilliseconds: request.headEndpoint.createdAtUnixMilliseconds,
            contentSetHash: request.headEndpoint.contentSetHash,
            providerIdentity: request.headEndpoint.providerIdentity
        )
        let changedFiles = snapshot.diff.files.map(bridgeChangedFile)
        registerContentLocators(
            for: changedFiles,
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            baseTarget: .commit(snapshot.comparisonBase.oid),
            headTarget: .workingTree,
            reviewGeneration: reviewGeneration
        )
        return BridgeContributionComparisonCapture(
            resolvedTargetOID: snapshot.resolvedTarget.oid,
            reviewedHeadOID: snapshot.reviewedHead.oid,
            baseRole: snapshot.baseRole,
            baseOID: snapshot.comparisonBase.oid,
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: changedFiles
            )
        )
    }

    private struct ContributionComparisonSnapshot {
        let resolvedTarget: GitResolvedRevision
        let reviewedHead: GitResolvedRevision
        let baseRole: BridgeReviewComparisonBaseRole
        let comparisonBase: GitResolvedRevision
        let diff: GitDiffSnapshot
    }

    private func usesDirectComparison(_ target: WorkspaceReviewContributionTarget) -> Bool {
        switch target {
        case .localDefaultBranch(_, let basis), .originDefaultBranch(_, _, let basis),
            .branch(_, let basis), .ref(_, let basis):
            basis == .branchTip
        case .commit:
            true
        }
    }

    private func gitRevisionTarget(
        for target: WorkspaceReviewContributionTarget
    ) -> GitRevisionTarget {
        switch target {
        case .localDefaultBranch(let branchName, _):
            .named("refs/heads/\(branchName)")
        case .branch(let name, _):
            .named("refs/heads/\(name)")
        case .originDefaultBranch(let remoteName, let branchName, _):
            .named("refs/remotes/\(remoteName)/\(branchName)")
        case .commit(let oid):
            .named(oid)
        case .ref(let name, _):
            .named(name)
        }
    }
}
