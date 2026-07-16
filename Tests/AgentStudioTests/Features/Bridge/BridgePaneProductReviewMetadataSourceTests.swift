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
        let packageBox = ReviewPackageBox(package)
        let source = BridgePaneProductReviewMetadataSource(initialAvailability: packageBox.availability)
        let collector = ReviewMetadataEventCollector()

        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
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

    @Test("same revision update is a no-op and one changed package emits a bounded delta")
    func updatesWithMinimalLineageCorrectDelta() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let initialPackage = makeReviewPackage(itemCount: 32)
        let packageBox = ReviewPackageBox(initialPackage)
        let source = BridgePaneProductReviewMetadataSource(initialAvailability: packageBox.availability)
        let collector = ReviewMetadataEventCollector()
        let initialSubscription = try reviewSubscription()
        try await source.open(
            subscription: initialSubscription, productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            await collector.append(event)
        }
        await collector.removeAll()

        try await source.update(
            subscription: try reviewSubscription(interestRevision: 1), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
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
        _ = try await source.publish(
            availability: packageBox.availability,
            productAdmission: productAdmission.context
        )
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
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let initialPackage = makeReviewPackage(itemCount: 4)
        let packageBox = ReviewPackageBox(initialPackage)
        let source = BridgePaneProductReviewMetadataSource(initialAvailability: packageBox.availability)
        let collector = ReviewMetadataEventCollector()
        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            await collector.append(event)
        }
        await collector.removeAll()

        packageBox.package = replacingReviewSource(
            initialPackage,
            packageId: "review-package-2",
            queryId: "review-query-2",
            generation: initialPackage.reviewGeneration.rawValue + 1
        )
        _ = try await source.publish(
            availability: packageBox.availability,
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
        let replacementIdentity = reviewIdentity(for: packageBox.package)
        #expect(reset.identity == replacementIdentity)
        #expect(accepted.identity == replacementIdentity)
        #expect(snapshot.identity == replacementIdentity)
    }

    @Test("contract-unsafe same-source delta resets and snapshots instead")
    func resetsInsteadOfEmittingOversizedDeltaMembers() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let initialPackage = makeReviewPackage(itemCount: 4097, includesContentRoles: false)
        let packageBox = ReviewPackageBox(initialPackage)
        let source = BridgePaneProductReviewMetadataSource(initialAvailability: packageBox.availability)
        let collector = ReviewMetadataEventCollector()
        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            await collector.append(event)
        }
        await collector.removeAll()

        packageBox.package = replacingReviewPackage(
            initialPackage,
            revision: initialPackage.revision + 1,
            itemsById: [:]
        )
        _ = try await source.publish(
            availability: packageBox.availability,
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
        let packageBox = ReviewPackageBox(makeReviewPackage(itemCount: 128))
        let source = BridgePaneProductReviewMetadataSource(initialAvailability: packageBox.availability)
        let collector = ReviewMetadataEventCollector()
        let subscription = try reviewSubscription()

        try await source.open(
            subscription: subscription, productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            await collector.append(event)
            if case .sourceAccepted = event {
                await source.cancel(subscriptionId: subscription.subscriptionId)
            }
        }

        #expect(await collector.events.count == 1)
    }

    @Test("open before package publication stays pending and publishes initial metadata later")
    func openBeforePackagePublicationPublishesInitialMetadataLater() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        // Arrange
        let packageBox = OptionalReviewPackageBox()
        let source = BridgePaneProductReviewMetadataSource(initialAvailability: packageBox.availability)
        let collector = ReviewMetadataEventCollector()
        let subscription = try reviewSubscription()

        // Act
        try await source.open(
            subscription: subscription, productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            await collector.append(event)
        }
        let eventsBeforePublication = await collector.events
        let reviewPackage = makeReviewPackage(itemCount: 4)
        packageBox.package = reviewPackage
        let outcome = try await source.publish(
            availability: .ready(reviewPackage), productAdmission: productAdmission.context)
        let eventsAfterPublication = await collector.events

        // Assert
        #expect(eventsBeforePublication.isEmpty)
        guard case .ready(let receipt) = outcome else {
            Issue.record("Expected ready Review metadata publication receipt")
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
        let packageBox = OptionalReviewPackageBox()
        let source = BridgePaneProductReviewMetadataSource(initialAvailability: packageBox.availability)
        let collector = ReviewMetadataEventCollector()
        let subscription = try reviewSubscription()
        try await source.open(
            subscription: subscription, productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            await collector.append(event)
        }

        // Act
        await source.cancel(subscriptionId: subscription.subscriptionId)
        let initialPackage = makeReviewPackage(itemCount: 4)
        packageBox.package = initialPackage
        let outcome = try await source.publish(
            availability: .ready(initialPackage), productAdmission: productAdmission.context)
        let replacementPackage = replacingReviewSource(
            initialPackage,
            packageId: "review-package-after-cancel",
            queryId: "review-query-after-cancel",
            generation: initialPackage.reviewGeneration.rawValue + 1
        )
        packageBox.package = replacementPackage
        _ = try await source.publish(
            availability: .ready(replacementPackage),
            productAdmission: productAdmission.context
        )

        // Assert
        guard case .ready(let receipt) = outcome else {
            Issue.record("Expected ready Review metadata publication receipt")
            return
        }
        #expect(receipt.retained == 0)
        #expect(receipt.publishedSubscriptions == 0)
        #expect(receipt.emittedEvents == 0)
        #expect(receipt.superseded == 0)
        #expect(await collector.events.isEmpty)
    }

    @Test("a newer pending open supersedes the older sink before package publication")
    func newerPendingOpenSupersedesOlderSink() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        // Arrange
        let packageBox = OptionalReviewPackageBox()
        let source = BridgePaneProductReviewMetadataSource(initialAvailability: packageBox.availability)
        let supersededCollector = ReviewMetadataEventCollector()
        let currentCollector = ReviewMetadataEventCollector()
        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            await supersededCollector.append(event)
        }
        try await source.open(
            subscription: try reviewSubscription(interestRevision: 1), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            await currentCollector.append(event)
        }

        // Act
        let reviewPackage = makeReviewPackage(itemCount: 4)
        packageBox.package = reviewPackage
        _ = try await source.publish(
            availability: .ready(reviewPackage),
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
        let packageBox = OptionalReviewPackageBox()
        let source = BridgePaneProductReviewMetadataSource(initialAvailability: packageBox.availability)
        let sink = ReviewMetadataSecondFrameFailureSink()
        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            try await sink.receive(event)
        }
        let reviewPackage = makeReviewPackage(itemCount: 4)
        packageBox.package = reviewPackage

        // Act
        do {
            _ = try await source.publish(
                availability: .ready(reviewPackage),
                productAdmission: productAdmission.context
            )
            Issue.record("Expected the injected second-frame sink failure")
        } catch {
            #expect(error as? ReviewMetadataInjectedSinkError == .secondFrame)
        }
        let successfulEventCountAfterFailure = await sink.successfulEvents.count
        _ = try await source.publish(
            availability: .ready(reviewPackage),
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

    @Test("loading update preserves published identity for replacement reset")
    func loadingUpdatePreservesPublishedIdentityForReplacementReset() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        // Arrange
        let initialPackage = makeReviewPackage(itemCount: 4)
        let packageBox = OptionalReviewPackageBox(initialPackage)
        let source = BridgePaneProductReviewMetadataSource(initialAvailability: packageBox.availability)
        let collector = ReviewMetadataEventCollector()
        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            await collector.append(event)
        }
        await collector.removeAll()

        // Act
        packageBox.package = nil
        _ = try await source.publish(
            availability: .loading,
            productAdmission: productAdmission.context
        )
        try await source.update(
            subscription: try reviewSubscription(interestRevision: 1), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            await collector.append(event)
        }
        let replacementPackage = replacingReviewSource(
            initialPackage,
            packageId: "review-package-after-loading",
            queryId: "review-query-after-loading",
            generation: initialPackage.reviewGeneration.rawValue + 1
        )
        packageBox.package = replacementPackage
        _ = try await source.publish(
            availability: .ready(replacementPackage),
            productAdmission: productAdmission.context
        )
        let events = await collector.events

        // Assert
        guard case .reset(let reset) = events.first,
            case .sourceAccepted(let accepted) = events.dropFirst().first,
            case .snapshot = events.dropFirst(2).first
        else {
            Issue.record("Expected replacement reset after a package-less loading update")
            return
        }
        #expect(reset.identity == reviewIdentity(for: replacementPackage))
        #expect(accepted.identity == reviewIdentity(for: replacementPackage))
    }

    @Test("actor-owned availability cannot lose ready publication racing open")
    func actorOwnedAvailabilityCannotLoseReadyPublicationRacingOpen() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        // Arrange
        let source = BridgePaneProductReviewMetadataSource(initialAvailability: .loading)
        let collector = ReviewMetadataEventCollector()
        let subscription = try reviewSubscription()
        let reviewPackage = makeReviewPackage(itemCount: 4)

        // Act
        async let open: Void = source.open(
            subscription: subscription, productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            await collector.append(event)
        }
        _ = try await source.publish(
            availability: .ready(reviewPackage),
            productAdmission: productAdmission.context
        )
        try await open
        let events = await collector.events

        // Assert
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
        let source = BridgePaneProductReviewMetadataSource(initialAvailability: .ready(initialPackage))
        let sink = ReviewMetadataOverlappingPublicationSink()
        try await source.open(
            subscription: try reviewSubscription(), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            await sink.receive(event)
        }
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
            _ = try await source.publish(
                availability: .ready(publicationA),
                productAdmission: productAdmission.context
            )
        }
        await sink.waitUntilSuspended()
        _ = try await source.publish(
            availability: .ready(publicationB),
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
        _ = try await source.publish(
            availability: .ready(publicationB),
            productAdmission: productAdmission.context
        )
        let eventCountAfterRepublishingB = await sink.events.count

        // Assert
        #expect(!stalePublicationAAfterB)
        #expect(eventCountAfterRepublishingB == eventCountBeforeRepublishingB)
    }

    @Test("closing admission while the metadata sink is suspended prevents its commit")
    func closeDuringMetadataSinkPreventsCommit() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let source = BridgePaneProductReviewMetadataSource(initialAvailability: .loading)
        let sink = ReviewMetadataAdmissionFencedSink()
        let subscription = try reviewSubscription()
        try await source.open(
            subscription: subscription,
            productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            await sink.receive(event, productAdmission: emittedProductAdmission)
        }
        let reviewPackage = makeReviewPackage(itemCount: 4)

        // Act
        let publication = Task {
            try await source.publish(
                availability: .ready(reviewPackage),
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
        guard case .ready(let receipt) = outcome else {
            Issue.record("Expected a superseded ready publication receipt")
            return
        }
        #expect(receipt.publishedSubscriptions == 0)
        #expect(receipt.emittedEvents == 0)
        #expect(receipt.superseded == 1)
    }
}

