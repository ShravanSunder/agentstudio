import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Bridge Review publication coordinator")
struct BridgeReviewPublicationCoordinatorTests {
    @Test("invalid candidates are rejected during off-main preparation")
    func invalidCandidatesAreRejectedDuringOffMainPreparation() async {
        // Arrange
        let candidate = makeReviewPublicationCandidate(suffix: "invalid", reviewGeneration: 1)
        let invalidCandidate = BridgeReviewPublicationCandidate(
            package: candidate.package,
            delta: candidate.delta,
            contentHandles: []
        )

        // Act
        let preparedPublication = await BridgeReviewPreparedPublication.prepare(invalidCandidate)

        // Assert
        #expect(preparedPublication == nil)
    }

    @Test("reservation rejection preserves active package and descriptor authority")
    func reservationRejectionPreservesActivePackageAndDescriptorAuthority() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(suffix: "a", reviewGeneration: 1)
        let publicationB = try await makeReviewPreparedPublication(suffix: "b", reviewGeneration: 2)
        _ = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let candidateToken = try #require(
            coordinator.stage(
                publicationB,
                productAdmission: productAdmission.context
            )
        )

        // Act
        let rejectedOutcome = coordinator.rejectReservation(
            candidateToken,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(rejectedOutcome == .rejectedBeforeCommit)
        let snapshot = coordinator.diagnosticSnapshot
        #expect(snapshot.active?.packageId == publicationA.package.packageId)
        #expect(snapshot.pending == nil)
        #expect(
            coordinator.activeContentHandle(
                handleId: publicationA.contentHandles[0].handleId,
                requestedGeneration: publicationA.package.reviewGeneration,
                productAdmission: productAdmission.context
            ) == publicationA.contentHandles[0]
        )
        #expect(
            coordinator.activeContentHandle(
                handleId: publicationB.contentHandles[0].handleId,
                requestedGeneration: publicationB.package.reviewGeneration,
                productAdmission: productAdmission.context
            ) == nil
        )
    }

    @Test("synchronous commit activates B and presents pane B before delivery")
    func synchronousCommitActivatesBAndPresentsPaneBBeforeDelivery() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(
            suffix: "commit-a",
            reviewGeneration: 1
        )
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "commit-b",
            reviewGeneration: 2
        )
        _ = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let candidateToken = try #require(
            coordinator.stage(
                publicationB,
                productAdmission: productAdmission.context
            )
        )
        var panePackageId: String?
        var deliveryAttemptStarted = false

        // Act
        let commitResult = coordinator.commit(
            candidateToken,
            productAdmission: productAdmission.context
        ) { committedPublication in
            #expect(
                coordinator.diagnosticSnapshot.active?.packageId
                    == publicationB.package.packageId
            )
            #expect(!deliveryAttemptStarted)
            panePackageId = committedPublication.package.packageId
        }
        let committedPublication = try #require(commitResult.committedPublication)
        deliveryAttemptStarted = true
        let deliveryOutcome = coordinator.recordTransportDeliveryDisposition(
            .transportAcknowledged,
            publicationId: committedPublication.publicationId,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(panePackageId == publicationB.package.packageId)
        #expect(committedPublication.package == publicationB.package)
        #expect(deliveryOutcome == .committed(delivery: .transportAcknowledged))
    }

    @Test(
        "post-commit non-observation retains native B for replay",
        arguments: [
            BridgeReviewPublicationDeliveryDisposition.failed,
            .deferred,
        ]
    )
    func postCommitNonObservationRetainsNativeBForReplay(
        _ deliveryDisposition: BridgeReviewPublicationDeliveryDisposition
    ) async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(
            suffix: "failure-a",
            reviewGeneration: 1
        )
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "failure-b",
            reviewGeneration: 2
        )
        _ = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let candidateToken = try #require(
            coordinator.stage(
                publicationB,
                productAdmission: productAdmission.context
            )
        )
        let committedPublication = try #require(
            coordinator.commit(
                candidateToken,
                productAdmission: productAdmission.context,
                presentCommitted: { _ in }
            ).committedPublication
        )

        // Act
        let deliveryOutcome = coordinator.recordTransportDeliveryDisposition(
            deliveryDisposition,
            publicationId: committedPublication.publicationId,
            productAdmission: productAdmission.context
        )
        let replay = coordinator.committedPublicationForReplay(
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(deliveryOutcome == .committed(delivery: deliveryDisposition))
        #expect(replay == committedPublication)
        #expect(coordinator.diagnosticSnapshot.active?.packageId == publicationB.package.packageId)
    }

    @Test("close while staged invalidates the candidate synchronously")
    func closeWhileStagedInvalidatesCandidateSynchronously() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publication = try await makeReviewPreparedPublication(
            suffix: "staged-close",
            reviewGeneration: 1
        )
        let token = try #require(
            coordinator.stage(
                publication,
                productAdmission: productAdmission.context
            )
        )

        // Act
        productAdmission.close()
        coordinator.close()
        let commitResult = coordinator.commit(
            token,
            productAdmission: productAdmission.context,
            presentCommitted: { _ in
                Issue.record("A post-close candidate must not reach pane presentation")
            }
        )

        // Assert
        #expect(commitResult == .closed)
        #expect(coordinator.diagnosticSnapshot == .closed)
    }

    @Test("close after commit clears publication authority synchronously")
    func closeAfterCommitClearsPublicationAuthoritySynchronously() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publication = try await makeReviewPreparedPublication(
            suffix: "committed-close",
            reviewGeneration: 1
        )
        let token = try #require(
            coordinator.stage(
                publication,
                productAdmission: productAdmission.context
            )
        )
        let committedPublication = try #require(
            coordinator.commit(
                token,
                productAdmission: productAdmission.context,
                presentCommitted: { _ in }
            ).committedPublication
        )

        // Act
        productAdmission.close()
        coordinator.close()
        let deliveryOutcome = coordinator.recordTransportDeliveryDisposition(
            .transportAcknowledged,
            publicationId: committedPublication.publicationId,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(deliveryOutcome == .closed)
        #expect(coordinator.diagnosticSnapshot == .closed)
        #expect(
            coordinator.committedPublicationForReplay(
                productAdmission: productAdmission.context
            ) == nil
        )
    }

    @Test("newer stage supersedes an older candidate")
    func newerStageSupersedesOlderCandidate() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "older",
            reviewGeneration: 2
        )
        let publicationC = try await makeReviewPreparedPublication(
            suffix: "newer",
            reviewGeneration: 3
        )
        let olderToken = try #require(
            coordinator.stage(
                publicationB,
                productAdmission: productAdmission.context
            )
        )

        // Act
        let newerToken = try #require(
            coordinator.stage(
                publicationC,
                productAdmission: productAdmission.context
            )
        )
        let olderCommitResult = coordinator.commit(
            olderToken,
            productAdmission: productAdmission.context,
            presentCommitted: { _ in
                Issue.record("A superseded candidate must not reach pane presentation")
            }
        )

        // Assert
        #expect(olderCommitResult == .superseded)
        #expect(olderToken != newerToken)
        let snapshot = coordinator.diagnosticSnapshot
        #expect(snapshot.active == nil)
        #expect(snapshot.pending?.packageId == publicationC.package.packageId)
        #expect(snapshot.retiring.isEmpty)
    }

    @Test("prepared older lineage cannot replace committed newer authority")
    func preparedOlderLineageCannotReplaceCommittedNewerAuthority() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let delayedOlderPublication = try await makeReviewPreparedPublication(
            suffix: "delayed-older",
            reviewGeneration: 1
        )
        let newerPublication = try await makeReviewPreparedPublication(
            suffix: "committed-newer",
            reviewGeneration: 2
        )
        let committedNewerPublication = try commitObserved(
            newerPublication,
            in: coordinator,
            productAdmission: productAdmission.context
        )

        // Act
        let delayedOlderToken = coordinator.stage(
            delayedOlderPublication,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(delayedOlderToken == nil)
        #expect(
            coordinator.committedPublicationForReplay(
                productAdmission: productAdmission.context
            ) == committedNewerPublication
        )
        #expect(coordinator.diagnosticSnapshot.pending == nil)
    }

    @Test("same lineage may advance its committed revision")
    func sameLineageMayAdvanceItsCommittedRevision() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let initialPublication = try await makeReviewPreparedPublication(
            suffix: "revision",
            reviewGeneration: 1,
            revision: 0
        )
        let revisedPublication = try await makeReviewPreparedPublication(
            suffix: "revision",
            reviewGeneration: 1,
            revision: 1
        )
        _ = try commitObserved(
            initialPublication,
            in: coordinator,
            productAdmission: productAdmission.context
        )

        // Act
        let revisedPublicationToken = try #require(
            coordinator.stage(
                revisedPublication,
                productAdmission: productAdmission.context
            )
        )
        let revisedCommit = coordinator.commit(
            revisedPublicationToken,
            productAdmission: productAdmission.context,
            presentCommitted: { _ in }
        )

        // Assert
        #expect(revisedCommit.committedPublication?.package.revision == 1)
        #expect(coordinator.diagnosticSnapshot.active?.revision == 1)
    }

    @Test("same lineage equal revision cannot stage a distinct publication")
    func sameLineageEqualRevisionCannotStageDistinctPublication() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let initialPublication = try await makeReviewPreparedPublication(
            suffix: "equal-revision",
            reviewGeneration: 1,
            revision: 3
        )
        let committedPublication = try commitObserved(
            initialPublication,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let equalRevisionPublication = try await makeReviewPreparedPublication(
            suffix: "equal-revision",
            reviewGeneration: 1,
            revision: 3
        )

        // Act
        let equalRevisionToken = coordinator.stage(
            equalRevisionPublication,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(equalRevisionToken == nil)
        #expect(coordinator.diagnosticSnapshot.pending == nil)
        #expect(
            coordinator.committedPublicationForReplay(
                productAdmission: productAdmission.context
            ) == committedPublication
        )
    }

    @Test("superseded publication cannot begin delayed delivery")
    func supersededPublicationCannotBeginDelayedDelivery() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let deliveryGate = BridgeReviewPublicationDeliveryGate()
        let deliveryProbe = BridgeReviewPublicationDeliveryProbe()
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "delivery-b",
            reviewGeneration: 2
        )
        let publicationC = try await makeReviewPreparedPublication(
            suffix: "delivery-c",
            reviewGeneration: 3
        )
        let committedB = try commitObserved(
            publicationB,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let delayedDelivery = Task { @MainActor in
            await deliveryGate.waitUntilReleased()
            guard
                coordinator.isCurrentPublication(
                    publicationId: committedB.publicationId,
                    productAdmission: productAdmission.context
                )
            else {
                return
            }
            await deliveryProbe.recordDelivery(publicationId: committedB.publicationId)
        }
        await deliveryGate.waitUntilSuspended()

        // Act
        let committedC = try commitObserved(
            publicationC,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        await deliveryGate.release()
        await delayedDelivery.value

        // Assert
        #expect(await deliveryProbe.deliveredPublicationIds().isEmpty)
        #expect(
            coordinator.committedPublicationForReplay(
                productAdmission: productAdmission.context
            ) == committedC
        )
    }

    @Test("exact B application retires A while frozen A leases remain settleable")
    func bApplicationRetiresAWhileFrozenALeasesRemainSettleable() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(
            suffix: "observed-a",
            reviewGeneration: 1
        )
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "observed-b",
            reviewGeneration: 2
        )
        _ = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let leaseA = try #require(
            coordinator.acquireContentLease(
                handleId: publicationA.contentHandles[0].handleId,
                packageId: publicationA.package.packageId,
                requestedGeneration: publicationA.package.reviewGeneration,
                sourceIdentity: publicationA.package.query.queryId,
                productAdmission: productAdmission.context
            )
        )
        let tokenB = try #require(
            coordinator.stage(
                publicationB,
                productAdmission: productAdmission.context
            )
        )
        let committedB = try #require(
            coordinator.commit(
                tokenB,
                productAdmission: productAdmission.context,
                presentCommitted: { _ in }
            ).committedPublication
        )
        #expect(coordinator.diagnosticSnapshot.retiring.map(\.packageId) == [publicationA.package.packageId])

        // Act
        let transportOutcome = coordinator.recordTransportDeliveryDisposition(
            .transportAcknowledged,
            publicationId: committedB.publicationId,
            productAdmission: productAdmission.context
        )
        let retiringAfterTransport = coordinator.diagnosticSnapshot.retiring
        let applicationRecorded = coordinator.recordWorkerApplication(
            publicationId: committedB.publicationId,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(transportOutcome == .committed(delivery: .transportAcknowledged))
        #expect(retiringAfterTransport.map(\.packageId) == [publicationA.package.packageId])
        #expect(applicationRecorded)
        #expect(coordinator.diagnosticSnapshot.retiring.isEmpty)
        #expect(coordinator.diagnosticSnapshot.activeContentLeaseCount == 1)
        #expect(coordinator.settleContentLease(leaseA))
        #expect(coordinator.diagnosticSnapshot.activeContentLeaseCount == 0)
    }

    @Test("only exact current C application retires all prior authority after A to B to C")
    func exactCurrentCApplicationRetiresAllPriorAuthority() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(
            suffix: "chain-a",
            reviewGeneration: 1
        )
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "chain-b",
            reviewGeneration: 2
        )
        let publicationC = try await makeReviewPreparedPublication(
            suffix: "chain-c",
            reviewGeneration: 3
        )
        _ = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let leaseA = try #require(
            coordinator.acquireContentLease(
                handleId: publicationA.contentHandles[0].handleId,
                packageId: publicationA.package.packageId,
                requestedGeneration: publicationA.package.reviewGeneration,
                sourceIdentity: publicationA.package.query.queryId,
                productAdmission: productAdmission.context
            )
        )
        let committedB = try commitObserved(
            publicationB,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let committedC = try commitObserved(
            publicationC,
            in: coordinator,
            productAdmission: productAdmission.context
        )

        // Act
        let delayedBApplication = coordinator.recordWorkerApplication(
            publicationId: committedB.publicationId,
            productAdmission: productAdmission.context
        )
        let retiringAfterStaleB = coordinator.diagnosticSnapshot.retiring
        let currentCApplication = coordinator.recordWorkerApplication(
            publicationId: committedC.publicationId,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(!delayedBApplication)
        #expect(retiringAfterStaleB.map(\.packageId) == [publicationA.package.packageId])
        #expect(currentCApplication)
        #expect(coordinator.diagnosticSnapshot.retiring.isEmpty)
        #expect(coordinator.diagnosticSnapshot.activeContentLeaseCount == 1)
        #expect(coordinator.settleContentLease(leaseA))
        #expect(coordinator.diagnosticSnapshot.activeContentLeaseCount == 0)
    }

    @Test("final frozen pre-commit A lease settlement retires A")
    func finalFrozenPreCommitALeaseSettlementRetiresA() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(
            suffix: "settle-a",
            reviewGeneration: 1
        )
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "settle-b",
            reviewGeneration: 2
        )
        _ = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let firstLeaseA = try #require(
            coordinator.acquireContentLease(
                handleId: publicationA.contentHandles[0].handleId,
                packageId: publicationA.package.packageId,
                requestedGeneration: publicationA.package.reviewGeneration,
                sourceIdentity: publicationA.package.query.queryId,
                productAdmission: productAdmission.context
            )
        )
        let secondLeaseA = try #require(
            coordinator.acquireContentLease(
                handleId: publicationA.contentHandles[0].handleId,
                packageId: publicationA.package.packageId,
                requestedGeneration: publicationA.package.reviewGeneration,
                sourceIdentity: publicationA.package.query.queryId,
                productAdmission: productAdmission.context
            )
        )
        let tokenB = try #require(
            coordinator.stage(
                publicationB,
                productAdmission: productAdmission.context
            )
        )
        _ = try #require(
            coordinator.commit(
                tokenB,
                productAdmission: productAdmission.context,
                presentCommitted: { _ in }
            ).committedPublication
        )

        // Act
        let firstSettlement = coordinator.settleContentLease(firstLeaseA)
        let retiringAfterFirstSettlement = coordinator.diagnosticSnapshot.retiring
        let finalSettlement = coordinator.settleContentLease(secondLeaseA)

        // Assert
        #expect(firstSettlement)
        #expect(retiringAfterFirstSettlement.map(\.packageId) == [publicationA.package.packageId])
        #expect(finalSettlement)
        #expect(coordinator.diagnosticSnapshot.retiring.isEmpty)
        #expect(coordinator.diagnosticSnapshot.active?.packageId == publicationB.package.packageId)
    }

    @Test("no new A lease may be minted after B commits")
    func noNewALeaseMayBeMintedAfterBCommits() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(
            suffix: "lease-a",
            reviewGeneration: 1
        )
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "lease-b",
            reviewGeneration: 2
        )
        _ = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let admittedLeaseA = try #require(
            coordinator.acquireContentLease(
                handleId: publicationA.contentHandles[0].handleId,
                packageId: publicationA.package.packageId,
                requestedGeneration: publicationA.package.reviewGeneration,
                sourceIdentity: publicationA.package.query.queryId,
                productAdmission: productAdmission.context
            )
        )
        let tokenB = try #require(
            coordinator.stage(
                publicationB,
                productAdmission: productAdmission.context
            )
        )
        _ = try #require(
            coordinator.commit(
                tokenB,
                productAdmission: productAdmission.context,
                presentCommitted: { _ in }
            ).committedPublication
        )

        // Act
        let rejectedLeaseA = coordinator.acquireContentLease(
            handleId: publicationA.contentHandles[0].handleId,
            packageId: publicationA.package.packageId,
            requestedGeneration: publicationA.package.reviewGeneration,
            sourceIdentity: publicationA.package.query.queryId,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(rejectedLeaseA == nil)
        #expect(coordinator.settleContentLease(admittedLeaseA))
        #expect(!coordinator.settleContentLease(admittedLeaseA))
    }
}

