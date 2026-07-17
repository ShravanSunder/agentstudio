import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Bridge pane product Review metadata source")
struct BridgePaneProductReviewMetadataSourceTests {
    @Test("opens with source acceptance and byte-bounded windows covering 3,420 items")
    func opensWithCompleteOrderedWindows() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let package = makeReviewPackage(itemCount: 3420)
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()

        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await collector.append(event)
        }
        let outcome = try await deliverReviewPackage(
            package,
            through: source,
            productAdmission: productAdmission.context
        )
        let events = await collector.events

        #expect(events.count > 2)
        guard case .sourceAccepted(let accepted) = events.first else {
            Issue.record("Expected sourceAccepted before Review metadata windows")
            return
        }
        #expect(accepted.identity == reviewIdentity(for: package))
        let receipt = try deliveredReviewReceipt(outcome)
        #expect(receipt.finalFrames == [.init(sequence: events.count, subscriptionId: "review-subscription-1")])

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

    @Test("same revision update is a no-op and one changed package emits a bounded delta")
    func updatesWithMinimalLineageCorrectDelta() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let initialPackage = makeReviewPackage(itemCount: 32)
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        let initialSubscription = try reviewSubscription()
        try await source.open(
            subscription: initialSubscription, productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await collector.append(event)
        }
        _ = try await deliverReviewPackage(
            initialPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        await collector.removeAll()

        try await source.update(
            subscription: try reviewSubscription(interestRevision: 1), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await collector.append(event)
        }
        #expect(await collector.events.isEmpty)

        let changedItemId = try #require(initialPackage.orderedItemIds.first)
        let changedPackage = replacingReviewItem(
            in: initialPackage,
            itemId: changedItemId,
            fileClass: .config,
            revision: initialPackage.revision + 1
        )
        _ = try await deliverReviewPackage(
            changedPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        let events = await collector.events

        #expect(events.count == 1)
        guard case .delta(let delta) = events.first else {
            Issue.record("Expected one Review delta")
            return
        }
        #expect(delta.fromRevision == initialPackage.revision)
        #expect(delta.toRevision == changedPackage.revision)
        #expect(delta.identity.revision == delta.toRevision)
        let upsertedItemIds = delta.operations.compactMap { operation -> String? in
            guard case .upsertItem(let item) = operation else { return nil }
            return item.itemId
        }
        #expect(upsertedItemIds == [changedItemId])
        #expect(delta.operations.count <= 3)
        #expect(try JSONEncoder().encode(BridgeProductReviewMetadataEvent.delta(delta)).count <= 128 * 1024)
    }

    @Test("delta and replay retain the exact committed successor publication identity")
    func deltaAndReplayRetainExactSuccessorPublicationIdentity() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        let subscription = try reviewSubscription()
        let publicationAId = reviewMetadataTestPublicationId
        let publicationBId = UUID(uuidString: "33333333-3333-7333-8333-333333333333")!
        let publicationA = makeReviewPackage(itemCount: 4)
        let changedItemId = try #require(publicationA.orderedItemIds.first)
        let publicationB = replacingReviewItem(
            in: publicationA,
            itemId: changedItemId,
            fileClass: .config,
            revision: publicationA.revision + 1
        )
        try await source.open(
            subscription: subscription,
            productAdmission: productAdmission.context
        ) { event, _ in
            try await collector.append(event)
        }
        _ = try await deliverReviewPackage(
            publicationA,
            publicationId: publicationAId,
            through: source,
            productAdmission: productAdmission.context
        )
        await collector.removeAll()

        // Act
        _ = try await deliverReviewPackage(
            publicationB,
            publicationId: publicationBId,
            through: source,
            productAdmission: productAdmission.context
        )
        let deltaEvents = await collector.events
        await source.cancel(subscriptionId: subscription.subscriptionId)
        await collector.removeAll()
        try await source.open(
            subscription: subscription,
            productAdmission: productAdmission.context
        ) { event, _ in
            try await collector.append(event)
        }
        _ = try await deliverReviewPackage(
            publicationB,
            publicationId: publicationBId,
            through: source,
            productAdmission: productAdmission.context
        )
        let replayEvents = await collector.events

        // Assert
        #expect(deltaEvents.count == 1)
        #expect(deltaEvents.allSatisfy { $0.publicationId == publicationBId })
        #expect(replayEvents.count == 2)
        #expect(replayEvents.allSatisfy { $0.publicationId == publicationBId })
    }

    @Test("source identity replacement resets, accepts, and snapshots the replacement")
    func resetsAndSnapshotsReplacementSource() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let initialPackage = makeReviewPackage(itemCount: 4)
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await collector.append(event)
        }
        _ = try await deliverReviewPackage(
            initialPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        await collector.removeAll()

        let replacementPackage = replacingReviewSource(
            initialPackage,
            packageId: "review-package-2",
            queryId: "review-query-2",
            generation: initialPackage.reviewGeneration.rawValue + 1
        )
        _ = try await deliverReviewPackage(
            replacementPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        let events = await collector.events

        #expect(events.count >= 3)
        guard case .reset(let reset) = events[0],
            case .sourceAccepted(let accepted) = events[1],
            case .snapshot(let snapshot) = events[2]
        else {
            Issue.record("Expected reset, sourceAccepted, then replacement snapshot")
            return
        }
        let replacementIdentity = reviewIdentity(for: replacementPackage)
        #expect(reset.identity == replacementIdentity)
        #expect(accepted.identity == replacementIdentity)
        #expect(snapshot.identity == replacementIdentity)
    }

    @Test("contract-unsafe same-source delta resets and snapshots instead")
    func resetsInsteadOfEmittingOversizedDeltaMembers() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let initialPackage = makeReviewPackage(itemCount: 4097, includesContentRoles: false)
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await collector.append(event)
        }
        _ = try await deliverReviewPackage(
            initialPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        await collector.removeAll()

        let replacementPackage = replacingReviewPackage(
            initialPackage,
            revision: initialPackage.revision + 1,
            itemsById: [:]
        )
        _ = try await deliverReviewPackage(
            replacementPackage,
            through: source,
            productAdmission: productAdmission.context
        )
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
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let package = makeReviewPackage(itemCount: 128)
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        let subscription = try reviewSubscription()

        try await source.open(
            subscription: subscription, productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            let enqueueResult = try await collector.append(event)
            if case .sourceAccepted = event {
                await source.cancel(subscriptionId: subscription.subscriptionId)
            }
            return enqueueResult
        }
        _ = try await deliverReviewPackage(
            package,
            through: source,
            productAdmission: productAdmission.context
        )

        #expect(await collector.events.count == 1)
    }

    @Test("open before package publication stays pending and publishes initial metadata later")
    func openBeforePackagePublicationPublishesInitialMetadataLater() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        // Arrange
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        let subscription = try reviewSubscription()

        // Act
        try await source.open(
            subscription: subscription, productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await collector.append(event)
        }
        let eventsBeforePublication = await collector.events
        let reviewPackage = makeReviewPackage(itemCount: 4)
        let outcome = try await deliverReviewPackage(
            reviewPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        let eventsAfterPublication = await collector.events

        // Assert
        #expect(eventsBeforePublication.isEmpty)
        guard case .delivered(let receipt) = outcome else {
            Issue.record("Expected delivered Review metadata publication receipt")
            return
        }
        #expect(receipt.retained == 1)
        #expect(receipt.publishedSubscriptions == 1)
        #expect(receipt.emittedEvents == 2)
        #expect(receipt.superseded == 0)
        guard case .sourceAccepted(let accepted) = eventsAfterPublication.first,
            case .snapshot(let snapshot) = eventsAfterPublication.dropFirst().first
        else {
            Issue.record("Expected first package publication to emit sourceAccepted then snapshot")
            return
        }
        #expect(accepted.identity == reviewIdentity(for: reviewPackage))
        #expect(snapshot.identity == reviewIdentity(for: reviewPackage))
    }

    @Test("cancelling a pending open prevents current and replacement package publication")
    func cancellationBeforePackagePublicationLeavesNoPendingResidue() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        // Arrange
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        let subscription = try reviewSubscription()
        try await source.open(
            subscription: subscription, productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await collector.append(event)
        }

        // Act
        await source.cancel(subscriptionId: subscription.subscriptionId)
        let initialPackage = makeReviewPackage(itemCount: 4)
        let outcome = try await deliverReviewPackage(
            initialPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        let replacementPackage = replacingReviewSource(
            initialPackage,
            packageId: "review-package-after-cancel",
            queryId: "review-query-after-cancel",
            generation: initialPackage.reviewGeneration.rawValue + 1
        )
        _ = try await deliverReviewPackage(
            replacementPackage,
            through: source,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(outcome == .deferred(retained: 0))
        #expect(await collector.events.isEmpty)
    }

    @Test("a newer pending open supersedes the older sink before package publication")
    func newerPendingOpenSupersedesOlderSink() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        // Arrange
        let source = BridgePaneProductReviewMetadataSource()
        let supersededCollector = ReviewMetadataEventCollector()
        let currentCollector = ReviewMetadataEventCollector()
        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await supersededCollector.append(event)
        }
        try await source.open(
            subscription: try reviewSubscription(interestRevision: 1), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await currentCollector.append(event)
        }

        // Act
        let reviewPackage = makeReviewPackage(itemCount: 4)
        _ = try await deliverReviewPackage(
            reviewPackage,
            through: source,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(await supersededCollector.events.isEmpty)
        guard case .sourceAccepted = await currentCollector.events.first else {
            Issue.record("Expected only the newest pending open to receive package publication")
            return
        }
    }

    @Test("same-package retry after second-frame failure replays a complete publication")
    func samePackageRetryAfterSecondFrameFailureReplaysCompletePublication() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        // Arrange
        let source = BridgePaneProductReviewMetadataSource()
        let sink = ReviewMetadataSecondFrameFailureSink()
        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await sink.receive(event)
        }
        let reviewPackage = makeReviewPackage(itemCount: 4)

        // Act
        do {
            _ = try await deliverReviewPackage(
                reviewPackage,
                through: source,
                productAdmission: productAdmission.context
            )
            Issue.record("Expected the injected second-frame sink failure")
        } catch {
            #expect(error as? ReviewMetadataInjectedSinkError == .secondFrame)
        }
        let successfulEventCountAfterFailure = await sink.successfulEvents.count
        _ = try await deliverReviewPackage(
            reviewPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        let retryEvents = await sink.successfulEvents.dropFirst(successfulEventCountAfterFailure)

        // Assert
        guard case .sourceAccepted = retryEvents.first,
            case .snapshot = retryEvents.dropFirst().first
        else {
            Issue.record("Expected retry to replay sourceAccepted and the initial snapshot")
            return
        }
    }

    @Test("subscription update preserves its delivered cursor for replacement reset")
    func subscriptionUpdatePreservesDeliveredCursorForReplacementReset() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        // Arrange
        let initialPackage = makeReviewPackage(itemCount: 4)
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await collector.append(event)
        }
        _ = try await deliverReviewPackage(
            initialPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        await collector.removeAll()

        // Act
        try await source.update(
            subscription: try reviewSubscription(interestRevision: 1), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await collector.append(event)
        }
        let replacementPackage = replacingReviewSource(
            initialPackage,
            packageId: "review-package-after-loading",
            queryId: "review-query-after-loading",
            generation: initialPackage.reviewGeneration.rawValue + 1
        )
        _ = try await deliverReviewPackage(
            replacementPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        let events = await collector.events

        // Assert
        guard case .reset(let reset) = events.first,
            case .sourceAccepted(let accepted) = events.dropFirst().first,
            case .snapshot = events.dropFirst(2).first
        else {
            Issue.record("Expected replacement reset from the subscription delivery cursor")
            return
        }
        #expect(reset.identity == reviewIdentity(for: replacementPackage))
        #expect(accepted.identity == reviewIdentity(for: replacementPackage))
    }

    @Test("reservation does not create global package availability before explicit delivery")
    func reservationDoesNotCreateGlobalPackageAvailability() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        // Arrange
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        let subscription = try reviewSubscription()
        let reviewPackage = makeReviewPackage(itemCount: 4)

        let reservation = try await source.reserve(
            package: reviewPackage,
            publicationId: reviewMetadataTestPublicationId,
            productAdmission: productAdmission.context
        )

        // Act
        try await source.open(
            subscription: subscription, productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await collector.append(event)
        }
        let eventsBeforeDelivery = await collector.events
        _ = try await source.deliver(
            package: reviewPackage,
            reservation: reservation,
            productAdmission: productAdmission.context
        )
        let events = await collector.events

        // Assert
        #expect(eventsBeforeDelivery.isEmpty)
        guard case .sourceAccepted(let accepted) = events.first,
            case .snapshot(let snapshot) = events.dropFirst().first
        else {
            Issue.record("Expected racing open and ready publication to converge on initial metadata")
            return
        }
        #expect(accepted.identity == reviewIdentity(for: reviewPackage))
        #expect(snapshot.identity == reviewIdentity(for: reviewPackage))
    }

    @Test("overlapping ready publication cannot emit or commit stale package after replacement")
    func overlappingReadyPublicationCannotRollBackReplacement() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        // Arrange
        let initialPackage = makeReviewPackage(itemCount: 4)
        let source = BridgePaneProductReviewMetadataSource()
        let sink = ReviewMetadataOverlappingPublicationSink()
        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await sink.receive(event)
        }
        _ = try await deliverReviewPackage(
            initialPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        await sink.removeAll()
        let publicationA = replacingReviewSource(
            initialPackage,
            packageId: "review-package-overlap-a",
            queryId: "review-query-overlap-a",
            generation: initialPackage.reviewGeneration.rawValue + 1
        )
        let publicationB = replacingReviewSource(
            initialPackage,
            packageId: "review-package-overlap-b",
            queryId: "review-query-overlap-b",
            generation: initialPackage.reviewGeneration.rawValue + 2
        )
        await sink.suspendFirstEvent(packageId: publicationA.packageId)

        // Act
        let publishingA = Task {
            _ = try await deliverReviewPackage(
                publicationA,
                through: source,
                productAdmission: productAdmission.context
            )
        }
        await sink.waitUntilSuspended()
        _ = try await deliverReviewPackage(
            publicationB,
            through: source,
            productAdmission: productAdmission.context
        )
        await sink.releaseSuspendedEvent()
        try await publishingA.value
        let overlappingEvents = await sink.events
        let firstPublicationBIndex = try #require(
            overlappingEvents.firstIndex { $0.packageId == publicationB.packageId }
        )
        let stalePublicationAAfterB =
            overlappingEvents
            .dropFirst(firstPublicationBIndex + 1)
            .contains { $0.packageId == publicationA.packageId }
        let eventCountBeforeRepublishingB = overlappingEvents.count
        _ = try await deliverReviewPackage(
            publicationB,
            through: source,
            productAdmission: productAdmission.context
        )
        let eventCountAfterRepublishingB = await sink.events.count

        // Assert
        #expect(!stalePublicationAAfterB)
        #expect(eventCountAfterRepublishingB == eventCountBeforeRepublishingB)
    }

    @Test("reservation rejects an invalid package before any delivery")
    func reservationRejectsInvalidPackageBeforeDelivery() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        try await source.open(
            subscription: try reviewSubscription(),
            productAdmission: productAdmission.context
        ) { event, _ in
            try await collector.append(event)
        }
        let validPackage = makeReviewPackage(itemCount: 4)
        let invalidPackage = replacingReviewSource(
            validPackage,
            packageId: "review-package-invalid-reservation",
            queryId: "review-query-invalid-reservation",
            generation: -1
        )

        // Act / Assert
        await #expect(throws: DecodingError.self) {
            _ = try await source.reserve(
                package: invalidPackage,
                publicationId: reviewMetadataTestPublicationId,
                productAdmission: productAdmission.context
            )
        }
        #expect(await collector.events.isEmpty)
    }

    @Test("closing admission while the metadata sink is suspended prevents its commit")
    func closeDuringMetadataSinkPreventsCommit() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let source = BridgePaneProductReviewMetadataSource()
        let sink = ReviewMetadataAdmissionFencedSink()
        let subscription = try reviewSubscription()
        try await source.open(
            subscription: subscription,
            productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            try await sink.receive(event, productAdmission: emittedProductAdmission)
        }
        let reviewPackage = makeReviewPackage(itemCount: 4)

        // Act
        let publication = Task {
            try await deliverReviewPackage(
                reviewPackage,
                through: source,
                productAdmission: productAdmission.context
            )
        }
        await sink.waitUntilSuspended()
        productAdmission.close()
        await sink.releaseSuspendedEvent()
        let outcome = try await publication.value
        await source.cancel(subscriptionId: subscription.subscriptionId)

        // Assert
        #expect(await sink.committedEvents.isEmpty)
        guard case .delivered(let receipt) = outcome else {
            Issue.record("Expected a superseded delivered publication receipt")
            return
        }
        #expect(receipt.publishedSubscriptions == 0)
        #expect(receipt.emittedEvents == 0)
        #expect(receipt.superseded == 1)
    }
}