@MainActor
private final class ReviewPackageBox {
    var package: BridgeReviewPackage

    var availability: BridgePaneProductReviewMetadataAvailability { .ready(package) }

    init(_ package: BridgeReviewPackage) {
        self.package = package
    }
}

@MainActor
private final class OptionalReviewPackageBox {
    var package: BridgeReviewPackage?

    var availability: BridgePaneProductReviewMetadataAvailability {
        package.map(BridgePaneProductReviewMetadataAvailability.ready) ?? .loading
    }

    init(_ package: BridgeReviewPackage? = nil) {
        self.package = package
    }
}

private enum ReviewMetadataInjectedSinkError: Error, Equatable {
    case secondFrame
}

private actor ReviewMetadataSecondFrameFailureSink {
    private var receivedEventCount = 0
    private(set) var successfulEvents: [BridgeProductReviewMetadataEvent] = []

    func receive(_ event: BridgeProductReviewMetadataEvent) throws {
        receivedEventCount += 1
        if receivedEventCount == 2 {
            throw ReviewMetadataInjectedSinkError.secondFrame
        }
        successfulEvents.append(event)
    }
}

private actor ReviewMetadataOverlappingPublicationSink {
    private(set) var events: [BridgeProductReviewMetadataEvent] = []
    private var suspendedPackageId: String?
    private var suspensionStarted = false
    private var suspensionStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspensionRelease: CheckedContinuation<Void, Never>?

    func receive(_ event: BridgeProductReviewMetadataEvent) async {
        events.append(event)
        guard event.packageId == suspendedPackageId, !suspensionStarted else { return }
        suspensionStarted = true
        let waiters = suspensionStartedWaiters
        suspensionStartedWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            suspensionRelease = continuation
        }
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
    private var suspensionStarted = false
    private var suspensionStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspensionRelease: CheckedContinuation<Void, Never>?

    func receive(
        _ event: BridgeProductReviewMetadataEvent,
        productAdmission: BridgeProductAdmissionContext
    ) async {
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
