import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

struct BridgeReviewPipelineTests {
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
        let contentStore = BridgeContentStore(provider: provider)
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

        #expect(result.package.packageId == "package")
        #expect(result.package.orderedItemIds == ["item-source"])
        #expect(await provider.recordedContentRequestsCount() == 0)
        await contentStore.activate(handles: result.registeredContentHandles, reviewGeneration: 5)
        let loaded = try await contentStore.load(handleId: headHandle.handleId, requestedGeneration: 5)
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
        let contentStore = BridgeContentStore(provider: provider)
        let pipeline = BridgeReviewPipeline(provider: provider)

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
        await contentStore.activate(handles: result.registeredContentHandles, reviewGeneration: 5)
        let loaded = try await contentStore.load(handleId: hiddenHeadHandle.handleId, requestedGeneration: 5)
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
        comparisonSemantics: .checkpointDelta,
        pathScope: options.pathScope,
        fileTarget: options.fileTarget,
        viewFilter: filter,
        grouping: grouping,
        provenanceFilter: BridgeProvenanceFilter()
    )
}

struct BridgeReviewQueryTestOptions {
    let queryKind: BridgeReviewQuery.Kind
    let fileTarget: String?
    let pathScope: [String]

    init(
        queryKind: BridgeReviewQuery.Kind = .compare,
        fileTarget: String? = nil,
        pathScope: [String] = []
    ) {
        self.queryKind = queryKind
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
        resourceUrl: "agentstudio://resource/review/content/\(handleId)?generation=\(reviewGeneration.rawValue)",
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
    newContentHash: String? = nil
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
