import Foundation
import Testing

@testable import AgentStudio

struct BridgeReviewDeltaBuilderTests {
    @Test("delta builder emits add update remove move group summary and invalidation ops")
    func deltaBuilderEmitsPackageOperations() throws {
        let existingSource = makeDescriptor(
            itemId: "item-source",
            path: "Sources/App/View.swift",
            headContentHash: "sha256:old-source"
        )
        let removedDoc = makeDescriptor(
            itemId: "item-doc",
            path: "Docs/Guide.md",
            headContentHash: "sha256:old-doc"
        )
        let currentPackage = makePackage(
            orderedItemIds: ["item-source", "item-doc"],
            items: [existingSource, removedDoc],
            groups: [
                makeReviewGroup(
                    label: "Before",
                    orderedItemIds: ["item-source", "item-doc"],
                    summary: BridgeReviewGroupSummary(filesChanged: 2, additions: 2, deletions: 2)
                )
            ],
            summary: BridgeReviewPackageSummary(
                filesChanged: 2,
                additions: 2,
                deletions: 2,
                visibleFileCount: 2,
                hiddenFileCount: 0
            )
        )
        let updatedSource = makeDescriptor(
            itemId: "item-source",
            path: "Sources/App/View.swift",
            headContentHash: "sha256:new-source",
            additions: 5,
            deletions: 1
        )
        let addedTest = makeDescriptor(
            itemId: "item-test",
            path: "Tests/App/ViewTests.swift",
            headContentHash: "sha256:test"
        )
        let nextPackage = makePackage(
            orderedItemIds: ["item-test", "item-source"],
            items: [addedTest, updatedSource],
            groups: [
                makeReviewGroup(
                    label: "After",
                    orderedItemIds: ["item-test", "item-source"],
                    summary: BridgeReviewGroupSummary(filesChanged: 2, additions: 6, deletions: 1)
                )
            ],
            summary: BridgeReviewPackageSummary(
                filesChanged: 2,
                additions: 6,
                deletions: 1,
                visibleFileCount: 2,
                hiddenFileCount: 0
            )
        )

        let delta = try #require(
            try BridgeReviewDeltaBuilder.build(
                BridgeReviewDeltaBuildRequest(
                    currentPackage: currentPackage,
                    nextPackage: nextPackage,
                    currentRevision: 4
                )
            )
        )

        #expect(delta.packageId == "package")
        #expect(delta.reviewGeneration == 7)
        #expect(delta.revision == 5)
        #expect(delta.operations.addItems.map(\.itemId) == ["item-test"])
        #expect(delta.operations.updateItems.map(\.itemId) == ["item-source"])
        #expect(delta.operations.updateItems.first?.itemVersion == existingSource.itemVersion + 1)
        #expect(delta.operations.removeItems == ["item-doc"])
        #expect(delta.operations.moveItems == ["item-test", "item-source"])
        #expect(delta.operations.updateGroups?.map(\.label) == ["After"])
        #expect(delta.operations.updateSummary?.additions == 6)
        #expect(
            delta.operations.invalidateContent
                == [
                    "handle-item-doc",
                    "handle-item-source",
                    "handle-item-source-new",
                ])
    }

    @Test("delta builder returns nil for identical packages")
    func deltaBuilderReturnsNilForIdenticalPackages() throws {
        let descriptor = makeDescriptor(itemId: "item-source", path: "Sources/App/View.swift")
        let package = makePackage(orderedItemIds: ["item-source"], items: [descriptor])

        let delta = try BridgeReviewDeltaBuilder.build(
            BridgeReviewDeltaBuildRequest(
                currentPackage: package,
                nextPackage: package,
                currentRevision: 1
            )
        )

        #expect(delta == nil)
    }

    @Test("delta builder removes hidden items that are absent from ordered ids")
    func deltaBuilderRemovesHiddenItemsAbsentFromOrderedIds() throws {
        let visibleDescriptor = makeDescriptor(itemId: "item-source", path: "Sources/App/View.swift")
        let hiddenDescriptor = makeDescriptor(itemId: "item-hidden", path: "Generated/File.generated.swift")
        let currentPackage = makePackage(
            orderedItemIds: ["item-source"],
            items: [visibleDescriptor, hiddenDescriptor]
        )
        let nextPackage = makePackage(
            orderedItemIds: ["item-source"],
            items: [visibleDescriptor]
        )

        let delta = try #require(
            try BridgeReviewDeltaBuilder.build(
                BridgeReviewDeltaBuildRequest(
                    currentPackage: currentPackage,
                    nextPackage: nextPackage,
                    currentRevision: 2
                )
            )
        )

        #expect(delta.operations.removeItems == ["item-hidden"])
        #expect(delta.operations.invalidateContent == ["handle-item-hidden"])
    }

    @Test("delta builder emits empty group updates instead of treating them as unchanged")
    func deltaBuilderEmitsEmptyGroupUpdates() throws {
        let descriptor = makeDescriptor(itemId: "item-source", path: "Sources/App/View.swift")
        let currentPackage = makePackage(
            orderedItemIds: ["item-source"],
            items: [descriptor],
            groups: [
                makeReviewGroup(
                    label: "Before",
                    orderedItemIds: ["item-source"],
                    summary: BridgeReviewGroupSummary(filesChanged: 1, additions: 1, deletions: 1)
                )
            ]
        )
        let nextPackage = makePackage(
            orderedItemIds: ["item-source"],
            items: [descriptor],
            groups: []
        )

        let delta = try #require(
            try BridgeReviewDeltaBuilder.build(
                BridgeReviewDeltaBuildRequest(
                    currentPackage: currentPackage,
                    nextPackage: nextPackage,
                    currentRevision: 2
                )
            )
        )

        #expect(delta.operations.updateGroups?.isEmpty == true)
    }

    @Test("delta builder rejects package or generation mismatches")
    func deltaBuilderRejectsMismatches() throws {
        let descriptor = makeDescriptor(itemId: "item-source", path: "Sources/App/View.swift")
        let package = makePackage(orderedItemIds: ["item-source"], items: [descriptor])
        let otherPackage = makePackage(packageId: "other", orderedItemIds: ["item-source"], items: [descriptor])
        let otherGenerationPackage = makePackage(
            orderedItemIds: ["item-source"],
            items: [descriptor],
            reviewGeneration: 8
        )

        #expect(throws: BridgeReviewDeltaBuilderError.packageMismatch(current: "package", next: "other")) {
            try BridgeReviewDeltaBuilder.build(
                BridgeReviewDeltaBuildRequest(
                    currentPackage: package,
                    nextPackage: otherPackage,
                    currentRevision: 1
                )
            )
        }
        #expect(
            throws: BridgeReviewDeltaBuilderError.reviewGenerationMismatch(current: 7, next: 8)
        ) {
            try BridgeReviewDeltaBuilder.build(
                BridgeReviewDeltaBuildRequest(
                    currentPackage: package,
                    nextPackage: otherGenerationPackage,
                    currentRevision: 1
                )
            )
        }
    }
}

