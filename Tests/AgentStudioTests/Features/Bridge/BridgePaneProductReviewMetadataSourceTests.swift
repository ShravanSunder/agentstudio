import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Bridge pane product Review metadata source")
struct BridgePaneProductReviewMetadataSourceTests {
    @Test("opens with source acceptance and byte-bounded windows covering 3,420 items")
    func opensWithCompleteOrderedWindows() async throws {
        let package = makeReviewPackage(itemCount: 3420)
        let packageBox = ReviewPackageBox(package)
        let source = BridgePaneProductReviewMetadataSource { packageBox.package }
        let collector = ReviewMetadataEventCollector()

        try await source.open(subscription: try reviewSubscription()) { event in
            await collector.append(event)
        }
        let events = await collector.events

        #expect(events.count > 2)
        guard case .sourceAccepted(let accepted) = events.first else {
            Issue.record("Expected sourceAccepted before Review metadata windows")
            return
        }
        #expect(accepted.identity == reviewIdentity(for: package))

        let windowPayloads = try events.dropFirst().map(reviewWindowPayload)
        #expect(windowPayloads.first?.isSnapshot == true)
        #expect(windowPayloads.first?.itemStartIndex == 0)
        #expect(windowPayloads.first?.treeStartIndex == 0)
        #expect(windowPayloads.last?.itemFinalWindow == true)
        #expect(windowPayloads.last?.treeFinalWindow == true)

        assertContiguousReviewWindows(windowPayloads, package: package)
        let emittedItemIds = windowPayloads.flatMap { $0.itemMetadata.map(\.itemId) }
        let emittedFileItemIds = windowPayloads.flatMap(\.treeRows).compactMap(\.itemId)
        #expect(emittedItemIds == package.orderedItemIds)
        #expect(emittedFileItemIds == package.orderedItemIds)
        #expect(Set(windowPayloads.flatMap(\.treeRows).map(\.rowId)).count == windowPayloads.flatMap(\.treeRows).count)

        for event in events {
            let encoded = try JSONEncoder().encode(event)
            #expect(encoded.count <= BridgeProductWireContract.maximumMetadataFrameBytes)
            let json = try #require(String(data: encoded, encoding: .utf8))
            #expect(!json.contains("resourceUrl"))
            #expect(!json.contains("selectedItemId"))
            #expect(!json.contains("contents"))
        }
    }

    @Test("same revision update is a no-op and one changed item emits a bounded delta")
    func updatesWithMinimalLineageCorrectDelta() async throws {
        let initialPackage = makeReviewPackage(itemCount: 32)
        let packageBox = ReviewPackageBox(initialPackage)
        let source = BridgePaneProductReviewMetadataSource { packageBox.package }
        let collector = ReviewMetadataEventCollector()
        let initialSubscription = try reviewSubscription()
        try await source.open(subscription: initialSubscription) { event in
            await collector.append(event)
        }
        await collector.removeAll()

        try await source.update(subscription: try reviewSubscription(interestRevision: 1)) { event in
            await collector.append(event)
        }
        #expect(await collector.events.isEmpty)

        let changedItemId = try #require(initialPackage.orderedItemIds.first)
        packageBox.package = replacingReviewItem(
            in: initialPackage,
            itemId: changedItemId,
            fileClass: .config,
            revision: initialPackage.revision + 1
        )
        try await source.update(subscription: try reviewSubscription(interestRevision: 2)) { event in
            await collector.append(event)
        }
        let events = await collector.events

        #expect(events.count == 1)
        guard case .delta(let delta) = events.first else {
            Issue.record("Expected one Review delta")
            return
        }
        #expect(delta.fromRevision == initialPackage.revision)
        #expect(delta.toRevision == packageBox.package.revision)
        #expect(delta.identity.revision == delta.toRevision)
        let upsertedItemIds = delta.operations.compactMap { operation -> String? in
            guard case .upsertItem(let item) = operation else { return nil }
            return item.itemId
        }
        #expect(upsertedItemIds == [changedItemId])
        #expect(delta.operations.count <= 3)
        #expect(try JSONEncoder().encode(BridgeProductReviewMetadataEvent.delta(delta)).count <= 128 * 1024)
    }

