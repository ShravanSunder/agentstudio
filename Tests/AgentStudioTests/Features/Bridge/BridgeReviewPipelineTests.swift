import CryptoKit
import Foundation
import Testing

@testable import AgentStudioBridge
@testable import AgentStudioCore

struct BridgeReviewPipelineTests {
    @Test("shared construction build and bind leave staged and unstaged origins absent")
    func sharedConstructionBuildAndBindLeaveStagedAndUnstagedOriginsAbsent() async throws {
        struct Case {
            let baseEndpoint: BridgeSourceEndpoint
            let headEndpoint: BridgeSourceEndpoint
            let comparisonSemantics: BridgeReviewQuery.ComparisonSemantics
        }

        let reviewedHeadEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .gitRef)
        let indexEndpoint = makeBridgeEndpoint(endpointId: "index", kind: .index)
        let workingTreeEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
        let cases = [
            Case(
                baseEndpoint: reviewedHeadEndpoint,
                headEndpoint: indexEndpoint,
                comparisonSemantics: .indexDelta
            ),
            Case(
                baseEndpoint: indexEndpoint,
                headEndpoint: workingTreeEndpoint,
                comparisonSemantics: .workingTreeDelta
            ),
        ]

        for testCase in cases {
            let comparison = BridgeEndpointComparison(
                baseEndpoint: testCase.baseEndpoint,
                headEndpoint: testCase.headEndpoint,
                changedFiles: []
            )
            let client = BridgeGitReviewDataClientFake(comparison: comparison)
            let pipeline = BridgeReviewPipeline(provider: BridgeGitReviewSourceProvider(client: client))
            let request = BridgeReviewPipelineRequest(
                packageId: "package-\(testCase.comparisonSemantics.rawValue)",
                query: makeBridgeReviewQuery(
                    baseEndpointId: testCase.baseEndpoint.endpointId,
                    headEndpointId: testCase.headEndpoint.endpointId,
                    options: BridgeReviewQueryTestOptions(
                        comparisonSemantics: testCase.comparisonSemantics
                    )
                ),
                baseEndpoint: testCase.baseEndpoint,
                headEndpoint: testCase.headEndpoint,
                checkpointIds: [],
                reviewGeneration: 7,
                generatedAtUnixMilliseconds: 8
            )
            let freshnessKey = BridgeGitReadFreshnessKey(
                token: "narrow-\(testCase.comparisonSemantics.rawValue)"
            )

            let resolvedRequest = try await pipeline.resolveSharedConstructionRequest(
                request,
                freshnessKey: freshnessKey
            )
            let template = try await pipeline.buildSharedTemplate(
                request: resolvedRequest,
                baseEndpointKey: resolvedEndpointKey(testCase.baseEndpoint),
                headEndpointKey: resolvedEndpointKey(testCase.headEndpoint),
                freshnessKey: freshnessKey
            )
            let result = try await pipeline.bindSharedTemplate(
                template,
                request: resolvedRequest
            )

            #expect(resolvedRequest.comparisonOrigin == nil)
            #expect(result.package.comparisonOrigin == nil)
        }
    }

    @Test("staged comparison loads from resolved HEAD to index without an origin")
    func stagedComparisonLoadsFromResolvedHeadToIndexWithoutOrigin() async throws {
        let reviewedHeadEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .gitRef)
        let indexEndpoint = makeBridgeEndpoint(endpointId: "index", kind: .index)
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: reviewedHeadEndpoint,
                headEndpoint: indexEndpoint,
                changedFiles: []
            ),
            contentByHandleId: [:]
        )
        let request = BridgeReviewPipelineRequest(
            packageId: "package-staged",
            query: makeBridgeReviewQuery(
                baseEndpointId: reviewedHeadEndpoint.endpointId,
                headEndpointId: indexEndpoint.endpointId,
                options: BridgeReviewQueryTestOptions(comparisonSemantics: .indexDelta)
            ),
            baseEndpoint: reviewedHeadEndpoint,
            headEndpoint: indexEndpoint,
            checkpointIds: [],
            reviewGeneration: 7,
            generatedAtUnixMilliseconds: 8
        )

        let result = try await BridgeReviewPipeline(provider: provider).loadPackage(request)

        #expect(result.package.comparisonOrigin == nil)
        #expect(await provider.recordedComparisonRequestsCount() == 1)
    }

    @Test("unstaged comparison loads from index to working tree without an origin")
    func unstagedComparisonLoadsFromIndexToWorkingTreeWithoutOrigin() async throws {
        let indexEndpoint = makeBridgeEndpoint(endpointId: "index", kind: .index)
        let workingTreeEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: indexEndpoint,
                headEndpoint: workingTreeEndpoint,
                changedFiles: []
            ),
            contentByHandleId: [:]
        )
        let request = BridgeReviewPipelineRequest(
            packageId: "package-unstaged",
            query: makeBridgeReviewQuery(
                baseEndpointId: indexEndpoint.endpointId,
                headEndpointId: workingTreeEndpoint.endpointId,
                options: BridgeReviewQueryTestOptions(comparisonSemantics: .workingTreeDelta)
            ),
            baseEndpoint: indexEndpoint,
            headEndpoint: workingTreeEndpoint,
            checkpointIds: [],
            reviewGeneration: 7,
            generatedAtUnixMilliseconds: 8
        )

        let result = try await BridgeReviewPipeline(provider: provider).loadPackage(request)

        #expect(result.package.comparisonOrigin == nil)
        #expect(await provider.recordedComparisonRequestsCount() == 1)
    }

    @Test("resolved contribution builder rejects captured endpoint roles outside contribution base to working tree")
    func resolvedContributionBuilderRejectsCapturedEndpointRolesOutsideContributionBaseToWorkingTree() {
        let requestBase = makeBridgeEndpoint(endpointId: "target", kind: .gitRef)
        let requestHead = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
        let request = BridgeReviewPipelineRequest(
            packageId: "package-contribution",
            query: makeBridgeReviewQuery(
                baseEndpointId: requestBase.endpointId,
                headEndpointId: requestHead.endpointId
            ),
            baseEndpoint: requestBase,
            headEndpoint: requestHead,
            checkpointIds: [],
            reviewGeneration: 7,
            generatedAtUnixMilliseconds: 8
        )
        let symbolicTarget = WorkspaceReviewContributionTarget.branch(name: "integration")
        let invalidComparisons = [
            BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "target", kind: .index),
                headEndpoint: requestHead,
                changedFiles: []
            ),
            BridgeEndpointComparison(
                baseEndpoint: requestBase,
                headEndpoint: makeBridgeEndpoint(endpointId: "working-tree", kind: .index),
                changedFiles: []
            ),
        ]

        for invalidComparison in invalidComparisons {
            #expect(throws: BridgeProviderFailure.self) {
                _ = try BridgeResolvedContributionRequestBuilder.build(
                    request: request,
                    symbolicTarget: symbolicTarget,
                    capture: BridgeContributionComparisonCapture(
                        resolvedTargetOID: "target-oid",
                        reviewedHeadOID: "head-oid",
                        baseRole: .commonCommit,
                        baseOID: "base-oid",
                        comparison: invalidComparison
                    ),
                    reviewedSubjectLabel: nil
                )
            }
        }
    }

    @Test("resolved contribution builder rejects captured endpoint identities outside the request")
    func resolvedContributionBuilderRejectsCapturedEndpointIdentitiesOutsideTheRequest() {
        let requestBase = makeBridgeEndpoint(endpointId: "target", kind: .gitRef)
        let requestHead = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
        let request = BridgeReviewPipelineRequest(
            packageId: "package-contribution",
            query: makeBridgeReviewQuery(
                baseEndpointId: requestBase.endpointId,
                headEndpointId: requestHead.endpointId
            ),
            baseEndpoint: requestBase,
            headEndpoint: requestHead,
            checkpointIds: [],
            reviewGeneration: 7,
            generatedAtUnixMilliseconds: 8
        )

        #expect(throws: BridgeProviderFailure.self) {
            _ = try BridgeResolvedContributionRequestBuilder.build(
                request: request,
                symbolicTarget: .branch(name: "integration"),
                capture: BridgeContributionComparisonCapture(
                    resolvedTargetOID: "target-oid",
                    reviewedHeadOID: "head-oid",
                    baseRole: .commonCommit,
                    baseOID: "base-oid",
                    comparison: BridgeEndpointComparison(
                        baseEndpoint: makeBridgeEndpoint(endpointId: "other-target", kind: .gitRef),
                        headEndpoint: requestHead,
                        changedFiles: []
                    )
                ),
                reviewedSubjectLabel: nil
            )
        }
    }

    @Test("prepared contribution enters package assembly without endpoint replay")
    func preparedContributionEntersPackageAssemblyWithoutEndpointReplay() async throws {
        let targetEndpoint = makeBridgeEndpoint(endpointId: "target", kind: .gitRef)
        let workingTreeEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
        let changedFile = makeBridgeEndpointChangedFile(
            fileId: "contribution",
            path: "Sources/Feature.swift",
            sizeBytes: 12
        )
        let preparedComparison = BridgeEndpointComparison(
            baseEndpoint: targetEndpoint,
            headEndpoint: workingTreeEndpoint,
            changedFiles: [changedFile]
        )
        let client = BridgeGitReviewDataClientFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: targetEndpoint,
                headEndpoint: workingTreeEndpoint,
                changedFiles: []
            )
        )
        let request = try BridgeResolvedContributionRequestBuilder.build(
            request: BridgeReviewPipelineRequest(
                packageId: "package-contribution",
                query: makeBridgeReviewQuery(
                    baseEndpointId: targetEndpoint.endpointId,
                    headEndpointId: workingTreeEndpoint.endpointId
                ),
                baseEndpoint: targetEndpoint,
                headEndpoint: workingTreeEndpoint,
                checkpointIds: [],
                reviewGeneration: 7,
                generatedAtUnixMilliseconds: 8
            ),
            symbolicTarget: .branch(name: "integration"),
            capture: BridgeContributionComparisonCapture(
                resolvedTargetOID: "target-oid",
                reviewedHeadOID: "head-oid",
                baseRole: .commonCommit,
                baseOID: "base-oid",
                comparison: preparedComparison
            ),
            reviewedSubjectLabel: "feature/stack"
        )

        let pipeline = BridgeReviewPipeline(provider: BridgeGitReviewSourceProvider(client: client))
        let resolvedRequest = try await pipeline.resolveSharedConstructionRequest(
            request,
            freshnessKey: BridgeGitReadFreshnessKey(token: "prepared-contribution")
        )
        let result = try await pipeline.loadPackage(resolvedRequest)

        #expect(resolvedRequest == request)
        #expect(await client.recordedSharedEndpointResolutionRequestsCount() == 0)
        #expect(await client.recordedSharedComparisonRequestsCount() == 0)
        #expect(await client.recordedComparisonRequestsCount() == 0)
        #expect(result.package.orderedItemIds == ["item-contribution"])
        #expect(result.package.reviewedSubjectLabel == "feature/stack")
        #expect(
            result.package.comparisonOrigin
                == BridgeReviewComparisonOrigin.contribution(
                    BridgeReviewContributionOrigin(
                        symbolicTarget: .branch(name: "integration"),
                        resolvedTargetOID: "target-oid",
                        reviewedHeadOID: "head-oid",
                        baseRole: .commonCommit,
                        baseOID: "base-oid"
                    )
                )
        )
    }

    @Test("pipeline builds package off main actor and returns handles without loading content")
    func pipelineBuildsPackageOffMainActorAndReturnsHandlesWithoutLoadingContent() async throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .promptCheckpoint)
        let changedFile = makeBridgeEndpointChangedFile(
            fileId: "source",
            path: "Sources/App/View.swift",
            sizeBytes: 100,
            oldContentHash: bridgeSHA256ContentHash("old"),
            newContentHash: bridgeSHA256ContentHash("new")
        )
        let headHandle = BridgeReviewPackageBuilder.contentHandle(
            for: changedFile,
            endpoint: headEndpoint,
            role: .head,
            reviewGeneration: 5
        )
        let baseHandle = BridgeReviewPackageBuilder.contentHandle(
            for: changedFile,
            endpoint: baseEndpoint,
            role: .base,
            reviewGeneration: 5
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [changedFile]
            ),
            contentByHandleId: [
                baseHandle.handleId: makeContentResult(handle: baseHandle, data: "old"),
                headHandle.handleId: makeContentResult(handle: headHandle, data: "new"),
            ]
        )
        let contentLoaderCache = BridgeReviewContentLoaderCache(provider: provider)
        let pipeline = BridgeReviewPipeline(provider: provider)
        let productAdmission = try BridgeProductAdmissionTestContext.make()

        let result = try await pipeline.loadPackage(
            BridgeReviewPipelineRequest(
                packageId: "package",
                query: makeBridgeReviewQuery(
                    baseEndpointId: baseEndpoint.endpointId,
                    headEndpointId: headEndpoint.endpointId
                ),
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                checkpointIds: ["checkpoint"],
                reviewGeneration: 5,
                generatedAtUnixMilliseconds: 6
            )
        )

        #expect(result.package.packageId == "package")
        #expect(result.package.orderedItemIds == ["item-source"])
        #expect(await provider.recordedContentRequestsCount() == 0)
        let loaded = try await contentLoaderCache.load(
            handle: headHandle,
            productAdmission: productAdmission.context
        )
        #expect(loaded.data == Data("new".utf8))
    }

    @Test("pipeline registers content for hidden package items")
    func pipelineRegistersContentForHiddenPackageItems() async throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .promptCheckpoint)
        let visibleFile = makeBridgeEndpointChangedFile(
            fileId: "source",
            path: "Sources/App/View.swift",
            sizeBytes: 100,
            oldContentHash: bridgeSHA256ContentHash("old"),
            newContentHash: bridgeSHA256ContentHash("new")
        )
        let hiddenFile = makeBridgeEndpointChangedFile(
            fileId: "generated",
            path: "Sources/Generated/API.swift",
            sizeBytes: 100,
            oldContentHash: bridgeSHA256ContentHash("old-hidden"),
            newContentHash: bridgeSHA256ContentHash("new-hidden")
        )
        let visibleHeadHandle = BridgeReviewPackageBuilder.contentHandle(
            for: visibleFile,
            endpoint: headEndpoint,
            role: .head,
            reviewGeneration: 5
        )
        let visibleBaseHandle = BridgeReviewPackageBuilder.contentHandle(
            for: visibleFile,
            endpoint: baseEndpoint,
            role: .base,
            reviewGeneration: 5
        )
        let hiddenHeadHandle = BridgeReviewPackageBuilder.contentHandle(
            for: hiddenFile,
            endpoint: headEndpoint,
            role: .head,
            reviewGeneration: 5
        )
        let hiddenBaseHandle = BridgeReviewPackageBuilder.contentHandle(
            for: hiddenFile,
            endpoint: baseEndpoint,
            role: .base,
            reviewGeneration: 5
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [visibleFile, hiddenFile]
            ),
            contentByHandleId: [
                visibleBaseHandle.handleId: makeContentResult(handle: visibleBaseHandle, data: "old"),
                visibleHeadHandle.handleId: makeContentResult(handle: visibleHeadHandle, data: "new"),
                hiddenBaseHandle.handleId: makeContentResult(handle: hiddenBaseHandle, data: "old-hidden"),
                hiddenHeadHandle.handleId: makeContentResult(handle: hiddenHeadHandle, data: "new-hidden"),
            ]
        )
        let contentLoaderCache = BridgeReviewContentLoaderCache(provider: provider)
        let pipeline = BridgeReviewPipeline(provider: provider)
        let productAdmission = try BridgeProductAdmissionTestContext.make()

        let result = try await pipeline.loadPackage(
            BridgeReviewPipelineRequest(
                packageId: "package",
                query: makeBridgeReviewQuery(
                    baseEndpointId: baseEndpoint.endpointId,
                    headEndpointId: headEndpoint.endpointId,
                    filter: BridgeViewFilter(excludedFileClasses: [.generated])
                ),
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                checkpointIds: ["checkpoint"],
                reviewGeneration: 5,
                generatedAtUnixMilliseconds: 6
            )
        )

        #expect(result.package.orderedItemIds == ["item-source", "item-generated"])
        #expect(result.registeredContentHandles.contains(hiddenHeadHandle))
        let loaded = try await contentLoaderCache.load(
            handle: hiddenHeadHandle,
            productAdmission: productAdmission.context
        )
        #expect(loaded.data == Data("new-hidden".utf8))
    }

    @Test("pipeline does not perform content IO for large metadata packages")
    func pipelineDoesNotPerformContentIOForLargeMetadataPackages() async throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .promptCheckpoint)
        let changedFiles = (0..<1000).map { index in
            makeBridgeEndpointChangedFile(
                fileId: "source-\(index)",
                path: "Sources/App/View\(index).swift",
                sizeBytes: 100
            )
        }
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: changedFiles
            ),
            contentByHandleId: [:]
        )
        let pipeline = BridgeReviewPipeline(provider: provider)

        let result = try await pipeline.loadPackage(
            BridgeReviewPipelineRequest(
                packageId: "package",
                query: makeBridgeReviewQuery(
                    baseEndpointId: baseEndpoint.endpointId,
                    headEndpointId: headEndpoint.endpointId
                ),
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                checkpointIds: ["checkpoint"],
                reviewGeneration: 5,
                generatedAtUnixMilliseconds: 6
            )
        )

        #expect(result.package.itemsById.count == 1000)
        #expect(await provider.recordedContentRequestsCount() == 0)
    }

    @Test("pipeline uses tree reader for browse tree queries")
    func pipelineUsesTreeReaderForBrowseTreeQueries() async throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let treeDescriptor = makeBridgeReviewItemDescriptor(
            itemId: "item-tree",
            path: "Sources/App/Tree.swift",
            fileClass: .source
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: []
            ),
            contentByHandleId: [:],
            treeDescriptors: [treeDescriptor]
        )
        let pipeline = BridgeReviewPipeline(provider: provider)

        let result = try await pipeline.loadPackage(
            BridgeReviewPipelineRequest(
                packageId: "package",
                query: makeBridgeReviewQuery(
                    baseEndpointId: baseEndpoint.endpointId,
                    headEndpointId: headEndpoint.endpointId,
                    options: BridgeReviewQueryTestOptions(queryKind: .browseTree)
                ),
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                checkpointIds: [],
                reviewGeneration: 5,
                generatedAtUnixMilliseconds: 6
            )
        )

        #expect(result.package.orderedItemIds == ["item-tree"])
        #expect(await provider.recordedComparisonRequestsCount() == 0)
        #expect(await provider.recordedTreeReadRequestsCount() == 1)
    }

    @Test("pipeline uses compare semantics for modified open file queries")
    func pipelineUsesCompareSemanticsForModifiedOpenFileQueries() async throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let changedFile = makeBridgeEndpointChangedFile(
            fileId: "open",
            path: "Sources/App/Open.swift",
            sizeBytes: 100,
            oldContentHash: bridgeSHA256ContentHash("old"),
            newContentHash: bridgeSHA256ContentHash("new")
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [changedFile]
            ),
            contentByHandleId: [:],
            itemDescriptorByPath: [
                "Sources/App/Open.swift": makeBridgeReviewItemDescriptor(
                    itemId: "item-open-file",
                    path: "Sources/App/Open.swift",
                    fileClass: .source
                )
            ]
        )
        let pipeline = BridgeReviewPipeline(provider: provider)

        let result = try await pipeline.loadPackage(
            BridgeReviewPipelineRequest(
                packageId: "package",
                query: makeBridgeReviewQuery(
                    baseEndpointId: baseEndpoint.endpointId,
                    headEndpointId: headEndpoint.endpointId,
                    options: BridgeReviewQueryTestOptions(
                        queryKind: .openFile,
                        fileTarget: "Sources/App/Open.swift"
                    )
                ),
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                checkpointIds: [],
                reviewGeneration: 5,
                generatedAtUnixMilliseconds: 6
            )
        )

        let item = try #require(result.package.itemsById["item-open"])
        #expect(result.package.orderedItemIds == ["item-open"])
        #expect(item.itemKind == .diff)
        #expect(item.contentRoles.base != nil)
        #expect(item.contentRoles.head != nil)
        #expect(item.contentRoles.file == nil)
        #expect(await provider.recordedComparisonRequestsCount() == 1)
        #expect(await provider.recordedItemDescriptorRequestsCount() == 0)
    }

    @Test("pipeline falls back to item descriptor reader for open file queries outside the comparison")
    func pipelineFallsBackToItemDescriptorReaderForOpenFileQueriesOutsideComparison() async throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let itemDescriptor = makeBridgeReviewItemDescriptor(
            itemId: "item-open",
            path: "Sources/App/Open.swift",
            fileClass: .source
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: []
            ),
            contentByHandleId: [:],
            itemDescriptorByPath: ["Sources/App/Open.swift": itemDescriptor]
        )
        let pipeline = BridgeReviewPipeline(provider: provider)

        let result = try await pipeline.loadPackage(
            BridgeReviewPipelineRequest(
                packageId: "package",
                query: makeBridgeReviewQuery(
                    baseEndpointId: baseEndpoint.endpointId,
                    headEndpointId: headEndpoint.endpointId,
                    options: BridgeReviewQueryTestOptions(
                        queryKind: .openFile,
                        fileTarget: "Sources/App/Open.swift"
                    )
                ),
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                checkpointIds: [],
                reviewGeneration: 5,
                generatedAtUnixMilliseconds: 6
            )
        )

        #expect(result.package.orderedItemIds == ["item-open"])
        #expect(await provider.recordedComparisonRequestsCount() == 1)
        #expect(await provider.recordedItemDescriptorRequestsCount() == 1)
    }
}

