import AgentStudioCore
import AgentStudioGit

extension AgentStudioGitBridgeReviewDataClient {
    func resolveReviewDefaultTarget() async throws -> BridgeReviewComparisonDefaultTargetIdentity? {
        let target = try await loadGitReviewDefaultTarget(
            freshnessKey: BridgeGitReadFreshnessKey(
                token: "\(gitReadContext.scopeKey.token):review-comparison-default-target"
            )
        )
        switch target {
        case .remoteTracking(let remoteName, let branchName, _):
            return BridgeReviewComparisonDefaultTargetIdentity(
                remoteName: remoteName,
                branchName: branchName
            )
        case .local, .none:
            return nil
        }
    }

    func captureReviewComparisonTargets(
        _ request: BridgeReviewComparisonTargetsCaptureRequest
    ) async throws -> BridgeReviewComparisonTargetsCapture {
        let capture = try await loadGitReviewComparisonTargets(
            GitReviewComparisonTargetCaptureRequest(
                repositoryPath: repositoryPath,
                capturedAt: request.capturedAtUnixMilliseconds,
                cutoff: request.cutoffUnixMilliseconds,
                maximumRows: request.maximumRows,
                currentBranchReference: Self.referenceName(for: request.currentTarget)
            ),
            freshnessKey: BridgeGitReadFreshnessKey(
                token:
                    "\(gitReadContext.scopeKey.token):review-comparison-targets:\(request.capturedAtUnixMilliseconds)"
            )
        )
        let targetsByReference: [String: GitReviewComparisonBranchTarget] = Dictionary(
            uniqueKeysWithValues: capture.rows.map { ($0.canonicalReferenceName, $0.target) }
        )
        return BridgeReviewComparisonTargetsCapture(
            capturedAtUnixMilliseconds: capture.capturedAt,
            cutoffUnixMilliseconds: capture.cutoff,
            isTruncated: capture.isTruncated,
            defaultTarget: capture.defaultReferenceName.flatMap { targetsByReference[$0].map(Self.bridgeTarget) },
            currentTarget: capture.currentReferenceName.flatMap { targetsByReference[$0].map(Self.bridgeTarget) },
            branches: capture.rows.map { Self.bridgeTarget($0.target) }
        )
    }

    private static func referenceName(
        for target: WorkspaceReviewContributionTarget?
    ) -> String? {
        guard let target else { return nil }
        switch target {
        case .localDefaultBranch(let branchName, _), .branch(let branchName, _):
            return "refs/heads/\(branchName)"
        case .originDefaultBranch(let remoteName, let branchName, _):
            return "refs/remotes/\(remoteName)/\(branchName)"
        case .ref(let name, _):
            return name
        case .commit:
            return nil
        }
    }

    private static func bridgeTarget(
        _ target: GitReviewComparisonBranchTarget
    ) -> BridgeReviewComparisonBranchTarget {
        switch target {
        case .local(let branchName, let oid):
            return .local(branchName: branchName, oid: oid)
        case .remoteTracking(let remoteName, let branchName, let oid):
            return .remoteTracking(remoteName: remoteName, branchName: branchName, oid: oid)
        }
    }

    func captureContributionComparison(_ request: BridgeContributionComparisonRequest) async throws
        -> BridgeContributionComparisonCapture
    {
        let reviewGeneration = BridgeReviewGeneration(request.reviewGenerationValue)
        let target = gitRevisionTarget(for: request.symbolicTarget)
        let refreshInput = gitReviewRefreshInput(for: request)
        let freshnessKey = gitReadFreshnessKey(
            forReviewAttemptAuthorityGeneration: request.reviewAttemptAuthorityGeneration
        )
        if usesDirectComparison(request.symbolicTarget) {
            let result = try await loadGitDirectReviewComparison(
                GitDirectReviewComparisonRequest(
                    repositoryPath: repositoryPath,
                    target: target,
                    refreshInput: refreshInput
                ),
                freshnessKey: freshnessKey
            )
            let snapshot = result.snapshot
            return makeContributionCapture(
                request: request,
                reviewGeneration: reviewGeneration,
                snapshot: ContributionComparisonSnapshot(
                    resolvedTarget: snapshot.resolvedTarget,
                    reviewedHead: snapshot.reviewedHead,
                    baseRole: .selectedTarget,
                    comparisonBase: snapshot.resolvedTarget,
                    diff: snapshot.diff
                ),
                successorSeed: result.successorSeed,
                calculationDisposition: result.calculationDisposition,
                calculationReason: result.calculationReason
            )
        }
        let result = try await loadGitContributionDiff(
            GitContributionDiffRequest(
                repositoryPath: repositoryPath,
                target: target,
                refreshInput: refreshInput
            ),
            freshnessKey: freshnessKey
        )
        let snapshot = result.snapshot
        return makeContributionCapture(
            request: request,
            reviewGeneration: reviewGeneration,
            snapshot: ContributionComparisonSnapshot(
                resolvedTarget: snapshot.resolvedTarget,
                reviewedHead: snapshot.reviewedHead,
                baseRole: .commonCommit,
                comparisonBase: snapshot.contributionBase,
                diff: snapshot.diff
            ),
            successorSeed: result.successorSeed,
            calculationDisposition: result.calculationDisposition,
            calculationReason: result.calculationReason
        )
    }

    private func makeContributionCapture(
        request: BridgeContributionComparisonRequest,
        reviewGeneration: BridgeReviewGeneration,
        snapshot: ContributionComparisonSnapshot,
        successorSeed: GitReviewRefreshSeed,
        calculationDisposition: GitReviewCalculationDisposition,
        calculationReason: GitReviewCalculationReason
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
            reviewedSubjectBranchName: snapshot.reviewedHead.shortName,
            baseRole: snapshot.baseRole,
            baseOID: snapshot.comparisonBase.oid,
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: changedFiles
            ),
            gitRefreshSeed: successorSeed,
            calculationDisposition: calculationDisposition,
            calculationReason: calculationReason
        )
    }

    private func gitReviewRefreshInput(
        for request: BridgeContributionComparisonRequest
    ) -> GitReviewRefreshInput {
        guard case .exactPaths(let paths) = request.gitRefreshScope,
            let seed = request.gitRefreshSeed
        else { return .complete }
        return .proportional(seed: seed, changedPaths: paths)
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
