import Foundation
import Testing

@testable import AgentStudio

struct BridgeReviewPipelineTests {
    @Test("pipeline builds package off main actor and registers provider content")
    func pipelineBuildsPackageOffMainActorAndRegistersProviderContent() async throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .promptCheckpoint)
        let changedFile = makeBridgeEndpointChangedFile(
            fileId: "source",
            path: "Sources/App/View.swift",
            sizeBytes: 100
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
        let contentStore = BridgeContentStore()
        let pipeline = BridgeReviewPipeline(provider: provider, contentStore: contentStore)

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
            sizeBytes: 100
        )
        let hiddenFile = makeBridgeEndpointChangedFile(
            fileId: "generated",
            path: "Sources/Generated/API.swift",
            sizeBytes: 100
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
        let contentStore = BridgeContentStore()
        let pipeline = BridgeReviewPipeline(provider: provider, contentStore: contentStore)

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

        #expect(result.package.orderedItemIds == ["item-source"])
        #expect(result.registeredContentHandles.contains(hiddenHeadHandle))
        let loaded = try await contentStore.load(handleId: hiddenHeadHandle.handleId, requestedGeneration: 5)
        #expect(loaded.data == Data("new-hidden".utf8))
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
    grouping: BridgeChangeGrouping = BridgeChangeGrouping(kind: .flat)
) -> BridgeReviewQuery {
    BridgeReviewQuery(
        queryId: "query",
        queryKind: .compare,
        repoId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        worktreeId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        baseEndpointId: baseEndpointId,
        headEndpointId: headEndpointId,
        comparisonSemantics: .checkpointDelta,
        pathScope: [],
        fileTarget: nil,
        viewFilter: filter,
        grouping: grouping,
        provenanceFilter: BridgeProvenanceFilter()
    )
}

func makeBridgeContentHandle(
    itemId: String,
    role: BridgeContentHandle.Role,
    endpointId: String = "endpoint",
    reviewGeneration: BridgeReviewGeneration = 7
) -> BridgeContentHandle {
    let handleId = "handle-\(endpointId)-\(itemId)-\(role.rawValue)"
    return BridgeContentHandle(
        handleId: handleId,
        itemId: itemId,
        role: role,
        endpointId: endpointId,
        reviewGeneration: reviewGeneration,
        resourceUrl: "agentstudio://resource/content/\(handleId)?generation=\(reviewGeneration.rawValue)",
        contentHash: "sha256:\(itemId):\(role.rawValue)",
        contentHashAlgorithm: "sha256",
        cacheKey: "\(endpointId):\(itemId):\(role.rawValue)",
        mimeType: "text/plain",
        language: nil,
        sizeBytes: 5,
        isBinary: false
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
    changeKind: BridgeFileChangeKind = .modified
) -> BridgeEndpointChangedFile {
    BridgeEndpointChangedFile(
        fileId: fileId,
        path: path,
        oldPath: nil,
        changeKind: changeKind,
        language: "swift",
        fileExtension: "swift",
        sizeBytes: sizeBytes,
        oldContentHash: changeKind == .added ? nil : "sha256:old-\(fileId)",
        newContentHash: changeKind == .deleted ? nil : "sha256:new-\(fileId)",
        contentHashAlgorithm: "sha256",
        additions: changeKind == .deleted ? 0 : 1,
        deletions: changeKind == .added ? 0 : 1,
        isBinary: false,
        mimeType: "text/x-swift"
    )
}