private func resolvedEndpointKey(
    _ endpoint: BridgeSourceEndpoint
) -> BridgeResolvedReviewEndpointKey {
    let kind: BridgeResolvedReviewEndpointKindKey
    switch endpoint.kind {
    case .gitRef:
        kind = .gitObject
    case .workingTree:
        kind = .workingTree
    case .index:
        kind = .index
    case .promptCheckpoint, .sessionCheckpoint, .manualCheckpoint, .savedTimeWindowCheckpoint:
        kind = .checkpoint
    }
    return BridgeResolvedReviewEndpointKey(
        kind: kind,
        providerIdentity: endpoint.providerIdentity,
        contentIdentity: endpoint.contentSetHash ?? endpoint.providerIdentity
    )
}

func makeBridgeEndpoint(
    endpointId: String,
    kind: BridgeSourceEndpoint.Kind
) -> BridgeSourceEndpoint {
    BridgeSourceEndpoint(
        endpointId: endpointId,
        kind: kind,
        repoId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        worktreeId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        label: endpointId,
        createdAtUnixMilliseconds: 1,
        contentSetHash: "sha256:\(endpointId)",
        providerIdentity: endpointId
    )
}

func makeBridgeReviewQuery(
    baseEndpointId: String = "base",
    headEndpointId: String = "head",
    filter: BridgeViewFilter = BridgeViewFilter(),
    grouping: BridgeChangeGrouping = BridgeChangeGrouping(kind: .flat),
    options: BridgeReviewQueryTestOptions = BridgeReviewQueryTestOptions()
) -> BridgeReviewQuery {
    BridgeReviewQuery(
        queryId: "query",
        queryKind: options.queryKind,
        repoId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        worktreeId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        baseEndpointId: baseEndpointId,
        headEndpointId: headEndpointId,
        comparisonSemantics: options.comparisonSemantics,
        pathScope: options.pathScope,
        fileTarget: options.fileTarget,
        viewFilter: filter,
        grouping: grouping,
        provenanceFilter: BridgeProvenanceFilter()
    )
}