private enum ReviewMetadataInjectedSinkError: Error, Equatable {
    case secondFrame
}

private actor ReviewMetadataSecondFrameFailureSink {
    private var receivedEventCount = 0
    private(set) var successfulEvents: [BridgeProductReviewMetadataEvent] = []

    func receive(_ event: BridgeProductReviewMetadataEvent) throws -> BridgeProductProducerEnqueueResult {
        receivedEventCount += 1
        if receivedEventCount == 2 {
            throw ReviewMetadataInjectedSinkError.secondFrame
        }
        successfulEvents.append(event)
        return try reviewMetadataEnqueueResult(event, sequence: receivedEventCount)
    }
}

private actor ReviewMetadataOverlappingPublicationSink {
    private(set) var events: [BridgeProductReviewMetadataEvent] = []
    private var nextSequence = 0
    private var suspendedPackageId: String?
    private var suspensionStarted = false
    private var suspensionStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspensionRelease: CheckedContinuation<Void, Never>?

    func receive(_ event: BridgeProductReviewMetadataEvent) async throws -> BridgeProductProducerEnqueueResult {
        nextSequence += 1
        let sequence = nextSequence
        events.append(event)
        if event.packageId == suspendedPackageId, !suspensionStarted {
            suspensionStarted = true
            let waiters = suspensionStartedWaiters
            suspensionStartedWaiters.removeAll(keepingCapacity: false)
            for waiter in waiters { waiter.resume() }
            await withCheckedContinuation { continuation in
                suspensionRelease = continuation
            }
        }
        return try reviewMetadataEnqueueResult(event, sequence: sequence)
    }

    func removeAll() {
        events.removeAll(keepingCapacity: false)
    }

    func suspendFirstEvent(packageId: String) {
        suspendedPackageId = packageId
    }

    func waitUntilSuspended() async {
        if suspensionStarted { return }
        await withCheckedContinuation { continuation in
            suspensionStartedWaiters.append(continuation)
        }
    }

    func releaseSuspendedEvent() {
        suspensionRelease?.resume()
        suspensionRelease = nil
    }
}

