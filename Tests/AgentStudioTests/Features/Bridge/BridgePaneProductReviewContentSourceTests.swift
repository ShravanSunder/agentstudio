import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge pane product Review content source")
struct BridgePaneProductReviewContentSourceTests {
    @Test("Review content authority is actor-owned rather than MainActor package-owned")
    func reviewContentAuthorityIsActorOwned() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Bridge/Transport/BridgePaneProductReviewContentSource.swift"
            ),
            encoding: .utf8
        )

        // Act / Assert
        #expect(source.contains("actor BridgePaneProductReviewContentSource"))
        #expect(!source.contains("currentPackage"))
        #expect(!source.contains("@MainActor"))
    }

    @Test("loads an authoritative Review byte range through the shared content store")
    @MainActor
    func loadsAuthoritativeRangeThroughSharedStore() async throws {
        // Arrange
        let fixture = try await ReviewProductContentFixture(content: "0123456789")
        let request = try fixture.request(startByte: 3, maximumBytes: 4)

        // Act
        let body = try await fixture.source.contentBody(
            for: request,
            productAdmission: fixture.productAdmission.context
        )

        // Assert
        #expect(body.data == Data("3456".utf8))
        #expect(body.sha256 == reviewProductRawSHA256(Data("3456".utf8)))
        #expect(body.wholeByteLength == 10)
        #expect(body.isFinalRange == false)
    }

    @Test("rejects a descriptor that does not match current package authority")
    @MainActor
    func rejectsDescriptorIdentityMismatch() async throws {
        // Arrange
        let fixture = try await ReviewProductContentFixture(content: "authority")
        let request = try fixture.request(
            startByte: 0,
            maximumBytes: 4,
            itemId: "forged-item"
        )

        // Act / Assert
        await #expect(throws: BridgePaneProductReviewContentSourceError.descriptorMismatch) {
            try await fixture.source.contentBody(
                for: request,
                productAdmission: fixture.productAdmission.context
            )
        }
    }

    @Test("loading and failed availability revoke issued Review descriptors")
    @MainActor
    func loadingAndFailedAvailabilityRevokeIssuedDescriptors() async throws {
        // Arrange
        let fixture = try await ReviewProductContentFixture(content: "authority")
        let request = try fixture.request(startByte: 0, maximumBytes: 4)

        // Act / Assert
        try await fixture.source.replaceAuthority(
            with: .loading,
            productAdmission: fixture.productAdmission.context
        )
        await #expect(throws: BridgePaneProductReviewContentSourceError.unavailablePackage) {
            try await fixture.source.contentBody(
                for: request,
                productAdmission: fixture.productAdmission.context
            )
        }

        try await fixture.source.replaceAuthority(
            with: .ready(fixture.package),
            productAdmission: fixture.productAdmission.context
        )
        _ = try await fixture.source.contentBody(
            for: request,
            productAdmission: fixture.productAdmission.context
        )
        try await fixture.source.replaceAuthority(
            with: .failed,
            productAdmission: fixture.productAdmission.context
        )
        await #expect(throws: BridgePaneProductReviewContentSourceError.unavailablePackage) {
            try await fixture.source.contentBody(
                for: request,
                productAdmission: fixture.productAdmission.context
            )
        }
    }

    @Test("a replacement generation rejects an exact descriptor from the retired generation")
    @MainActor
    func replacementGenerationRejectsRetiredDescriptor() async throws {
        // Arrange
        let fixture = try await ReviewProductContentFixture(content: "authority")
        let retiredRequest = try fixture.request(startByte: 0, maximumBytes: 4)
        let replacementPackage = fixture.replacementPackage(generation: 8)

        // Act
        try await fixture.source.replaceAuthority(
            with: .ready(replacementPackage),
            productAdmission: fixture.productAdmission.context
        )

        // Assert
        await #expect(throws: BridgePaneProductReviewContentSourceError.descriptorMismatch) {
            try await fixture.source.contentBody(
                for: retiredRequest,
                productAdmission: fixture.productAdmission.context
            )
        }
    }

    @Test("closed admission rejects content reads while failed cleanup still revokes authority")
    @MainActor
    func closedAdmissionRejectsReadsAndPermitsFailedCleanup() async throws {
        // Arrange
        let fixture = try await ReviewProductContentFixture(content: "retired")
        let request = try fixture.request(startByte: 0, maximumBytes: 4)

        // Act / Assert
        fixture.productAdmission.close()
        await #expect(throws: BridgePaneProductReviewContentSourceError.unavailablePackage) {
            try await fixture.source.contentBody(
                for: request,
                productAdmission: fixture.productAdmission.context
            )
        }
        try await fixture.source.replaceAuthority(
            with: .failed,
            productAdmission: fixture.productAdmission.context
        )
        let diagnosticAdmission = try BridgeProductAdmissionTestContext.make()
        #expect(
            await fixture.source.authoritativeItemId(
                for: request,
                productAdmission: diagnosticAdmission.context
            ) == nil
        )
    }

    @Test("highest committed Review interest wins and cancel plus resync reset revoke priority")
    @MainActor
    func committedReviewInterestOwnsContentPriorityLifecycle() async throws {
        // Arrange
        let fixture = try await ReviewProductContentFixture(content: "priority")
        let request = BridgeProductContentRequest.reviewContent(
            try fixture.request(startByte: 0, maximumBytes: 4)
        )
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: fixture.source
        )
        let visible = try reviewProductSubscriptionLifecycle(
            subscriptionId: "review-visible-subscription",
            itemId: fixture.handle.itemId,
            lane: .visible
        )
        let selected = try reviewProductSubscriptionLifecycle(
            subscriptionId: "review-selected-subscription",
            itemId: fixture.handle.itemId,
            lane: .foreground
        )
        let productAdmission = try BridgeProductAdmissionTestContext.make().context
        await coordinator.apply(
            .subscriptionOpened(visible.opened),
            productAdmission: productAdmission
        )
        await coordinator.apply(
            .subscriptionInterestsCommitted(
                barrier: visible.barrier,
                subscription: visible.committed
            ),
            productAdmission: productAdmission
        )
        await coordinator.apply(
            .subscriptionOpened(selected.opened),
            productAdmission: productAdmission
        )
        await coordinator.apply(
            .subscriptionInterestsCommitted(
                barrier: selected.barrier,
                subscription: selected.committed
            ),
            productAdmission: productAdmission
        )

        // Act / Assert
        #expect(
            await coordinator.contentDemandInterest(
                for: request,
                productAdmission: productAdmission
            ) == .selected
        )

        await coordinator.apply(
            .subscriptionCancelled(selected.committed),
            productAdmission: productAdmission
        )
        #expect(
            await coordinator.contentDemandInterest(
                for: request,
                productAdmission: productAdmission
            ) == .visible
        )

        let emptyState = BridgeProductSubscriptionInterestState.reviewMetadata(interests: [])
        let emptyStateSHA256 = try emptyState.sha256Hex()
        let resetRevision = visible.committed.interestRevision + 1
        await coordinator.apply(
            .resynced(
                .init(
                    reconciliation: [
                        .reset(
                            try .init(
                                subscriptionId: visible.committed.subscriptionId,
                                subscriptionKind: .reviewMetadata,
                                workerDerivationEpoch: visible.committed.workerDerivationEpoch,
                                interestRevision: resetRevision,
                                interestSha256: emptyStateSHA256,
                                reason: .interestMismatch
                            )
                        )
                    ],
                    revokedNativeOnlySubscriptionIds: [],
                    resetIntents: [
                        .init(
                            subscription: .reviewMetadata,
                            subscriptionId: visible.committed.subscriptionId,
                            subscriptionKind: .reviewMetadata,
                            workerDerivationEpoch: visible.committed.workerDerivationEpoch,
                            interestRevision: resetRevision,
                            interestSha256: emptyStateSHA256
                        )
                    ]
                )
            ),
            productAdmission: productAdmission
        )
        #expect(
            await coordinator.contentDemandInterest(
                for: request,
                productAdmission: productAdmission
            ) == .unspecified
        )
    }

    @Test("streams accepted data and terminal integrity frames for Review content")
    @MainActor
    func streamsReviewContentFrames() async throws {
        // Arrange
        let fixture = try await ReviewProductContentFixture(content: "abcdefghij")
        let reviewRequest = try fixture.request(startByte: 2, maximumBytes: 5)
        let provider = BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgePaneProductReviewMetadataSource(
                initialAvailability: .ready(fixture.package)
            ),
            reviewContentSource: fixture.source,
            markReviewItemViewed: { _, _ in }
        )
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let request = BridgeProductContentRequest.reviewContent(reviewRequest)
        let registration = await harness.session.registerContentProducer(
            request: request,
            productAdmission: harness.productAdmission.context
        ) { lease in
            await provider.runContentProducer(
                request: request,
                lease: lease,
                productAdmission: harness.productAdmission.context,
                session: harness.session
            )
        }
        let lease = try bridgeProductAcceptedLease(registration)
        let decoder = try BridgeProductContentFrameDecoder()
        var decodedFrames: [BridgeProductContentFrame] = []

        // Act
        while !decodedFrames.contains(where: { $0.isTerminalForReviewProductTest }) {
            let queuedFrame = try #require(
                await consumeNextBridgeProductProducerFrame(
                    for: lease,
                    from: harness.session,
                    productAdmission: harness.productAdmission.context
                )
            )
            decodedFrames.append(contentsOf: try decoder.append(queuedFrame.data))
        }

        // Assert
        guard case .accepted = decodedFrames.first?.header,
            case .end(let endHeader) = decodedFrames.last?.header
        else {
            Issue.record("Expected accepted and end Review content frames")
            return
        }
        let data = decodedFrames.reduce(into: Data()) { result, frame in
            guard case .data = frame.header else { return }
            result.append(frame.payload)
        }
        #expect(data == Data("cdefg".utf8))
        #expect(endHeader.endOfSource == false)
        #expect(endHeader.observedByteLength == 5)
        #expect(endHeader.observedSha256 == reviewProductRawSHA256(data))

        for _ in 0..<1000 where (await harness.session.producerSnapshot()).activeProducerTaskCount > 0 {
            await Task.yield()
        }
        let acknowledgement = try #require(await harness.session.unregisterProducer(lease))
        #expect(await harness.session.acknowledgeProducerLifecycle(acknowledgement))
    }
}