struct BridgeReviewQueryTestOptions {
    let queryKind: BridgeReviewQuery.Kind
    let comparisonSemantics: BridgeReviewQuery.ComparisonSemantics
    let fileTarget: String?
    let pathScope: [String]

    init(
        queryKind: BridgeReviewQuery.Kind = .compare,
        comparisonSemantics: BridgeReviewQuery.ComparisonSemantics = .checkpointDelta,
        fileTarget: String? = nil,
        pathScope: [String] = []
    ) {
        self.queryKind = queryKind
        self.comparisonSemantics = comparisonSemantics
        self.fileTarget = fileTarget
        self.pathScope = pathScope
    }
}

func makeBridgeContentHandle(
    itemId: String,
    role: BridgeContentHandle.Role,
    endpointId: String = "endpoint",
    reviewGeneration: BridgeReviewGeneration = 7,
    contentHash: String = bridgeSHA256ContentHash("content"),
    sizeBytes: Int = 100,
    isBinary: Bool = false
) -> BridgeContentHandle {
    let handleId = "handle-\(endpointId)-\(itemId)-\(role.rawValue)"
    return BridgeContentHandle(
        handleId: handleId,
        itemId: itemId,
        role: role,
        endpointId: endpointId,
        reviewGeneration: reviewGeneration,
        contentHash: contentHash,
        contentHashAlgorithm: "sha256",
        cacheKey: "\(endpointId):\(itemId):\(role.rawValue)",
        mimeType: "text/plain",
        language: nil,
        sizeBytes: sizeBytes,
        isBinary: isBinary
    )
}