private actor ReviewMetadataAdmissionFencedSink {
    private(set) var committedEvents: [BridgeProductReviewMetadataEvent] = []
    private var nextSequence = 0
    private var suspensionStarted = false
    private var suspensionStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspensionRelease: CheckedContinuation<Void, Never>?

    func receive(
        _ event: BridgeProductReviewMetadataEvent,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgeProductProducerEnqueueResult {
        nextSequence += 1
        suspensionStarted = true
        let waiters = suspensionStartedWaiters
        suspensionStartedWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            suspensionRelease = continuation
        }
        _ = productAdmission.withValidAdmission {
            committedEvents.append(event)
        }
        return try reviewMetadataEnqueueResult(event, sequence: nextSequence)
    }

    func waitUntilSuspended() async {
        if suspensionStarted { return }
        await withCheckedContinuation { continuation in
            suspensionStartedWaiters.append(continuation)
        }
    }

    func releaseSuspendedEvent() {
        suspensionRelease?.resume()
        suspensionRelease = nil
    }
}

private actor ReviewMetadataEventCollector {
    private(set) var events: [BridgeProductReviewMetadataEvent] = []
    private var nextSequence = 0

    func append(_ event: BridgeProductReviewMetadataEvent) throws -> BridgeProductProducerEnqueueResult {
        nextSequence += 1
        events.append(event)
        return try reviewMetadataEnqueueResult(event, sequence: nextSequence)
    }

    func removeAll() {
        events.removeAll()
    }
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
