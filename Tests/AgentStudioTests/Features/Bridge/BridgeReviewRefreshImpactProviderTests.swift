import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge Review refresh impact provider")
struct BridgeReviewRefreshImpactProviderTests {
    @Test("ephemeral query and endpoint identities do not change semantic refresh scope")
    func ephemeralPublicationIdentitiesStillMeasureExactImpact() async throws {
        let displayed = makeImpactPackage(
            reviewGeneration: 1,
            revision: 1,
            reviewedHeadOID: "displayed-head",
            items: [],
            ephemeralIdentitySuffix: "displayed"
        )
        let candidate = makeImpactPackage(
            reviewGeneration: 2,
            revision: 2,
            reviewedHeadOID: "candidate-head",
            items: [],
            ephemeralIdentitySuffix: "candidate"
        )
        let dataClient = BridgeReviewRefreshImpactDataClientFake(
            commitRangeCount: .atLeastLimit(10),
            diff: GitDiffSnapshot(files: [])
        )
        let provider = BridgeReviewRefreshImpactProvider(dataClient: dataClient)

        let impact = try await provider.measure(
            displayedPackage: displayed,
            candidatePackage: candidate,
            candidateGeneration: candidate.reviewGeneration
        )

        #expect(impact.newlyImportedCommitCount == 10)
        #expect(impact.preDeliveryPresentationClass == .promoted(reason: .commits))
        #expect(await dataClient.requests().commitRange != nil)
    }

    @Test(
        "meaningful semantic source-scope changes promote unknown",
        arguments: ImpactSemanticScopeVariant.allCases
    )
    func meaningfulSemanticScopeChangesPromoteUnknown(
        variant: ImpactSemanticScopeVariant
    ) async throws {
        let displayed = makeImpactPackage(
            reviewGeneration: 1,
            revision: 1,
            reviewedHeadOID: "displayed-head",
            items: []
        )
        let candidate = makeImpactPackage(
            reviewGeneration: 2,
            revision: 2,
            reviewedHeadOID: "candidate-head",
            items: [],
            semanticScopeVariant: variant
        )
        let dataClient = BridgeReviewRefreshImpactDataClientFake(
            commitRangeCount: .atLeastLimit(10),
            diff: GitDiffSnapshot(files: [])
        )
        let provider = BridgeReviewRefreshImpactProvider(dataClient: dataClient)

        let impact = try await provider.measure(
            displayedPackage: displayed,
            candidatePackage: candidate,
            candidateGeneration: candidate.reviewGeneration
        )

        #expect(impact.preDeliveryPresentationClass == .promoted(reason: .unknown))
        #expect(await dataClient.requests().commitRange == nil)
    }

    @Test(
        "classifies exact threshold boundaries",
        arguments: [
            (9, 24, 500, 499, BridgeReviewPreDeliveryPresentationClass.ordinary),
            (10, 1, 1, 1, .promoted(reason: .commits)),
            (1, 25, 1, 1, .promoted(reason: .files)),
            (1, 1, 500, 500, .promoted(reason: .lines)),
        ]
    )
    func classifiesThresholdBoundaries(
        commitCount: Int,
        fileCount: Int,
        addedLineCount: Int,
        deletedLineCount: Int,
        expectedClass: BridgeReviewPreDeliveryPresentationClass
    ) {
        let impact = BridgeReviewRefreshImpact.exact(
            newlyImportedCommitCount: commitCount,
            affectedFileCount: fileCount,
            addedLineCount: addedLineCount,
            deletedLineCount: deletedLineCount,
            affectedStableFileIdentities: ["stable-file"]
        )

        #expect(impact.preDeliveryPresentationClass == expectedClass)
    }