private func makePackage(
    packageId: String = "package",
    orderedItemIds: [String],
    items: [BridgeReviewItemDescriptor],
    groups: [BridgeReviewGroup]? = nil,
    summary: BridgeReviewPackageSummary? = nil,
    reviewGeneration: BridgeReviewGeneration = 7
) -> BridgeReviewPackage {
    let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
    let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
    let itemsById = Dictionary(uniqueKeysWithValues: items.map { ($0.itemId, $0) })
    let resolvedSummary =
        summary
        ?? BridgeReviewPackageSummary(
            filesChanged: items.count,
            additions: items.reduce(0) { $0 + $1.additions },
            deletions: items.reduce(0) { $0 + $1.deletions },
            visibleFileCount: orderedItemIds.count,
            hiddenFileCount: items.count - orderedItemIds.count
        )

    return BridgeReviewPackage(
        packageId: packageId,
        schemaVersion: 1,
        reviewGeneration: reviewGeneration,
        revision: 0,
        query: makeBridgeReviewQuery(
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId
        ),
        baseEndpoint: baseEndpoint,
        headEndpoint: headEndpoint,
        orderedItemIds: orderedItemIds,
        itemsById: itemsById,
        groups: groups
            ?? [
                makeReviewGroup(
                    label: "Files",
                    orderedItemIds: orderedItemIds,
                    summary: BridgeReviewGroupSummary(
                        filesChanged: orderedItemIds.count,
                        additions: resolvedSummary.additions,
                        deletions: resolvedSummary.deletions
                    ),
                    hiddenFileCount: resolvedSummary.hiddenFileCount
                )
            ],
        summary: resolvedSummary,
        filterState: BridgeViewFilter(),
        generatedAtUnixMilliseconds: 100
    )
}

private func makeReviewGroup(
    label: String,
    orderedItemIds: [String],
    summary: BridgeReviewGroupSummary,
    hiddenFileCount: Int = 0
) -> BridgeReviewGroup {
    BridgeReviewGroup(
        groupId: "group-\(label.lowercased())",
        grouping: BridgeChangeGrouping(kind: .flat),
        label: label,
        orderedItemIds: orderedItemIds,
        summary: summary,
        hiddenSummary: BridgeHiddenSummary(
            hiddenFileCount: hiddenFileCount,
            hiddenAdditions: 0,
            hiddenDeletions: 0,
            hiddenFileClasses: []
        )
    )
}

private func makeDescriptor(
    itemId: String,
    path: String,
    headContentHash: String = "sha256:head",
    additions: Int = 1,
    deletions: Int = 1
) -> BridgeReviewItemDescriptor {
    let handle = BridgeContentHandle(
        handleId: headContentHash.contains("new") ? "handle-\(itemId)-new" : "handle-\(itemId)",
        itemId: itemId,
        role: .head,
        endpointId: "head",
        reviewGeneration: 7,
        contentHash: headContentHash,
        contentHashAlgorithm: "sha256",
        cacheKey: "head:\(itemId):\(headContentHash)",
        mimeType: "text/plain",
        language: "swift",
        sizeBytes: 100,
        isBinary: false
    )

    return BridgeReviewItemDescriptor(
        itemId: itemId,
        itemKind: .diff,
        itemVersion: 7,
        basePath: path,
        headPath: path,
        changeKind: .modified,
        fileClass: .source,
        language: "swift",
        extension: "swift",
        sizeBytes: 100,
        baseContentHash: "sha256:base",
        headContentHash: headContentHash,
        contentHashAlgorithm: "sha256",
        additions: additions,
        deletions: deletions,
        isHiddenByDefault: false,
        hiddenReason: nil,
        reviewPriority: .normal,
        contentRoles: BridgeReviewItemDescriptor.ContentRoles(head: handle),
        cacheKey: handle.cacheKey,
        provenance: BridgeProvenanceSummary(),
        annotationSummary: BridgeAnnotationSummary(threadCount: 0, unresolvedThreadCount: 0, commentCount: 0),
        reviewState: .unreviewed,
        collapsed: false
    )
}
