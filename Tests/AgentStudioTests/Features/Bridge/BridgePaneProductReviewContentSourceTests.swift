import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge pane product Review content source")
struct BridgePaneProductReviewContentSourceTests {
    @Test("content source delegates authority to coordinator leases")
    func contentSourceDelegatesAuthorityToCoordinatorLeases() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Bridge/Transport/BridgePaneProductReviewContentSource.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("actor BridgePaneProductReviewContentSource"))
        #expect(source.contains("acquireContentLease"))
        #expect(source.contains("settleContentLease"))
        #expect(!source.contains("replaceAuthority"))
        #expect(!source.contains("authorityByDescriptorId"))
        #expect(!source.contains("hasAvailableAuthority"))
        #expect(!source.contains("currentPackage"))
    }

    @Test("successful range load settles its coordinator lease exactly once")
    @MainActor
    func successfulRangeLoadSettlesLeaseExactlyOnce() async throws {
        let fixture = try await ReviewProductContentFixture(content: "0123456789")
        let request = try fixture.request(startByte: 3, maximumBytes: 4)

        let body = try await fixture.source.contentBody(
            for: request,
            productAdmission: fixture.productAdmission.context
        )

        #expect(body.data == Data("3456".utf8))
        #expect(body.sha256 == reviewContentSHA256(Data("3456".utf8)))
        #expect(body.wholeByteLength == 10)
        #expect(!body.isFinalRange)
        #expect(fixture.leasePort.acquireCallCount == 1)
        #expect(fixture.leasePort.settleCallCount == 1)
        #expect(fixture.coordinator.diagnosticSnapshot.activeContentLeaseCount == 0)
    }

    @Test("descriptor mismatch settles an acquired lease exactly once")
    @MainActor
    func descriptorMismatchSettlesLeaseExactlyOnce() async throws {
        let fixture = try await ReviewProductContentFixture(content: "authority")
        let request = try fixture.request(
            startByte: 0,
            maximumBytes: 4,
            itemId: "forged-item"
        )

        await #expect(throws: BridgePaneProductReviewContentSourceError.descriptorMismatch) {
            try await fixture.source.contentBody(
                for: request,
                productAdmission: fixture.productAdmission.context
            )
        }

        #expect(fixture.leasePort.acquireCallCount == 1)
        #expect(fixture.leasePort.settleCallCount == 1)
        #expect(fixture.coordinator.diagnosticSnapshot.activeContentLeaseCount == 0)
    }

    @Test("post-load integrity error settles its coordinator lease exactly once")
    @MainActor
    func integrityErrorSettlesLeaseExactlyOnce() async throws {
        let fixture = try await ReviewProductContentFixture(content: "authority")
        let request = try fixture.request(
            startByte: 0,
            maximumBytes: 4,
            expectedSHA256: String(repeating: "0", count: 64)
        )

        await #expect(throws: BridgePaneProductReviewContentSourceError.self) {
            try await fixture.source.contentBody(
                for: request,
                productAdmission: fixture.productAdmission.context
            )
        }

        #expect(fixture.leasePort.acquireCallCount == 1)
        #expect(fixture.leasePort.settleCallCount == 1)
        #expect(fixture.coordinator.diagnosticSnapshot.activeContentLeaseCount == 0)
    }

    @Test("provider failure settles its coordinator lease exactly once")
    @MainActor
    func providerFailureSettlesLeaseExactlyOnce() async throws {
        let fixture = try await ReviewProductContentFixture(
            content: "missing",
            providerHasContent: false
        )
        let request = try fixture.request(startByte: 0, maximumBytes: 4)

        await #expect(throws: BridgeProviderFailure.self) {
            try await fixture.source.contentBody(
                for: request,
                productAdmission: fixture.productAdmission.context
            )
        }

        #expect(fixture.leasePort.acquireCallCount == 1)
        #expect(fixture.leasePort.settleCallCount == 1)
        #expect(fixture.coordinator.diagnosticSnapshot.activeContentLeaseCount == 0)
    }

    @Test("cancellation settles its coordinator lease exactly once")
    @MainActor
    func cancellationSettlesLeaseExactlyOnce() async throws {
        let gate = BridgeContentLoadGate()
        let fixture = try await ReviewProductContentFixture(
            content: "cancelled",
            contentLoadGate: gate
        )
        let request = try fixture.request(startByte: 0, maximumBytes: 4)
        let load = Task {
            try await fixture.source.contentBody(
                for: request,
                productAdmission: fixture.productAdmission.context
            )
        }
        await gate.waitForStartedLoadCount(1)

        load.cancel()
        await gate.releaseAll()

        await #expect(throws: CancellationError.self) {
            _ = try await load.value
        }
        #expect(fixture.leasePort.acquireCallCount == 1)
        #expect(fixture.leasePort.settleCallCount == 1)
        #expect(fixture.coordinator.diagnosticSnapshot.activeContentLeaseCount == 0)
    }

    @Test("failed success settlement is attempted exactly once")
    @MainActor
    func failedSuccessSettlementIsAttemptedExactlyOnce() async throws {
        let gate = BridgeContentLoadGate()
        let fixture = try await ReviewProductContentFixture(
            content: "closed-after-load",
            contentLoadGate: gate
        )
        let request = try fixture.request(startByte: 0, maximumBytes: 6)
        let load = Task {
            try await fixture.source.contentBody(
                for: request,
                productAdmission: fixture.productAdmission.context
            )
        }
        await gate.waitForStartedLoadCount(1)

        fixture.coordinator.close()
        await gate.releaseAll()

        await #expect(throws: BridgePaneProductReviewContentSourceError.unavailablePackage) {
            _ = try await load.value
        }
        #expect(fixture.leasePort.acquireCallCount == 1)
        #expect(fixture.leasePort.settleCallCount == 1)
        #expect(fixture.coordinator.diagnosticSnapshot.activeContentLeaseCount == 0)
    }

    @Test("admitted A lease finishes after B commits")
    @MainActor
    func admittedALeaseFinishesAfterBCommits() async throws {
        let gate = BridgeContentLoadGate()
        let fixture = try await ReviewProductContentFixture(
            content: "retained-A",
            contentLoadGate: gate
        )
        let requestA = try fixture.request(startByte: 0, maximumBytes: 8)
        let loadA = Task {
            try await fixture.source.contentBody(
                for: requestA,
                productAdmission: fixture.productAdmission.context
            )
        }
        await gate.waitForStartedLoadCount(1)

        try await fixture.commitReplacementPublication()
        await gate.releaseAll()
        let bodyA = try await loadA.value

        #expect(bodyA.data == Data("retained".utf8))
        #expect(fixture.leasePort.settleCallCount == 1)
        #expect(fixture.coordinator.diagnosticSnapshot.activeContentLeaseCount == 0)
    }

    @Test("no new A lease can start after B commits")
    @MainActor
    func noNewALeaseCanStartAfterBCommits() async throws {
        let fixture = try await ReviewProductContentFixture(content: "retired-A")
        let requestA = try fixture.request(startByte: 0, maximumBytes: 4)
        try await fixture.commitReplacementPublication()

        await #expect(throws: BridgePaneProductReviewContentSourceError.unavailablePackage) {
            try await fixture.source.contentBody(
                for: requestA,
                productAdmission: fixture.productAdmission.context
            )
        }

        #expect(fixture.leasePort.acquireCallCount == 1)
        #expect(fixture.leasePort.settleCallCount == 0)
    }

    @Test("authoritative item lookup acquires and settles one short-lived lease")
    @MainActor
    func authoritativeItemLookupAcquiresAndSettlesLease() async throws {
        let fixture = try await ReviewProductContentFixture(content: "identity")
        let request = try fixture.request(startByte: 0, maximumBytes: 4)

        let itemId = await fixture.source.authoritativeItemId(
            for: request,
            productAdmission: fixture.productAdmission.context
        )

        #expect(itemId == fixture.handle.itemId)
        #expect(fixture.leasePort.acquireCallCount == 1)
        #expect(fixture.leasePort.settleCallCount == 1)
        #expect(fixture.coordinator.diagnosticSnapshot.activeContentLeaseCount == 0)
    }

    @Test("closed coordinator refuses content authority without touching loader cache")
    @MainActor
    func closedCoordinatorRefusesContentAuthority() async throws {
        let fixture = try await ReviewProductContentFixture(content: "closed")
        let request = try fixture.request(startByte: 0, maximumBytes: 4)
        fixture.coordinator.close()

        await #expect(throws: BridgePaneProductReviewContentSourceError.unavailablePackage) {
            try await fixture.source.contentBody(
                for: request,
                productAdmission: fixture.productAdmission.context
            )
        }

        #expect(fixture.leasePort.acquireCallCount == 1)
        #expect(fixture.leasePort.settleCallCount == 0)
        #expect((await fixture.loaderCache.diagnosticSnapshot).cachedContentCount == 0)
    }
}