    @Test("measures the displayed publication to candidate and maps rename and delete identities on both sides")
    func measuresDisplayedToCandidateWithBothIdentitySides() async throws {
        let displayed = makeImpactPackage(
            reviewGeneration: 1,
            revision: 1,
            reviewedHeadOID: "displayed-head",
            items: [
                impactItem(itemId: "displayed-renamed", basePath: "old.swift", headPath: "old.swift"),
                impactItem(itemId: "displayed-deleted", basePath: "deleted.swift", headPath: "deleted.swift"),
            ]
        )
        let candidate = makeImpactPackage(
            reviewGeneration: 3,
            revision: 3,
            reviewedHeadOID: "candidate-head",
            items: [
                impactItem(itemId: "candidate-renamed", basePath: "old.swift", headPath: "new.swift"),
                impactItem(itemId: "candidate-deleted", basePath: "deleted.swift", headPath: nil),
            ]
        )
        let dataClient = BridgeReviewRefreshImpactDataClientFake(
            commitRangeCount: .exact(2),
            diff: GitDiffSnapshot(
                files: [
                    impactDiffFile(
                        fileId: "rename",
                        path: "new.swift",
                        previousPath: "old.swift",
                        changeKind: .renamed,
                        additions: 4,
                        deletions: 2
                    ),
                    impactDiffFile(
                        fileId: "delete",
                        path: "deleted.swift",
                        previousPath: nil,
                        changeKind: .deleted,
                        additions: 0,
                        deletions: 3
                    ),
                ]
            )
        )
        let provider = BridgeReviewRefreshImpactProvider(dataClient: dataClient)

        let impact = try await provider.measure(
            displayedPackage: displayed,
            candidatePackage: candidate,
            candidateGeneration: candidate.reviewGeneration
        )

        #expect(impact.newlyImportedCommitCount == 2)
        #expect(impact.affectedFileCount == 2)
        #expect(impact.addedLineCount == 4)
        #expect(impact.deletedLineCount == 5)
        #expect(
            impact.affectedStableFileIdentities == [
                "candidate-deleted",
                "candidate-renamed",
                "displayed-deleted",
                "displayed-renamed",
            ]
        )
        let requests = await dataClient.requests()
        #expect(requests.commitRange?.base == .named("displayed-head"))
        #expect(requests.commitRange?.candidate == .named("candidate-head"))
        #expect(requests.commitRange?.maximumCount == 10)
        #expect(requests.commitRange?.maximumTraversalCount == 256)
        #expect(requests.diffImpact?.base == .commit("displayed-head"))
        #expect(requests.diffImpact?.compare == .commit("candidate-head"))
        #expect(requests.diffImpact?.maximumChangedFileCount == 25)
        #expect(requests.diffImpact?.maximumChangedLineCount == 1000)
        #expect(requests.diffImpact?.maximumDiffableBlobByteCount == Int64(1 * 1024 * 1024))
    }

    @Test("bounded or indeterminate Git facts promote conservatively")
    func boundedOrIndeterminateGitFactsPromoteConservatively() async throws {
        let displayed = makeImpactPackage(
            reviewGeneration: 1,
            revision: 1,
            reviewedHeadOID: "displayed-head",
            items: [impactItem(itemId: "displayed-file", basePath: "file.swift", headPath: "file.swift")]
        )
        let candidate = makeImpactPackage(
            reviewGeneration: 2,
            revision: 2,
            reviewedHeadOID: "candidate-head",
            items: [impactItem(itemId: "candidate-file", basePath: "file.swift", headPath: "file.swift")]
        )
        let cases: [(GitCommitRangeCount, GitDiffImpactSummary)] = [
            (
                .traversalLimitReached(256),
                exactImpactSummary(paths: [], addedLineCount: 0, deletedLineCount: 0)
            ),
            (
                .exact(1),
                GitDiffImpactSummary(
                    changedPaths: [GitDiffImpactPath(currentPath: "file.swift", previousPath: nil)],
                    pathsAreComplete: true,
                    changedFileCount: .exact(1),
                    changedLineCount: .indeterminate,
                    addedLineCount: nil,
                    deletedLineCount: nil
                )
            ),
        ]

        for (commitRangeCount, diffImpact) in cases {
            let provider = BridgeReviewRefreshImpactProvider(
                dataClient: BridgeReviewRefreshImpactDataClientFake(
                    commitRangeCount: commitRangeCount,
                    diffImpact: diffImpact
                )
            )

            let impact = try await provider.measure(
                displayedPackage: displayed,
                candidatePackage: candidate,
                candidateGeneration: candidate.reviewGeneration
            )

            #expect(impact.preDeliveryPresentationClass == .promoted(reason: .unknown))
            #expect(impact.affectedStableFileIdentities.isEmpty)
        }
    }

    @Test("unrelated or incomplete source facts use symbolic promoted unknown affectedness")
    func promotesUnknownForUnrelatedSourceFacts() async throws {
        let displayed = makeImpactPackage(
            reviewGeneration: 1,
            revision: 1,
            reviewedHeadOID: "displayed-head",
            items: [impactItem(itemId: "displayed-file", basePath: "file.swift", headPath: "file.swift")]
        )
        let candidate = makeImpactPackage(
            reviewGeneration: 2,
            revision: 2,
            reviewedHeadOID: "candidate-head",
            items: [impactItem(itemId: "candidate-file", basePath: "file.swift", headPath: "file.swift")]
        )
        let provider = BridgeReviewRefreshImpactProvider(
            dataClient: BridgeReviewRefreshImpactDataClientFake(
                commitRangeCount: .unrelated,
                diff: GitDiffSnapshot(files: [])
            )
        )

        let impact = try await provider.measure(
            displayedPackage: displayed,
            candidatePackage: candidate,
            candidateGeneration: candidate.reviewGeneration
        )

        #expect(impact.preDeliveryPresentationClass == .promoted(reason: .unknown))
        #expect(impact.newlyImportedCommitCount == nil)
        #expect(impact.affectedFileCount == nil)
        #expect(impact.addedLineCount == nil)
        #expect(impact.deletedLineCount == nil)
        #expect(impact.affectedStableFileIdentities.isEmpty)
    }

    @Test("carries the capped commit count as a conservative promotion lower bound")
    func carriesCappedCommitCountAsLowerBound() async throws {
        let displayed = makeImpactPackage(
            reviewGeneration: 1,
            revision: 1,
            reviewedHeadOID: "displayed-head",
            items: []
        )
        let candidate = makeImpactPackage(
            reviewGeneration: 2,
            revision: 2,
            reviewedHeadOID: "candidate-head",
            items: []
        )
        let provider = BridgeReviewRefreshImpactProvider(
            dataClient: BridgeReviewRefreshImpactDataClientFake(
                commitRangeCount: .atLeastLimit(10),
                diff: GitDiffSnapshot(files: [])
            )
        )

        let impact = try await provider.measure(
            displayedPackage: displayed,
            candidatePackage: candidate,
            candidateGeneration: candidate.reviewGeneration
        )

        #expect(impact.newlyImportedCommitCount == 10)
        #expect(impact.preDeliveryPresentationClass == .promoted(reason: .commits))
    }

    @Test("provider failure promotes unknown while cancellation remains stale control flow")
    func separatesUnknownFailureFromCancellation() async throws {
        let displayed = makeImpactPackage(
            reviewGeneration: 1,
            revision: 1,
            reviewedHeadOID: "displayed-head",
            items: [impactItem(itemId: "displayed-file", basePath: "file.swift", headPath: "file.swift")]
        )
        let candidate = makeImpactPackage(
            reviewGeneration: 2,
            revision: 2,
            reviewedHeadOID: "candidate-head",
            items: [impactItem(itemId: "candidate-file", basePath: "file.swift", headPath: "file.swift")]
        )
        let failedProvider = BridgeReviewRefreshImpactProvider(
            dataClient: BridgeReviewRefreshImpactDataClientFake(
                commitRangeCount: .exact(1),
                diff: GitDiffSnapshot(files: []),
                injectedFailure: .failed
            )
        )
        let cancelledProvider = BridgeReviewRefreshImpactProvider(
            dataClient: BridgeReviewRefreshImpactDataClientFake(
                commitRangeCount: .exact(1),
                diff: GitDiffSnapshot(files: []),
                injectedFailure: .cancelled
            )
        )

        let failedImpact = try await failedProvider.measure(
            displayedPackage: displayed,
            candidatePackage: candidate,
            candidateGeneration: candidate.reviewGeneration
        )

        #expect(failedImpact.preDeliveryPresentationClass == .promoted(reason: .unknown))
        await #expect(throws: CancellationError.self) {
            _ = try await cancelledProvider.measure(
                displayedPackage: displayed,
                candidatePackage: candidate,
                candidateGeneration: candidate.reviewGeneration
            )
        }
    }
}