@MainActor
private struct ReviewProductContentFixture {
    let content: Data
    let handle: BridgeContentHandle
    let package: BridgeReviewPackage
    let productAdmission: BridgeProductAdmissionTestContext
    let source: BridgePaneProductReviewContentSource

    init(content: String) async throws {
        let contentData = Data(content.utf8)
        let wholeSHA256 = reviewProductRawSHA256(contentData)
        let handle = BridgeContentHandle(
            handleId: "review-handle-1",
            itemId: "review-item-1",
            role: .head,
            endpointId: "review-head-endpoint",
            reviewGeneration: 7,
            contentHash: "sha256:\(wholeSHA256)",
            contentHashAlgorithm: "sha256",
            cacheKey: "review-content-cache-1",
            mimeType: "text/plain",
            language: "swift",
            sizeBytes: contentData.count,
            isBinary: false
        )
        let package = Self.makePackage(handle: handle)
        let store = BridgeContentStore()
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        try await store.register(
            BridgeContentLoadResult(
                handle: handle,
                data: contentData,
                mimeType: handle.mimeType,
                contentHash: handle.contentHash,
                contentHashAlgorithm: handle.contentHashAlgorithm
            ),
            productAdmission: productAdmission.context
        )
        self.content = contentData
        self.handle = handle
        self.package = package
        self.productAdmission = productAdmission
        let source = BridgePaneProductReviewContentSource(contentStore: store)
        try await source.replaceAuthority(
            with: .ready(package),
            productAdmission: productAdmission.context
        )
        self.source = source
    }