    @Test("source identity replacement resets, accepts, and snapshots the replacement")
    func resetsAndSnapshotsReplacementSource() async throws {
        let initialPackage = makeReviewPackage(itemCount: 4)
        let packageBox = ReviewPackageBox(initialPackage)
        let source = BridgePaneProductReviewMetadataSource { packageBox.package }
        let collector = ReviewMetadataEventCollector()
        try await source.open(subscription: try reviewSubscription()) { event in
            await collector.append(event)
        }
        await collector.removeAll()

        packageBox.package = replacingReviewSource(
            initialPackage,
            packageId: "review-package-2",
            queryId: "review-query-2",
            generation: initialPackage.reviewGeneration.rawValue + 1
        )
        try await source.update(subscription: try reviewSubscription(interestRevision: 1)) { event in
            await collector.append(event)
        }
        let events = await collector.events

        #expect(events.count >= 3)
        guard case .reset(let reset) = events[0],
            case .sourceAccepted(let accepted) = events[1],
            case .snapshot(let snapshot) = events[2]
        else {
            Issue.record("Expected reset, sourceAccepted, then replacement snapshot")
            return
        }
        let replacementIdentity = reviewIdentity(for: packageBox.package)
        #expect(reset.identity == replacementIdentity)
        #expect(accepted.identity == replacementIdentity)
        #expect(snapshot.identity == replacementIdentity)
    }

    @Test("contract-unsafe same-source delta resets and snapshots instead")
    func resetsInsteadOfEmittingOversizedDeltaMembers() async throws {
        let initialPackage = makeReviewPackage(itemCount: 4097, includesContentRoles: false)
        let packageBox = ReviewPackageBox(initialPackage)
        let source = BridgePaneProductReviewMetadataSource { packageBox.package }
        let collector = ReviewMetadataEventCollector()
        try await source.open(subscription: try reviewSubscription()) { event in
            await collector.append(event)
        }
        await collector.removeAll()

        packageBox.package = replacingReviewPackage(
            initialPackage,
            revision: initialPackage.revision + 1,
            itemsById: [:]
        )
        try await source.update(subscription: try reviewSubscription(interestRevision: 1)) { event in
            await collector.append(event)
        }
        let events = await collector.events

        #expect(events.count == 3)
        guard case .reset = events[0], case .sourceAccepted = events[1], case .snapshot = events[2] else {
            Issue.record("Expected reset, sourceAccepted, and empty snapshot for an unsafe delta")
            return
        }
        #expect(!events.contains { if case .delta = $0 { true } else { false } })
    }

    @Test("cancellation during source acceptance prevents later window emission")
    func cancellationStopsWindowEmission() async throws {
        let packageBox = ReviewPackageBox(makeReviewPackage(itemCount: 128))
        let source = BridgePaneProductReviewMetadataSource { packageBox.package }
        let collector = ReviewMetadataEventCollector()
        let subscription = try reviewSubscription()

        try await source.open(subscription: subscription) { event in
            await collector.append(event)
            if case .sourceAccepted = event {
                await source.cancel(subscriptionId: subscription.subscriptionId)
            }
        }

        #expect(await collector.events.count == 1)
    }
}

@MainActor
private final class ReviewPackageBox {
    var package: BridgeReviewPackage

    init(_ package: BridgeReviewPackage) {
        self.package = package
    }
}

private actor ReviewMetadataEventCollector {
    private(set) var events: [BridgeProductReviewMetadataEvent] = []

    func append(_ event: BridgeProductReviewMetadataEvent) {
        events.append(event)
    }

    func removeAll() {
        events.removeAll()
    }
}

private struct ReviewWindowPayload {
    let isSnapshot: Bool
    let itemStartIndex: Int
    let itemFinalWindow: Bool
    let itemMetadata: [BridgeProductReviewItemMetadataValue]
    let treeStartIndex: Int
    let treeFinalWindow: Bool
    let treeRows: [BridgeProductReviewTreeRowValue]
}