extension BridgeReviewPublicationStateSnapshot {
    fileprivate static let closed = Self(
        active: nil,
        pending: nil,
        retiring: [],
        activeContentLeaseCount: 0,
        isClosed: true
    )
}

extension BridgeReviewPublicationCommitResult {
    fileprivate var committedPublication: BridgeReviewCommittedPublication? {
        guard case .committed(let committedPublication) = self else { return nil }
        return committedPublication
    }
}

@MainActor
private func commitObserved(
    _ publication: BridgeReviewPreparedPublication,
    in coordinator: BridgeReviewPublicationCoordinator,
    productAdmission: BridgeProductAdmissionContext
) throws -> BridgeReviewCommittedPublication {
    let token = try #require(
        coordinator.stage(
            publication,
            productAdmission: productAdmission
        )
    )
    let committedPublication = try #require(
        coordinator.commit(
            token,
            productAdmission: productAdmission,
            presentCommitted: { _ in }
        ).committedPublication
    )
    #expect(
        coordinator.recordTransportDeliveryDisposition(
            .transportAcknowledged,
            publicationId: committedPublication.publicationId,
            productAdmission: productAdmission
        ) == .committed(delivery: .transportAcknowledged)
    )
    return committedPublication
}

private func makeReviewPreparedPublication(
    suffix: String,
    reviewGeneration: BridgeReviewGeneration,
    revision: Int = 0
) async throws -> BridgeReviewPreparedPublication {
    let candidate = makeReviewPublicationCandidate(
        suffix: suffix,
        reviewGeneration: reviewGeneration
    )
    let revisedCandidate = BridgeReviewPublicationCandidate(
        package: candidate.package.withRevision(revision),
        delta: candidate.delta,
        contentHandles: candidate.contentHandles
    )
    return try #require(
        await BridgeReviewPreparedPublication.prepare(revisedCandidate)
    )
}

