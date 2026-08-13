import AgentStudioCore
import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudioBridge

extension BridgeGitReviewSourceProviderTests {
    @Test("AgentStudioGit adapter captures typed local and remote Review comparison targets")
    func agentStudioGitAdapterPreservesTypedReviewComparisonTargets() async throws {
        let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-git-default-branch-test")
        let gitClient = AgentStudioGitLocalClientFake(
            reviewComparisonTargetCapture: GitReviewComparisonTargetCapture(
                capturedAt: 2000,
                cutoff: 1000,
                isTruncated: false,
                defaultReferenceName: "refs/remotes/origin/integration",
                currentReferenceName: "refs/heads/integration",
                rows: [
                    GitReviewComparisonTargetRow(
                        canonicalReferenceName: "refs/heads/integration",
                        target: .local(branchName: "integration", oid: "local-integration-oid"),
                        tipCommittedAt: 1900
                    ),
                    GitReviewComparisonTargetRow(
                        canonicalReferenceName: "refs/remotes/origin/integration",
                        target: .remoteTracking(
                            remoteName: "origin",
                            branchName: "integration",
                            oid: "origin-integration-oid"
                        ),
                        tipCommittedAt: 1800
                    ),
                ]
            )
        )
        let provider = BridgeGitReviewSourceProvider(
            client: AgentStudioGitBridgeReviewDataClient(
                repositoryPath: repositoryPath,
                client: gitClient,
                gitReadContext: makeBridgeGitReadContext(rootURL: repositoryPath)
            )
        )

        let capture = try await provider.captureReviewComparisonTargets(
            BridgeReviewComparisonTargetsCaptureRequest(
                currentTarget: .branch(name: "integration"),
                capturedAtUnixMilliseconds: 2000,
                cutoffUnixMilliseconds: 1000,
                maximumRows: 10
            )
        )

        #expect(capture.capturedAtUnixMilliseconds == 2000)
        #expect(capture.cutoffUnixMilliseconds == 1000)
        #expect(!capture.isTruncated)
        #expect(
            capture.defaultTarget
                == .remoteTracking(
                    remoteName: "origin",
                    branchName: "integration",
                    oid: "origin-integration-oid"
                )
        )
        #expect(capture.currentTarget == .local(branchName: "integration", oid: "local-integration-oid"))
        #expect(
            capture.branches
                == [
                    .local(branchName: "integration", oid: "local-integration-oid"),
                    .remoteTracking(
                        remoteName: "origin",
                        branchName: "integration",
                        oid: "origin-integration-oid"
                    ),
                ]
        )
        #expect(
            await gitClient.recordedReviewComparisonTargetRequests()
                == [
                    GitReviewComparisonTargetCaptureRequest(
                        repositoryPath: repositoryPath,
                        capturedAt: 2000,
                        cutoff: 1000,
                        maximumRows: 10,
                        currentBranchReference: "refs/heads/integration"
                    )
                ]
        )

        _ = try await provider.captureReviewComparisonTargets(
            BridgeReviewComparisonTargetsCaptureRequest(
                currentTarget: .ref(name: "origin/integration"),
                capturedAtUnixMilliseconds: 2001,
                cutoffUnixMilliseconds: 1001,
                maximumRows: 10
            )
        )

        #expect(
            await gitClient.recordedReviewComparisonTargetRequests().last?.currentBranchReference
                == "origin/integration"
        )
    }

    @Test("AgentStudioGit adapter captures one correlated contribution and registers its content")
    func agentStudioGitAdapterCapturesOneCorrelatedContributionAndRegistersContent() async throws {
        let fixture = makeContributionAdapterFixture()

        let capture = try await fixture.provider.captureContributionComparison(
            BridgeContributionComparisonRequest(
                symbolicTarget: .localDefaultBranch(
                    branchName: "integration",
                    basis: .commonCommit
                ),
                baseEndpoint: fixture.baseEndpoint,
                headEndpoint: fixture.headEndpoint,
                reviewGenerationValue: 12
            )
        )
        let package = try BridgeReviewPackageBuilder.build(
            request: BridgeReviewPackageBuildRequest(
                packageId: "package",
                query: makeBridgeReviewQuery(
                    baseEndpointId: fixture.baseEndpoint.endpointId,
                    headEndpointId: fixture.headEndpoint.endpointId
                ),
                comparison: capture.comparison,
                checkpointIds: [],
                reviewGeneration: 12,
                generatedAtUnixMilliseconds: 10
            )
        )
        let item = try #require(package.itemsById["item-source"])
        let baseResult = try await fixture.provider.loadContent(
            BridgeContentLoadRequest(handle: try #require(item.contentRoles.base), requestedGeneration: 12)
        )
        let headResult = try await fixture.provider.loadContent(
            BridgeContentLoadRequest(handle: try #require(item.contentRoles.head), requestedGeneration: 12)
        )

        #expect(capture.resolvedTargetOID == "target-oid")
        #expect(capture.reviewedHeadOID == "head-oid")
        #expect(capture.baseOID == "base-oid")
        #expect(capture.comparison.baseEndpoint.providerIdentity == "base-oid")
        #expect(capture.comparison.baseEndpoint.contentSetHash == "base-oid")
        #expect(capture.comparison.headEndpoint.kind == .workingTree)
        #expect(capture.comparison.changedFiles.map(\.path) == [fixture.filePath])
        #expect(baseResult.data == Data(fixture.baseContent.utf8))
        #expect(headResult.data == Data(fixture.workingContent.utf8))
        #expect(
            await fixture.gitClient.recordedContributionDiffRequests() == [
                GitContributionDiffRequest(
                    repositoryPath: fixture.repositoryPath,
                    target: .named("refs/heads/integration")
                )
            ]
        )
        #expect(await fixture.gitClient.recordedDiffRequests().isEmpty)
    }

    @Test("AgentStudioGit adapter qualifies moving contribution branch refs")
    func agentStudioGitAdapterQualifiesMovingContributionBranchRefs() async throws {
        let fixture = makeContributionAdapterFixture()
        let requests = [
            WorkspaceReviewContributionTarget.localDefaultBranch(
                branchName: "integration",
                basis: .commonCommit
            ),
            .branch(name: "stack/base", basis: .commonCommit),
            .originDefaultBranch(
                remoteName: "upstream",
                branchName: "integration",
                basis: .commonCommit
            ),
        ]

        for target in requests {
            _ = try await fixture.provider.captureContributionComparison(
                BridgeContributionComparisonRequest(
                    symbolicTarget: target,
                    baseEndpoint: fixture.baseEndpoint,
                    headEndpoint: fixture.headEndpoint,
                    reviewGenerationValue: 12
                )
            )
        }

        #expect(
            await fixture.gitClient.recordedContributionDiffRequests() == [
                GitContributionDiffRequest(
                    repositoryPath: fixture.repositoryPath,
                    target: .named("refs/heads/integration")
                ),
                GitContributionDiffRequest(
                    repositoryPath: fixture.repositoryPath,
                    target: .named("refs/heads/stack/base")
                ),
                GitContributionDiffRequest(
                    repositoryPath: fixture.repositoryPath,
                    target: .named("refs/remotes/upstream/integration")
                ),
            ]
        )
    }

    @Test("AgentStudioGit adapter compares an exact commit directly against the working tree")
    func agentStudioGitAdapterComparesExactCommitDirectlyAgainstWorkingTree() async throws {
        let fixture = makeContributionAdapterFixture()
        let oid = "0123456789abcdef0123456789abcdef01234567"

        let capture = try await fixture.provider.captureContributionComparison(
            BridgeContributionComparisonRequest(
                symbolicTarget: .commit(oid: oid),
                baseEndpoint: fixture.baseEndpoint,
                headEndpoint: fixture.headEndpoint,
                reviewGenerationValue: 12
            )
        )

        #expect(
            await fixture.gitClient.recordedDirectReviewComparisonRequests() == [
                GitDirectReviewComparisonRequest(
                    repositoryPath: fixture.repositoryPath,
                    target: .named(oid)
                )
            ]
        )
        #expect(await fixture.gitClient.recordedContributionDiffRequests().isEmpty)
        #expect(capture.baseRole == .selectedTarget)
        #expect(capture.baseOID == "target-oid")
    }

    @Test("AgentStudioGit adapter compares a branch tip directly against the working tree")
    func agentStudioGitAdapterComparesBranchTipDirectlyAgainstWorkingTree() async throws {
        let fixture = makeContributionAdapterFixture()

        let capture = try await fixture.provider.captureContributionComparison(
            BridgeContributionComparisonRequest(
                symbolicTarget: .branch(name: "review/selected-target", basis: .branchTip),
                baseEndpoint: fixture.baseEndpoint,
                headEndpoint: fixture.headEndpoint,
                reviewGenerationValue: 12
            )
        )

        #expect(
            await fixture.gitClient.recordedDirectReviewComparisonRequests() == [
                GitDirectReviewComparisonRequest(
                    repositoryPath: fixture.repositoryPath,
                    target: .named("refs/heads/review/selected-target")
                )
            ]
        )
        #expect(await fixture.gitClient.recordedContributionDiffRequests().isEmpty)
        #expect(capture.baseRole == .selectedTarget)
    }
}