func makeContentResult(handle: BridgeContentHandle, data: String) -> BridgeContentLoadResult {
    BridgeContentLoadResult(
        handle: handle,
        data: Data(data.utf8),
        mimeType: handle.mimeType,
        contentHash: handle.contentHash,
        contentHashAlgorithm: handle.contentHashAlgorithm
    )
}

func makeBridgeReviewItemDescriptor(
    itemId: String,
    path: String,
    fileClass: BridgeFileClass,
    contentRoles: BridgeReviewItemDescriptor.ContentRoles? = nil
) -> BridgeReviewItemDescriptor {
    let roles =
        contentRoles
        ?? BridgeReviewItemDescriptor.ContentRoles(
            head: makeBridgeContentHandle(itemId: itemId, role: .head)
        )
    return BridgeReviewItemDescriptor(
        itemId: itemId,
        itemKind: .diff,
        itemVersion: 9,
        basePath: path,
        headPath: path,
        changeKind: .modified,
        fileClass: fileClass,
        language: "swift",
        extension: "swift",
        sizeBytes: 100,
        baseContentHash: "sha256:old-\(itemId)",
        headContentHash: "sha256:new-\(itemId)",
        contentHashAlgorithm: "sha256",
        additions: 1,
        deletions: 1,
        isHiddenByDefault: fileClass == .generated,
        hiddenReason: fileClass == .generated ? "generated" : nil,
        reviewPriority: .normal,
        contentRoles: roles,
        cacheKey: roles.allHandles.map(\.cacheKey).joined(separator: "|"),
        provenance: BridgeProvenanceSummary(),
        annotationSummary: BridgeAnnotationSummary(threadCount: 0, unresolvedThreadCount: 0, commentCount: 0),
        reviewState: .unreviewed,
        collapsed: fileClass == .generated
    )
}

func makeBridgeEndpointChangedFile(
    fileId: String,
    path: String,
    sizeBytes: Int,
    changeKind: BridgeFileChangeKind = .modified,
    oldContentHash: String? = nil,
    newContentHash: String? = nil,
    oldMode: Int32? = nil,
    newMode: Int32? = nil
) -> BridgeEndpointChangedFile {
    BridgeEndpointChangedFile(
        fileId: fileId,
        path: path,
        oldPath: nil,
        changeKind: changeKind,
        language: "swift",
        fileExtension: "swift",
        sizeBytes: sizeBytes,
        oldContentHash: changeKind == .added ? nil : (oldContentHash ?? "sha256:old-\(fileId)"),
        newContentHash: changeKind == .deleted ? nil : (newContentHash ?? "sha256:new-\(fileId)"),
        contentHashAlgorithm: "sha256",
        oldMode: oldMode,
        newMode: newMode,
        additions: changeKind == .deleted ? 0 : 1,
        deletions: changeKind == .added ? 0 : 1,
        isBinary: false,
        mimeType: "text/x-swift"
    )
}

func bridgeSHA256ContentHash(_ content: String) -> String {
    let digest = SHA256.hash(data: Data(content.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "sha256:\(hex)"
}