private enum BridgeReviewRefreshImpactInjectedFailure: Error, Sendable {
    case cancelled
    case failed
}

private actor BridgeReviewRefreshImpactDataClientFake: BridgeReviewRefreshImpactDataClient {
    nonisolated let repositoryPath = URL(fileURLWithPath: "/repository")

    struct Requests: Sendable {
        let commitRange: GitCommitRangeCountRequest?
        let diffImpact: GitDiffImpactSummaryRequest?
    }

    private let commitRangeCount: GitCommitRangeCount
    private let diffImpactSummary: GitDiffImpactSummary
    private let injectedFailure: BridgeReviewRefreshImpactInjectedFailure?
    private var commitRangeRequest: GitCommitRangeCountRequest?
    private var diffImpactRequest: GitDiffImpactSummaryRequest?

    init(
        commitRangeCount: GitCommitRangeCount,
        diff: GitDiffSnapshot,
        injectedFailure: BridgeReviewRefreshImpactInjectedFailure? = nil
    ) {
        self.commitRangeCount = commitRangeCount
        self.diffImpactSummary = impactSummary(diff: diff)
        self.injectedFailure = injectedFailure
    }

    init(
        commitRangeCount: GitCommitRangeCount,
        diffImpact: GitDiffImpactSummary,
        injectedFailure: BridgeReviewRefreshImpactInjectedFailure? = nil
    ) {
        self.commitRangeCount = commitRangeCount
        self.diffImpactSummary = diffImpact
        self.injectedFailure = injectedFailure
    }

    func countCommitRange(
        _ request: GitCommitRangeCountRequest,
        candidateGeneration _: BridgeReviewGeneration
    ) async throws -> GitCommitRangeCount {
        commitRangeRequest = request
        if injectedFailure == .cancelled { throw CancellationError() }
        if injectedFailure == .failed { throw BridgeReviewRefreshImpactInjectedFailure.failed }
        return commitRangeCount
    }

    func summarizeDiffImpact(
        _ request: GitDiffImpactSummaryRequest,
        candidateGeneration _: BridgeReviewGeneration
    ) async throws -> GitDiffImpactSummary {
        diffImpactRequest = request
        return diffImpactSummary
    }

    func requests() -> Requests {
        Requests(commitRange: commitRangeRequest, diffImpact: diffImpactRequest)
    }
}