private struct ContributionAdapterFixture {
    let repositoryPath: URL
    let filePath: String
    let baseContent: String
    let workingContent: String
    let gitClient: AgentStudioGitLocalClientFake
    let provider: BridgeGitReviewSourceProvider
    let baseEndpoint: BridgeSourceEndpoint
    let headEndpoint: BridgeSourceEndpoint
}

private func makeContributionAdapterFixture() -> ContributionAdapterFixture {
    let repositoryPath = URL(fileURLWithPath: "/tmp/agentstudio-git-contribution-test")
    let filePath = "Sources/App/View.swift"
    let baseContent = "base content"
    let workingContent = "working content"
    let repoId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let worktreeId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let snapshot = GitContributionDiffSnapshot(
        resolvedTarget: GitResolvedRevision(oid: "target-oid", shortName: "integration"),
        reviewedHead: GitResolvedRevision(oid: "head-oid", shortName: "feature"),
        contributionBase: GitResolvedRevision(oid: "base-oid", shortName: nil),
        diff: GitDiffSnapshot(
            files: [
                GitDiffFile(
                    fileId: "source",
                    path: filePath,
                    previousPath: nil,
                    changeKind: .modified,
                    oldContentHash: gitBlobSHA1ContentHash(baseContent),
                    newContentHash: gitBlobSHA1ContentHash(workingContent),
                    contentHashAlgorithm: "git-blob-sha1",
                    oldMode: 0o100644,
                    newMode: 0o100644,
                    additions: 1,
                    deletions: 1,
                    isBinary: false,
                    sizeBytes: Int64(workingContent.utf8.count)
                )
            ]
        )
    )
    let directReviewComparisonSnapshot = GitDirectReviewComparisonSnapshot(
        resolvedTarget: GitResolvedRevision(oid: "target-oid", shortName: nil),
        reviewedHead: GitResolvedRevision(oid: "head-oid", shortName: "feature"),
        diff: snapshot.diff
    )
    let gitClient = AgentStudioGitLocalClientFake(
        contributionDiffSnapshot: snapshot,
        directReviewComparisonSnapshot: directReviewComparisonSnapshot,
        contentByLocator: [
            GitContentLocator(target: .commit("base-oid"), path: filePath): gitContentPayload(baseContent),
            GitContentLocator(target: .workingTree, path: filePath): gitContentPayload(workingContent),
        ]
    )
    let provider = BridgeGitReviewSourceProvider(
        client: AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            client: gitClient,
            gitReadContext: makeBridgeGitReadContext(rootURL: repositoryPath)
        )
    )
    return ContributionAdapterFixture(
        repositoryPath: repositoryPath,
        filePath: filePath,
        baseContent: baseContent,
        workingContent: workingContent,
        gitClient: gitClient,
        provider: provider,
        baseEndpoint: BridgeSourceEndpoint(
            endpointId: "contribution-base",
            kind: .gitRef,
            repoId: repoId,
            worktreeId: worktreeId,
            label: "Contribution base",
            createdAtUnixMilliseconds: 10,
            contentSetHash: nil,
            providerIdentity: "integration"
        ),
        headEndpoint: BridgeSourceEndpoint(
            endpointId: "working-tree",
            kind: .workingTree,
            repoId: repoId,
            worktreeId: worktreeId,
            label: "Working tree",
            createdAtUnixMilliseconds: 10,
            contentSetHash: nil,
            providerIdentity: "working-tree:\(worktreeId.uuidString)"
        )
    )
}
