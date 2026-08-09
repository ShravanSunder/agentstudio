import AgentStudioCore
import AgentStudioGit

extension AgentStudioGitBridgeReviewDataClient {
    func localDefaultBranch() async throws -> String? {
        try await loadGitLocalDefaultBranch(
            freshnessKey: BridgeGitReadFreshnessKey(
                token: "\(gitReadContext.scopeKey.token):local-default-branch"
            )
        )?.name
    }

    func captureContributionComparison(_ request: BridgeContributionComparisonRequest) async throws
        -> BridgeContributionComparisonCapture
    {
        let reviewGeneration = BridgeReviewGeneration(request.reviewGenerationValue)
        let snapshot = try await loadGitContributionDiff(
            GitContributionDiffRequest(
                repositoryPath: repositoryPath,
                target: gitRevisionTarget(for: request.symbolicTarget)
            ),
            freshnessKey: gitReadFreshnessKey(for: reviewGeneration)
        )
        let baseEndpoint = BridgeSourceEndpoint(
            endpointId: request.baseEndpoint.endpointId,
            kind: .gitRef,
            repoId: request.baseEndpoint.repoId,
            worktreeId: request.baseEndpoint.worktreeId,
            label: request.baseEndpoint.label,
            createdAtUnixMilliseconds: request.baseEndpoint.createdAtUnixMilliseconds,
            contentSetHash: snapshot.contributionBase.oid,
            providerIdentity: snapshot.contributionBase.oid
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
            baseTarget: .commit(snapshot.contributionBase.oid),
            headTarget: .workingTree,
            reviewGeneration: reviewGeneration
        )
        return BridgeContributionComparisonCapture(
            resolvedTargetOID: snapshot.resolvedTarget.oid,
            reviewedHeadOID: snapshot.reviewedHead.oid,
            contributionBaseOID: snapshot.contributionBase.oid,
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: changedFiles
            )
        )
    }

    private func gitRevisionTarget(
        for target: WorkspaceReviewContributionTarget
    ) -> GitRevisionTarget {
        switch target {
        case .localDefaultBranch(let branchName), .branch(let branchName):
            .named(branchName)
        case .originDefaultBranch(let remoteName, let branchName):
            .named("\(remoteName)/\(branchName)")
        case .ref(let name):
            .named(name)
        }
    }
}