private func impactSummary(diff: GitDiffSnapshot) -> GitDiffImpactSummary {
    let addedLineCount = diff.files.reduce(0) { $0 + $1.additions }
    let deletedLineCount = diff.files.reduce(0) { $0 + $1.deletions }
    return exactImpactSummary(
        paths: diff.files.map { file in
            GitDiffImpactPath(
                currentPath: file.changeKind == .deleted ? nil : file.path,
                previousPath: file.changeKind == .renamed || file.changeKind == .deleted
                    ? (file.previousPath ?? file.path)
                    : nil
            )
        },
        addedLineCount: addedLineCount,
        deletedLineCount: deletedLineCount
    )
}

private func exactImpactSummary(
    paths: [GitDiffImpactPath],
    addedLineCount: Int,
    deletedLineCount: Int
) -> GitDiffImpactSummary {
    GitDiffImpactSummary(
        changedPaths: paths,
        pathsAreComplete: true,
        changedFileCount: .exact(paths.count),
        changedLineCount: .exact(addedLineCount + deletedLineCount),
        addedLineCount: addedLineCount,
        deletedLineCount: deletedLineCount
    )
}

private func makeImpactPackage(
    reviewGeneration: BridgeReviewGeneration,
    revision: Int,
    reviewedHeadOID: String,
    items: [BridgeReviewItemDescriptor],
    ephemeralIdentitySuffix: String = "stable",
    semanticScopeVariant: ImpactSemanticScopeVariant? = nil
) -> BridgeReviewPackage {
    let defaultRepoId = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let defaultWorktreeId = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    let repoId =
        semanticScopeVariant == .repoId
        ? UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        : defaultRepoId
    let worktreeId =
        semanticScopeVariant == .worktreeId
        ? UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
        : defaultWorktreeId
    let viewFilter =
        semanticScopeVariant == .viewFilter
        ? BridgeViewFilter(showHiddenFiles: true)
        : BridgeViewFilter()
    let grouping =
        semanticScopeVariant == .grouping
        ? BridgeChangeGrouping(kind: .flat)
        : BridgeChangeGrouping(kind: .folder)
    let provenanceFilter =
        semanticScopeVariant == .provenanceFilter
        ? BridgeProvenanceFilter(sourceKinds: [.filesystemWatch])
        : BridgeProvenanceFilter()
    let baseEndpoint = BridgeSourceEndpoint(
        endpointId: "impact-base-\(ephemeralIdentitySuffix)",
        kind: .gitRef,
        repoId: repoId,
        worktreeId: worktreeId,
        label: "main",
        createdAtUnixMilliseconds: 1,
        contentSetHash: "base-oid",
        providerIdentity: "base-oid"
    )
    let headEndpoint = BridgeSourceEndpoint(
        endpointId: "impact-head-\(ephemeralIdentitySuffix)",
        kind: .workingTree,
        repoId: repoId,
        worktreeId: worktreeId,
        label: "working tree",
        createdAtUnixMilliseconds: 1,
        contentSetHash: reviewedHeadOID,
        providerIdentity: "working-tree"
    )
    return BridgeReviewPackage(
        packageId: "impact-package",
        schemaVersion: 1,
        reviewGeneration: reviewGeneration,
        revision: revision,
        query: BridgeReviewQuery(
            queryId: "impact-query-\(ephemeralIdentitySuffix)",
            queryKind: semanticScopeVariant == .queryKind ? .openFile : .compare,
            repoId: repoId,
            worktreeId: worktreeId,
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId,
            comparisonSemantics: semanticScopeVariant == .comparisonSemantics
                ? .threeDot
                : .workingTreeDelta,
            pathScope: semanticScopeVariant == .pathScope ? ["Sources"] : [],
            fileTarget: semanticScopeVariant == .fileTarget ? "Sources/App.swift" : nil,
            viewFilter: viewFilter,
            grouping: grouping,
            provenanceFilter: provenanceFilter
        ),
        baseEndpoint: baseEndpoint,
        headEndpoint: headEndpoint,
        orderedItemIds: items.map(\.itemId),
        itemsById: Dictionary(uniqueKeysWithValues: items.map { ($0.itemId, $0) }),
        groups: [],
        summary: BridgeReviewPackageSummary(
            filesChanged: items.count,
            additions: items.reduce(0) { $0 + $1.additions },
            deletions: items.reduce(0) { $0 + $1.deletions },
            visibleFileCount: items.count,
            hiddenFileCount: 0
        ),
        filterState: viewFilter,
        generatedAtUnixMilliseconds: 1,
        comparisonOrigin: .contribution(
            BridgeReviewContributionOrigin(
                symbolicTarget: semanticScopeVariant == .symbolicTarget
                    ? .branch(name: "release")
                    : .branch(name: "main"),
                resolvedTargetOID: "target-oid",
                reviewedHeadOID: reviewedHeadOID,
                baseRole: .commonCommit,
                baseOID: "base-oid"
            )
        )
    )
}