private func reviewWindowPayload(_ event: BridgeProductReviewMetadataEvent) throws -> ReviewWindowPayload {
    switch event {
    case .snapshot(let snapshot):
        ReviewWindowPayload(
            isSnapshot: true,
            itemStartIndex: snapshot.itemWindow.startIndex,
            itemFinalWindow: snapshot.itemWindow.finalWindow,
            itemMetadata: snapshot.itemMetadata,
            treeStartIndex: snapshot.treeWindow.startIndex,
            treeFinalWindow: snapshot.treeWindow.finalWindow,
            treeRows: snapshot.treeRows
        )
    case .window(let window):
        ReviewWindowPayload(
            isSnapshot: false,
            itemStartIndex: window.itemWindow.startIndex,
            itemFinalWindow: window.itemWindow.finalWindow,
            itemMetadata: window.itemMetadata,
            treeStartIndex: window.treeWindow.startIndex,
            treeFinalWindow: window.treeWindow.finalWindow,
            treeRows: window.treeRows
        )
    default:
        throw ReviewMetadataSourceTestError.unexpectedEvent
    }
}

private func assertContiguousReviewWindows(
    _ windows: [ReviewWindowPayload],
    package: BridgeReviewPackage,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    var nextItemIndex = 0
    var nextTreeIndex = 0
    for window in windows {
        #expect(window.itemStartIndex == nextItemIndex, sourceLocation: sourceLocation)
        #expect(window.treeStartIndex == nextTreeIndex, sourceLocation: sourceLocation)
        nextItemIndex += window.itemMetadata.count
        nextTreeIndex += window.treeRows.count
    }
    #expect(nextItemIndex == package.orderedItemIds.count, sourceLocation: sourceLocation)
    #expect(nextTreeIndex >= package.orderedItemIds.count, sourceLocation: sourceLocation)
}

private func reviewIdentity(for package: BridgeReviewPackage) -> BridgeProductReviewMetadataIdentity {
    try! BridgeProductReviewMetadataIdentity(
        generation: package.reviewGeneration.rawValue,
        packageId: package.packageId,
        revision: package.revision,
        sourceIdentity: package.query.queryId
    )
}

private func reviewSubscription(interestRevision: Int = 0) throws -> BridgeProductSubscriptionSnapshot {
    let interestState = BridgeProductSubscriptionInterestState.reviewMetadata(interests: [])
    return BridgeProductSubscriptionSnapshot(
        subscription: .reviewMetadata,
        subscriptionId: "review-subscription-1",
        subscriptionKind: .reviewMetadata,
        workerDerivationEpoch: 1,
        interestRevision: interestRevision,
        interestSha256: try interestState.sha256Hex(),
        interestState: interestState,
        hasStagedUpdate: false
    )
}

private func makeReviewPackage(itemCount: Int, includesContentRoles: Bool = true) -> BridgeReviewPackage {
    let repoId = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let worktreeId = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    let items = (0..<itemCount).map { index in
        makeBridgeReviewItemDescriptor(
            itemId: String(format: "review-item-%05d", index),
            path: String(format: "Sources/Module%02d/File%05d.swift", index % 32, index),
            fileClass: .source,
            contentRoles: includesContentRoles ? nil : .init()
        )
    }
    let orderedItemIds = items.map(\.itemId)
    return BridgeReviewPackage(
        packageId: "review-package-1",
        schemaVersion: 1,
        reviewGeneration: 7,
        revision: 11,
        query: BridgeReviewQuery(
            queryId: "review-query-1",
            queryKind: .compare,
            repoId: repoId,
            worktreeId: worktreeId,
            baseEndpointId: "review-base-endpoint",
            headEndpointId: "review-head-endpoint",
            comparisonSemantics: .threeDot,
            pathScope: [],
            fileTarget: nil,
            viewFilter: BridgeViewFilter(showBinaryFiles: true, showLargeFiles: true),
            grouping: BridgeChangeGrouping(kind: .folder),
            provenanceFilter: BridgeProvenanceFilter()
        ),
        baseEndpoint: reviewEndpoint(
            endpointId: "review-base-endpoint",
            kind: .gitRef,
            repoId: repoId,
            worktreeId: worktreeId
        ),
        headEndpoint: reviewEndpoint(
            endpointId: "review-head-endpoint",
            kind: .workingTree,
            repoId: repoId,
            worktreeId: worktreeId
        ),
        orderedItemIds: orderedItemIds,
        itemsById: Dictionary(uniqueKeysWithValues: items.map { ($0.itemId, $0) }),
        groups: [],
        summary: BridgeReviewPackageSummary(
            filesChanged: itemCount,
            additions: itemCount,
            deletions: itemCount,
            visibleFileCount: itemCount,
            hiddenFileCount: 0
        ),
        filterState: BridgeViewFilter(showBinaryFiles: true, showLargeFiles: true),
        generatedAtUnixMilliseconds: 100
    )
}

