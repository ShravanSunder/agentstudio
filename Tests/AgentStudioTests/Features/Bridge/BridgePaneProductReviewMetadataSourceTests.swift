import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Bridge pane product Review metadata source")
struct BridgePaneProductReviewMetadataSourceTests {
    @Test("origin change resets metadata and projects the successor origin and subject")
    func originChangeResetsMetadataAndProjectsSuccessorOriginAndSubject() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let initialOrigin = BridgeReviewComparisonOrigin.contribution(
            BridgeReviewContributionOrigin(
                symbolicTarget: .branch(name: "main"),
                resolvedTargetOID: "target-oid-1",
                reviewedHeadOID: "head-oid-1",
                baseRole: .commonCommit,
                baseOID: "base-oid-1"
            )
        )
        let successorOrigin = BridgeReviewComparisonOrigin.contribution(
            BridgeReviewContributionOrigin(
                symbolicTarget: .branch(name: "main"),
                resolvedTargetOID: "target-oid-2",
                reviewedHeadOID: "head-oid-2",
                baseRole: .commonCommit,
                baseOID: "base-oid-2"
            )
        )
        let initialPackage = makeReviewPackage(
            itemCount: 1,
            comparisonOrigin: initialOrigin,
            reviewedSubjectLabel: "feature/review"
        )
        let successorPackage = replacingReviewOrigin(
            initialPackage,
            revision: initialPackage.revision + 1,
            comparisonOrigin: successorOrigin,
            reviewedSubjectLabel: "feature/review"
        )
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        try await source.open(
            subscription: try reviewSubscription(),
            productAdmission: productAdmission.context
        ) { event, _ in
            try await collector.append(event.event)
        }
        _ = try await deliverReviewPackage(
            initialPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        await collector.removeAll()

        _ = try await deliverReviewPackage(
            successorPackage,
            through: source,
            productAdmission: productAdmission.context
        )

        let events = await collector.events
        guard events.count == 3,
            case .reset(let reset) = events[0],
            case .sourceAccepted = events[1],
            case .snapshot(let snapshot) = events[2]
        else {
            Issue.record("Expected reset, source acceptance, and successor snapshot")
            return
        }
        #expect(reset.comparisonOrigin == successorOrigin)
        #expect(reset.reviewedSubjectLabel == "feature/review")
        #expect(snapshot.comparisonOrigin == successorOrigin)
        #expect(snapshot.reviewedSubjectLabel == "feature/review")
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(BridgeProductReviewSnapshotEvent.self, from: encodedSnapshot) == snapshot)
    }

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
            return try await collector.append(event.event)
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

    @Test("admitted Review publication carries its scrubbed operation correlation on every event")
    func admittedReviewPublicationCarriesOperationCorrelation() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let package = makeReviewPackage(itemCount: 2)
        let operationCorrelationID = String(repeating: "d", count: 64)
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        try await source.open(
            subscription: try reviewSubscription(),
            productAdmission: productAdmission.context
        ) { event, _ in
            try await collector.append(event.event)
        }

        _ = try await deliverReviewPackage(
            package,
            operationCorrelationID: operationCorrelationID,
            through: source,
            productAdmission: productAdmission.context
        )

        let events = await collector.events
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.operationCorrelationID == operationCorrelationID })
    }

    @Test("diff statistics do not publish unverified full-content extent facts")
    func omitsUnverifiedExtentFacts() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let originalPackage = makeReviewPackage(itemCount: 1)
        let itemId = try #require(originalPackage.orderedItemIds.first)
        let originalItem = try #require(originalPackage.itemsById[itemId])
        let package = replacingReviewPackage(
            originalPackage,
            revision: originalPackage.revision,
            itemsById: [
                itemId: reviewItemWithDiffStatistics(
                    originalItem,
                    additions: 2,
                    deletions: 1
                )
            ]
        )
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        try await source.open(
            subscription: try reviewSubscription(),
            productAdmission: productAdmission.context
        ) { event, _ in
            try await collector.append(event.event)
        }

        // Act
        _ = try await deliverReviewPackage(
            package,
            through: source,
            productAdmission: productAdmission.context
        )

        // Assert
        let snapshotEvent = try #require(await collector.events.dropFirst().first)
        guard case .snapshot(let snapshot) = snapshotEvent else {
            Issue.record("Expected initial Review metadata snapshot")
            return
        }
        let itemMetadata = try #require(snapshot.itemMetadata.first)
        #expect(itemMetadata.additions == 2)
        #expect(itemMetadata.deletions == 1)
        #expect(snapshot.extentFacts.isEmpty)
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
            return try await collector.append(event.event)
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
            return try await collector.append(event.event)
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
            classifiedRefreshImpact: .initial,
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
            try await collector.append(event.event)
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
            classifiedRefreshImpact: .initial,
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
            try await collector.append(event.event)
        }
        _ = try await deliverReviewPackage(
            publicationB,
            publicationId: publicationBId,
            classifiedRefreshImpact: .initial,
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
            return try await collector.append(event.event)
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
            return try await collector.append(event.event)
        }
        _ = try await deliverReviewPackage(
            initialPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        await collector.removeAll()

        let generationAdvancedPackage = replacingReviewSource(
            initialPackage,
            packageId: initialPackage.packageId,
            queryId: initialPackage.query.queryId,
            generation: initialPackage.reviewGeneration.rawValue + 1
        )
        let replacementPackage = replacingReviewPackage(
            generationAdvancedPackage,
            revision: generationAdvancedPackage.revision + 1,
            itemsById: [:]
        )
        let impact = BridgeReviewRefreshImpact.exact(
            newlyImportedCommitCount: 10,
            affectedFileCount: 1,
            addedLineCount: 4,
            deletedLineCount: 3,
            affectedStableFileIdentities: ["review-item-00000"]
        )
        _ = try await deliverReviewPackage(
            replacementPackage,
            classifiedRefreshImpact: impact,
            through: source,
            productAdmission: productAdmission.context
        )
        let events = await collector.events

        #expect(events.count == 3)
        guard case .reset(let reset) = events[0],
            case .sourceAccepted = events[1],
            case .snapshot = events[2]
        else {
            Issue.record("Expected reset, sourceAccepted, and empty snapshot for an unsafe delta")
            return
        }
        #expect(reset.refreshImpact == impact)
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
            let enqueueResult = try await collector.append(event.event)
            if case .sourceAccepted = event.event {
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
            return try await collector.append(event.event)
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
            return try await collector.append(event.event)
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
            return try await supersededCollector.append(event.event)
        }
        try await source.open(
            subscription: try reviewSubscription(interestRevision: 1), productAdmission: productAdmission.context
        ) { event, emittedProductAdmission in
            #expect(emittedProductAdmission.matches(productAdmission.context))
            return try await currentCollector.append(event.event)
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
            return try await sink.receive(event.event)
        }
        let reviewPackage = makeReviewPackage(itemCount: 4)
        let reservation = try await source.reserve(
            package: reviewPackage,
            publicationId: reviewMetadataTestPublicationId,
            productAdmission: productAdmission.context
        )
        let publication = reviewMetadataCommittedPublication(reviewPackage)

        // Act
        do {
            _ = try await source.deliver(
                publication: publication,
                reservation: reservation,
                productAdmission: productAdmission.context
            )
            Issue.record("Expected the injected second-frame sink failure")
        } catch {
            #expect(error as? ReviewMetadataInjectedSinkError == .secondFrame)
        }
        let successfulEventCountAfterFailure = await sink.successfulEvents.count
        _ = try await source.deliver(
            publication: publication,
            reservation: reservation,
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
            return try await collector.append(event.event)
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
            return try await collector.append(event.event)
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
            return try await collector.append(event.event)
        }
        let eventsBeforeDelivery = await collector.events
        _ = try await source.deliver(
            publication: reviewMetadataCommittedPublication(reviewPackage),
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
            return try await sink.receive(event.event)
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
            try await collector.append(event.event)
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
            try await sink.receive(event.event, productAdmission: emittedProductAdmission)
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