private func makeReviewPublicationCandidate(
    suffix: String,
    reviewGeneration: BridgeReviewGeneration
) -> BridgeReviewPublicationCandidate {
    let itemId = "item-\(suffix)"
    let baseEndpoint = makeBridgeEndpoint(
        endpointId: "base-\(suffix)",
        kind: .gitRef
    )
    let headEndpoint = makeBridgeEndpoint(
        endpointId: "head-\(suffix)",
        kind: .workingTree
    )
    let contentHandle = makeBridgeContentHandle(
        itemId: itemId,
        role: .head,
        endpointId: headEndpoint.endpointId,
        reviewGeneration: reviewGeneration,
        contentHash: bridgeSHA256ContentHash("contents-\(suffix)")
    )
    let item = makeBridgeReviewItemDescriptor(
        itemId: itemId,
        path: "Sources/\(suffix).swift",
        fileClass: .source,
        contentRoles: .init(base: nil, head: contentHandle, diff: nil)
    )
    let package = BridgeReviewPackage(
        packageId: "package-\(suffix)",
        schemaVersion: 1,
        reviewGeneration: reviewGeneration,
        revision: 0,
        query: makeBridgeReviewQuery(
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId
        ),
        baseEndpoint: baseEndpoint,
        headEndpoint: headEndpoint,
        orderedItemIds: [itemId],
        itemsById: [itemId: item],
        groups: [],
        summary: .init(
            filesChanged: 1,
            additions: 1,
            deletions: 0,
            visibleFileCount: 1,
            hiddenFileCount: 0
        ),
        filterState: BridgeViewFilter(),
        generatedAtUnixMilliseconds: 1
    )
    return BridgeReviewPublicationCandidate(
        package: package,
        delta: nil,
        contentHandles: [contentHandle]
    )
}

private actor BridgeReviewPublicationDeliveryGate {
    private var isSuspended = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilReleased() async {
        isSuspended = true
        let waiters = suspensionWaiters
        suspensionWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor BridgeReviewPublicationDeliveryProbe {
    private var publicationIds: [UUID] = []

    func recordDelivery(publicationId: UUID) {
        publicationIds.append(publicationId)
    }

    func deliveredPublicationIds() -> [UUID] {
        publicationIds
    }
}