private func reviewEndpoint(
    endpointId: String,
    kind: BridgeSourceEndpoint.Kind,
    repoId: UUID,
    worktreeId: UUID
) -> BridgeSourceEndpoint {
    BridgeSourceEndpoint(
        endpointId: endpointId,
        kind: kind,
        repoId: repoId,
        worktreeId: worktreeId,
        label: endpointId,
        createdAtUnixMilliseconds: 100,
        contentSetHash: nil,
        providerIdentity: "provider:\(endpointId)"
    )
}

private func replacingReviewItem(
    in package: BridgeReviewPackage,
    itemId: String,
    fileClass: BridgeFileClass,
    revision: Int
) -> BridgeReviewPackage {
    var itemsById = package.itemsById
    let previous = itemsById[itemId]!
    itemsById[itemId] = makeBridgeReviewItemDescriptor(
        itemId: itemId,
        path: previous.headPath ?? previous.basePath ?? itemId,
        fileClass: fileClass,
        contentRoles: previous.contentRoles
    )
    return replacingReviewPackage(package, revision: revision, itemsById: itemsById)
}

private func replacingReviewSource(
    _ package: BridgeReviewPackage,
    packageId: String,
    queryId: String,
    generation: Int
) -> BridgeReviewPackage {
    let query = BridgeReviewQuery(
        queryId: queryId,
        queryKind: package.query.queryKind,
        repoId: package.query.repoId,
        worktreeId: package.query.worktreeId,
        baseEndpointId: package.query.baseEndpointId,
        headEndpointId: package.query.headEndpointId,
        comparisonSemantics: package.query.comparisonSemantics,
        pathScope: package.query.pathScope,
        fileTarget: package.query.fileTarget,
        viewFilter: package.query.viewFilter,
        grouping: package.query.grouping,
        provenanceFilter: package.query.provenanceFilter
    )
    return BridgeReviewPackage(
        packageId: packageId,
        schemaVersion: package.schemaVersion,
        reviewGeneration: BridgeReviewGeneration(generation),
        revision: 0,
        query: query,
        baseEndpoint: package.baseEndpoint,
        headEndpoint: package.headEndpoint,
        orderedItemIds: package.orderedItemIds,
        itemsById: package.itemsById,
        groups: package.groups,
        summary: package.summary,
        filterState: package.filterState,
        generatedAtUnixMilliseconds: package.generatedAtUnixMilliseconds,
        changesetCluster: package.changesetCluster
    )
}

private func replacingReviewPackage(
    _ package: BridgeReviewPackage,
    revision: Int,
    itemsById: [String: BridgeReviewItemDescriptor]
) -> BridgeReviewPackage {
    BridgeReviewPackage(
        packageId: package.packageId,
        schemaVersion: package.schemaVersion,
        reviewGeneration: package.reviewGeneration,
        revision: revision,
        query: package.query,
        baseEndpoint: package.baseEndpoint,
        headEndpoint: package.headEndpoint,
        orderedItemIds: package.orderedItemIds,
        itemsById: itemsById,
        groups: package.groups,
        summary: package.summary,
        filterState: package.filterState,
        generatedAtUnixMilliseconds: package.generatedAtUnixMilliseconds,
        changesetCluster: package.changesetCluster
    )
}

private enum ReviewMetadataSourceTestError: Error {
    case unexpectedEvent
}