@MainActor
private final class ReviewContentLeasePort {
    let coordinator: BridgeReviewPublicationCoordinator
    private(set) var acquireCallCount = 0
    private(set) var settleCallCount = 0

    init(coordinator: BridgeReviewPublicationCoordinator) {
        self.coordinator = coordinator
    }

    func acquire(
        descriptor: BridgeProductReviewContentDescriptor,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeReviewContentAuthorityLease? {
        acquireCallCount += 1
        return coordinator.acquireContentLease(
            handleId: descriptor.source.handleId,
            packageId: descriptor.packageId,
            requestedGeneration: BridgeReviewGeneration(descriptor.reviewGeneration),
            sourceIdentity: descriptor.sourceIdentity,
            productAdmission: productAdmission
        )
    }

    func settle(_ lease: BridgeReviewContentAuthorityLease) -> Bool {
        settleCallCount += 1
        return coordinator.settleContentLease(lease)
    }
}

@MainActor
private final class ReviewProductContentFixture {
    let content: Data
    let handle: BridgeContentHandle
    let package: BridgeReviewPackage
    let productAdmission: BridgeProductAdmissionTestContext
    let coordinator: BridgeReviewPublicationCoordinator
    let leasePort: ReviewContentLeasePort
    let loaderCache: BridgeReviewContentLoaderCache
    let source: BridgePaneProductReviewContentSource