    func replacementPackage(generation: BridgeReviewGeneration) -> BridgeReviewPackage {
        let replacementHandle = BridgeContentHandle(
            handleId: handle.handleId,
            itemId: handle.itemId,
            role: handle.role,
            endpointId: handle.endpointId,
            reviewGeneration: generation,
            contentHash: handle.contentHash,
            contentHashAlgorithm: handle.contentHashAlgorithm,
            cacheKey: handle.cacheKey,
            mimeType: handle.mimeType,
            language: handle.language,
            sizeBytes: handle.sizeBytes,
            sizeBytesIsExact: handle.sizeBytesIsExact,
            isBinary: handle.isBinary
        )
        return Self.makePackage(handle: replacementHandle)
    }

    func request(
        startByte: Int,
        maximumBytes: Int,
        itemId: String = "review-item-1"
    ) throws -> BridgeProductReviewContentRequest {
        let endByte = min(startByte + maximumBytes, content.count)
        let rangeData = content.subdata(in: startByte..<endByte)
        let object: [String: Any] = [
            "contentKind": "review.content",
            "contentRequestId": "review-content-request-1",
            "descriptor": [
                "contentDigest": [
                    "algorithm": "sha256",
                    "authority": "authoritative",
                    "value": reviewProductRawSHA256(content),
                ],
                "contentKind": "review.content",
                "declaredByteLength": rangeData.count,
                "descriptorId": handle.handleId,
                "encoding": "utf-8",
                "endpointId": handle.endpointId,
                "expectedSha256": reviewProductRawSHA256(rangeData),
                "handleId": handle.handleId,
                "isBinary": false,
                "itemId": itemId,
                "language": handle.language.map { $0 as Any } ?? NSNull(),
                "maximumBytes": maximumBytes,
                "mimeType": handle.mimeType,
                "packageId": package.packageId,
                "reviewGeneration": handle.reviewGeneration.rawValue,
                "role": handle.role.rawValue,
                "sourceIdentity": package.query.queryId,
                "wholeByteLength": content.count,
                "window": [
                    "kind": "byteRange",
                    "maximumBytes": maximumBytes,
                    "startByte": startByte,
                ],
            ],
            "kind": "content.open",
            "leaseId": "review-content-lease-1",
            "paneSessionId": "pane-session-1",
            "wireVersion": BridgeProductWireContract.version,
            "workerDerivationEpoch": 1,
            "workerInstanceId": "worker-instance-1",
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoded = try BridgeProductStrictJSON.decode(BridgeProductContentRequest.self, from: data)
        guard case .reviewContent(let request) = decoded else {
            throw ReviewProductContentFixtureError.unexpectedContentKind
        }
        return request
    }

    private static func makePackage(handle: BridgeContentHandle) -> BridgeReviewPackage {
        let repoId = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let worktreeId = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let baseEndpoint = BridgeSourceEndpoint(
            endpointId: "review-base-endpoint",
            kind: .gitRef,
            repoId: repoId,
            worktreeId: worktreeId,
            label: "Base",
            createdAtUnixMilliseconds: 1,
            contentSetHash: nil,
            providerIdentity: "git:base"
        )
        let headEndpoint = BridgeSourceEndpoint(
            endpointId: handle.endpointId,
            kind: .workingTree,
            repoId: repoId,
            worktreeId: worktreeId,
            label: "Head",
            createdAtUnixMilliseconds: 2,
            contentSetHash: nil,
            providerIdentity: "git:head"
        )
        let query = BridgeReviewQuery(
            queryId: "review-query-1",
            queryKind: .compare,
            repoId: repoId,
            worktreeId: worktreeId,
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId,
            comparisonSemantics: .twoDot,
            pathScope: [],
            fileTarget: nil,
            viewFilter: BridgeViewFilter(showLargeFiles: true),
            grouping: BridgeChangeGrouping(),
            provenanceFilter: BridgeProvenanceFilter()
        )
        let item = BridgeReviewItemDescriptor(
            itemId: handle.itemId,
            itemKind: .diff,
            itemVersion: 1,
            basePath: "Sources/Old.swift",
            headPath: "Sources/New.swift",
            changeKind: .modified,
            fileClass: .source,
            language: handle.language,
            extension: "swift",
            sizeBytes: handle.sizeBytes,
            baseContentHash: nil,
            headContentHash: handle.contentHash,
            contentHashAlgorithm: handle.contentHashAlgorithm,
            additions: 1,
            deletions: 1,
            isHiddenByDefault: false,
            hiddenReason: nil,
            reviewPriority: .normal,
            contentRoles: .init(head: handle),
            cacheKey: handle.cacheKey,
            provenance: BridgeProvenanceSummary(),
            annotationSummary: .init(threadCount: 0, unresolvedThreadCount: 0, commentCount: 0),
            reviewState: .unreviewed,
            collapsed: false
        )
        return BridgeReviewPackage(
            packageId: "review-package-1",
            schemaVersion: 1,
            reviewGeneration: handle.reviewGeneration,
            revision: 1,
            query: query,
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            orderedItemIds: [item.itemId],
            itemsById: [item.itemId: item],
            groups: [],
            summary: .init(
                filesChanged: 1,
                additions: 1,
                deletions: 1,
                visibleFileCount: 1,
                hiddenFileCount: 0
            ),
            filterState: query.viewFilter,
            generatedAtUnixMilliseconds: 3
        )
    }
}

private struct ReviewProductSubscriptionLifecycle {
    let opened: BridgeProductSubscriptionSnapshot
    let committed: BridgeProductSubscriptionSnapshot
    let barrier: BridgeProductSubscriptionCommitBarrierIntent
}

private func reviewProductSubscriptionLifecycle(
    subscriptionId: String,
    itemId: String,
    lane: BridgeProductDemandLane
) throws -> ReviewProductSubscriptionLifecycle {
    let emptyState = BridgeProductSubscriptionInterestState.reviewMetadata(interests: [])
    let opened = BridgeProductSubscriptionSnapshot(
        subscription: .reviewMetadata,
        subscriptionId: subscriptionId,
        subscriptionKind: .reviewMetadata,
        workerDerivationEpoch: 1,
        interestRevision: 0,
        interestSha256: try emptyState.sha256Hex(),
        interestState: emptyState,
        hasStagedUpdate: false
    )
    let committedState = BridgeProductSubscriptionInterestState.reviewMetadata(
        interests: [try .init(itemIds: [itemId], lane: lane)]
    )
    let committedSHA256 = try committedState.sha256Hex()
    let committed = BridgeProductSubscriptionSnapshot(
        subscription: .reviewMetadata,
        subscriptionId: subscriptionId,
        subscriptionKind: .reviewMetadata,
        workerDerivationEpoch: 1,
        interestRevision: 1,
        interestSha256: committedSHA256,
        interestState: committedState,
        hasStagedUpdate: false
    )
    return .init(
        opened: opened,
        committed: committed,
        barrier: .init(
            subscriptionId: subscriptionId,
            subscriptionKind: .reviewMetadata,
            workerDerivationEpoch: 1,
            interestRevision: 1,
            interestSha256: committedSHA256,
            updateId: "\(subscriptionId)-update-1"
        )
    )
}

private enum ReviewProductContentFixtureError: Error {
    case unexpectedContentKind
}

private func reviewProductRawSHA256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

extension BridgeProductContentFrame {
    fileprivate var isTerminalForReviewProductTest: Bool {
        switch header {
        case .end, .error, .reset:
            true
        case .accepted, .data:
            false
        }
    }
}