enum ImpactSemanticScopeVariant: CaseIterable, Sendable {
    case repoId
    case worktreeId
    case queryKind
    case comparisonSemantics
    case pathScope
    case fileTarget
    case viewFilter
    case grouping
    case provenanceFilter
    case symbolicTarget
}

private func impactItem(
    itemId: String,
    basePath: String?,
    headPath: String?
) -> BridgeReviewItemDescriptor {
    BridgeReviewItemDescriptor(
        itemId: itemId,
        itemKind: .diff,
        itemVersion: 1,
        basePath: basePath,
        headPath: headPath,
        changeKind: headPath == nil ? .deleted : (basePath == headPath ? .modified : .renamed),
        fileClass: .source,
        language: "swift",
        extension: "swift",
        sizeBytes: 1,
        baseContentHash: "base-\(itemId)",
        headContentHash: headPath == nil ? nil : "head-\(itemId)",
        contentHashAlgorithm: "git-blob-sha1",
        additions: 1,
        deletions: headPath == nil ? 1 : 0,
        isHiddenByDefault: false,
        hiddenReason: nil,
        reviewPriority: .normal,
        contentRoles: .init(),
        cacheKey: "cache-\(itemId)",
        provenance: BridgeProvenanceSummary(),
        annotationSummary: BridgeAnnotationSummary(threadCount: 0, unresolvedThreadCount: 0, commentCount: 0),
        reviewState: .unreviewed,
        collapsed: false
    )
}

private func impactDiffFile(
    fileId: String,
    path: String,
    previousPath: String?,
    changeKind: GitDiffChangeKind,
    additions: Int,
    deletions: Int
) -> GitDiffFile {
    GitDiffFile(
        fileId: fileId,
        path: path,
        previousPath: previousPath,
        changeKind: changeKind,
        oldContentHash: "old-\(fileId)",
        newContentHash: changeKind == .deleted ? nil : "new-\(fileId)",
        contentHashAlgorithm: "git-blob-sha1",
        oldMode: 0o100644,
        newMode: changeKind == .deleted ? nil : 0o100644,
        additions: additions,
        deletions: deletions,
        isBinary: false,
        sizeBytes: 1
    )
}