    init(
        content: String,
        providerHasContent: Bool = true,
        contentLoadGate: BridgeContentLoadGate? = nil
    ) async throws {
        let contentData = Data(content.utf8)
        let handle = Self.makeHandle(
            content: contentData,
            reviewGeneration: 7
        )
        let package = Self.makePackage(handle: handle)
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: package.baseEndpoint,
                headEndpoint: package.headEndpoint,
                changedFiles: []
            ),
            contentByHandleId: providerHasContent
                ? [handle.handleId: Self.makeResult(handle: handle, content: contentData)]
                : [:],
            contentLoadGate: contentLoadGate
        )
        let loaderCache = BridgeReviewContentLoaderCache(provider: provider)
        let coordinator = BridgeReviewPublicationCoordinator()
        try await Self.commit(
            package: package,
            handles: [handle],
            coordinator: coordinator,
            productAdmission: productAdmission.context
        )
        let leasePort = ReviewContentLeasePort(coordinator: coordinator)
        let source = BridgePaneProductReviewContentSource(
            loaderCache: loaderCache,
            acquireContentLease: { descriptor, admission in
                leasePort.acquire(descriptor: descriptor, productAdmission: admission)
            },
            settleContentLease: { lease in
                leasePort.settle(lease)
            }
        )

        self.content = contentData
        self.handle = handle
        self.package = package
        self.productAdmission = productAdmission
        self.coordinator = coordinator
        self.leasePort = leasePort
        self.loaderCache = loaderCache
        self.source = source
    }

    func commitReplacementPublication() async throws {
        let replacementHandle = Self.makeHandle(
            content: content,
            reviewGeneration: handle.reviewGeneration.next()
        )
        try await Self.commit(
            package: Self.makePackage(handle: replacementHandle),
            handles: [replacementHandle],
            coordinator: coordinator,
            productAdmission: productAdmission.context
        )
    }

    func request(
        startByte: Int,
        maximumBytes: Int,
        itemId: String? = nil,
        expectedSHA256: String? = nil
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
                    "value": reviewContentSHA256(content),
                ],
                "contentKind": "review.content",
                "declaredByteLength": rangeData.count,
                "descriptorId": handle.handleId,
                "encoding": "utf-8",
                "endpointId": handle.endpointId,
                "expectedSha256": expectedSHA256 ?? reviewContentSHA256(rangeData),
                "handleId": handle.handleId,
                "isBinary": false,
                "itemId": itemId ?? handle.itemId,
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

    private static func commit(
        package: BridgeReviewPackage,
        handles: [BridgeContentHandle],
        coordinator: BridgeReviewPublicationCoordinator,
        productAdmission: BridgeProductAdmissionContext
    ) async throws {
        let preparedCandidate = await BridgeReviewPreparedPublication.prepare(
            BridgeReviewPublicationCandidate(
                package: package,
                delta: nil,
                contentHandles: handles
            )
        )
        let prepared = try #require(preparedCandidate)
        let token = try #require(
            coordinator.stage(prepared, productAdmission: productAdmission)
        )
        guard
            case .committed = coordinator.commit(
                token,
                productAdmission: productAdmission,
                presentCommitted: { _ in }
            )
        else {
            Issue.record("Expected Review publication commit")
            return
        }
    }

    private static func makeHandle(
        content: Data,
        reviewGeneration: BridgeReviewGeneration
    ) -> BridgeContentHandle {
        let wholeSHA256 = reviewContentSHA256(content)
        return BridgeContentHandle(
            handleId: "review-handle-1",
            itemId: "review-item-1",
            role: .head,
            endpointId: "review-head-endpoint",
            reviewGeneration: reviewGeneration,
            contentHash: "sha256:\(wholeSHA256)",
            contentHashAlgorithm: "sha256",
            cacheKey: "review-content-cache-\(reviewGeneration.rawValue)",
            mimeType: "text/plain",
            language: "swift",
            sizeBytes: content.count,
            isBinary: false
        )
    }

    private static func makeResult(
        handle: BridgeContentHandle,
        content: Data
    ) -> BridgeContentLoadResult {
        BridgeContentLoadResult(
            handle: handle,
            data: content,
            mimeType: handle.mimeType,
            contentHash: handle.contentHash,
            contentHashAlgorithm: handle.contentHashAlgorithm
        )
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
            revision: handle.reviewGeneration.rawValue,
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

private enum ReviewProductContentFixtureError: Error {
    case unexpectedContentKind
}

private func reviewContentSHA256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
