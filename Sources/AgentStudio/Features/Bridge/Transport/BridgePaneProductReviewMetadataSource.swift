import AgentStudioInfrastructure
import Foundation

enum BridgePaneProductReviewMetadataSourceError: Error, Equatable {
    case integerOutOfRange
    case metadataEventExceedsByteLimit
    case unavailablePackage
    case unknownSubscription
}

struct BridgeReviewMetadataPublicationReservation: Equatable, Sendable {
    let reservationId: UUID
    let packageId: String
    let publicationId: UUID
    let reviewGeneration: BridgeReviewGeneration
    let revision: Int
    let projectionPlan: BridgeReviewMetadataPublicationProjectionPlan
}

struct BridgeReviewMetadataFinalFrame: Equatable, Sendable {
    let sequence: Int
    let subscriptionId: String
}

struct BridgeReviewMetadataPublicationReceipt: Equatable, Sendable {
    let retained: Int
    let publishedSubscriptions: Int
    let emittedEvents: Int
    let superseded: Int
    let finalFrames: [BridgeReviewMetadataFinalFrame]
}

enum BridgePaneProductReviewMetadataPublicationOutcome: Equatable, Sendable {
    case delivered(BridgeReviewMetadataPublicationReceipt)
    case deferred(retained: Int)
}

typealias BridgePaneProductReviewMetadataEventSink =
    @Sendable (
        BridgeProductSealedMetadataApplicationEvent<BridgeProductReviewMetadataEvent>,
        BridgeProductAdmissionContext
    ) async throws ->
    BridgeProductProducerEnqueueResult

protocol BridgePaneProductReviewMetadataProducing: Sendable {
    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws
    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws
    func reserve(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgeReviewMetadataPublicationReservation
    func deliver(
        publication: BridgeReviewCommittedPublication,
        reservation: BridgeReviewMetadataPublicationReservation,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome
    func cancel(subscriptionId: String) async
}

actor BridgeUnavailablePaneProductReviewMetadataSource: BridgePaneProductReviewMetadataProducing {
    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        throw BridgePaneProductReviewMetadataSourceError.unavailablePackage
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        throw BridgePaneProductReviewMetadataSourceError.unavailablePackage
    }

    func reserve(
        package _: BridgeReviewPackage,
        publicationId _: UUID,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> BridgeReviewMetadataPublicationReservation {
        throw BridgePaneProductReviewMetadataSourceError.unavailablePackage
    }

    func deliver(
        publication _: BridgeReviewCommittedPublication,
        reservation _: BridgeReviewMetadataPublicationReservation,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        .deferred(retained: 0)
    }

    func cancel(subscriptionId _: String) {}
}

actor BridgePaneProductReviewMetadataSource: BridgePaneProductReviewMetadataProducing {
    fileprivate struct DeliveredPublication: Sendable {
        let comparisonPresentationRevision: Int
        let package: BridgeReviewPackage
        let publicationId: UUID
        let classifiedRefreshImpact: BridgeReviewRefreshImpact?
        let reviewComparison: BridgePaneReviewComparisonPresentation?
        let operationCorrelationID: String?
    }

    private enum EmissionOutcome {
        case published(eventCount: Int, finalFrameSequence: Int?)
        case superseded
    }

    private struct SubscriptionContext: Sendable {
        let contextId: UUID
        var deliveredPublication: DeliveredPublication?
        var subscription: BridgeProductSubscriptionSnapshot
        var emit: BridgePaneProductReviewMetadataEventSink
    }

    private var deliveryRevision = 0
    private var contextBySubscriptionId: [String: SubscriptionContext] = [:]

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        guard subscription.subscriptionKind == .reviewMetadata,
            subscription.interestState.reviewMetadataState != nil
        else {
            throw BridgePaneProductReviewMetadataSourceError.unavailablePackage
        }
        _ = productAdmission.withValidAdmission {
            contextBySubscriptionId[subscription.subscriptionId] = SubscriptionContext(
                contextId: UUID(),
                deliveredPublication: nil,
                subscription: subscription,
                emit: emit
            )
        }
    }

    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        guard let activeContext = contextBySubscriptionId[subscription.subscriptionId] else {
            throw BridgePaneProductReviewMetadataSourceError.unknownSubscription
        }
        guard subscription.subscriptionKind == .reviewMetadata,
            subscription.interestState.reviewMetadataState != nil,
            subscription.interestRevision >= activeContext.subscription.interestRevision
        else {
            throw BridgePaneProductReviewMetadataSourceError.unavailablePackage
        }
        _ = productAdmission.withValidAdmission {
            contextBySubscriptionId[subscription.subscriptionId] = SubscriptionContext(
                contextId: UUID(),
                deliveredPublication: activeContext.deliveredPublication,
                subscription: subscription,
                emit: emit
            )
        }
    }

    func reserve(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgeReviewMetadataPublicationReservation {
        let projectionPlan = try BridgeReviewMetadataPublicationProjectionPlan.prepare(
            package: package,
            publicationId: publicationId
        )
        guard (productAdmission.withValidAdmission { true }) == true else {
            throw CancellationError()
        }
        return BridgeReviewMetadataPublicationReservation(
            reservationId: UUIDv7.generate(),
            packageId: package.packageId,
            publicationId: publicationId,
            reviewGeneration: package.reviewGeneration,
            revision: package.revision,
            projectionPlan: projectionPlan
        )
    }

    func deliver(
        publication: BridgeReviewCommittedPublication,
        reservation: BridgeReviewMetadataPublicationReservation,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        let package = publication.package
        guard reservation.packageId == package.packageId,
            reservation.reviewGeneration == package.reviewGeneration,
            reservation.revision == package.revision,
            reservation.projectionPlan.packageId == package.packageId,
            reservation.projectionPlan.publicationId == reservation.publicationId,
            reservation.projectionPlan.reviewGeneration == package.reviewGeneration,
            reservation.projectionPlan.revision == package.revision,
            (productAdmission.withValidAdmission { true }) == true
        else { throw BridgePaneProductReviewMetadataSourceError.unavailablePackage }
        let subscriptionIds = contextBySubscriptionId.keys.sorted()
        guard !subscriptionIds.isEmpty else { return .deferred(retained: 0) }
        guard
            let publishingDeliveryRevision = productAdmission.withValidAdmission({
                deliveryRevision += 1
                return deliveryRevision
            })
        else { return .deferred(retained: 0) }
        var emittedEventCount = 0
        var publishedSubscriptionCount = 0
        var supersededSubscriptionCount = 0
        var finalFrames: [BridgeReviewMetadataFinalFrame] = []
        for subscriptionId in subscriptionIds {
            try Task.checkCancellation()
            guard let context = contextBySubscriptionId[subscriptionId] else { continue }
            switch try await emitAndCommitIfCurrent(
                DeliveredPublication(
                    comparisonPresentationRevision: publication.comparisonPresentationRevision,
                    package: package,
                    publicationId: reservation.publicationId,
                    classifiedRefreshImpact: publication.classifiedRefreshImpact,
                    reviewComparison: publication.reviewComparison,
                    operationCorrelationID: publication.operationCorrelationID
                ),
                projectionPlan: reservation.projectionPlan,
                context: context,
                deliveryRevision: publishingDeliveryRevision,
                productAdmission: productAdmission
            ) {
            case .published(let eventCount, let finalFrameSequence):
                emittedEventCount += eventCount
                publishedSubscriptionCount += 1
                if let finalFrameSequence {
                    finalFrames.append(
                        BridgeReviewMetadataFinalFrame(
                            sequence: finalFrameSequence,
                            subscriptionId: subscriptionId
                        )
                    )
                }
            case .superseded:
                supersededSubscriptionCount += 1
            }
        }
        return .delivered(
            BridgeReviewMetadataPublicationReceipt(
                retained: subscriptionIds.count,
                publishedSubscriptions: publishedSubscriptionCount,
                emittedEvents: emittedEventCount,
                superseded: supersededSubscriptionCount,
                finalFrames: finalFrames
            ))
    }

    func cancel(subscriptionId: String) {
        contextBySubscriptionId.removeValue(forKey: subscriptionId)
    }

    private func emitAndCommitIfCurrent(
        _ publication: DeliveredPublication,
        projectionPlan: BridgeReviewMetadataPublicationProjectionPlan,
        context: SubscriptionContext,
        deliveryRevision publishingDeliveryRevision: Int,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> EmissionOutcome {
        let events = try Self.events(
            from: context.deliveredPublication,
            to: publication,
            projectionPlan: projectionPlan
        )
        var finalFrameSequence: Int?
        for sealedEvent in events {
            try Task.checkCancellation()
            guard
                (productAdmission.withValidAdmission {
                    guard
                        let currentContext = contextBySubscriptionId[context.subscription.subscriptionId],
                        currentContext.contextId == context.contextId,
                        deliveryRevision == publishingDeliveryRevision
                    else { return false }
                    return true
                }) == true
            else { return .superseded }
            let enqueueResult = try await context.emit(sealedEvent, productAdmission)
            guard case .enqueued(let frame) = enqueueResult else {
                throw BridgePaneProductReviewMetadataSourceError.unavailablePackage
            }
            finalFrameSequence = frame.sequence
        }
        return productAdmission.withValidAdmission {
            guard var currentContext = contextBySubscriptionId[context.subscription.subscriptionId],
                currentContext.contextId == context.contextId,
                deliveryRevision == publishingDeliveryRevision
            else { return .superseded }
            currentContext.deliveredPublication = publication
            contextBySubscriptionId[context.subscription.subscriptionId] = currentContext
            return .published(
                eventCount: events.count,
                finalFrameSequence: finalFrameSequence
            )
        } ?? .superseded
    }

    private static func sourceAcceptedEvent(
        for publication: DeliveredPublication
    ) throws -> BridgeProductReviewMetadataEvent {
        .sourceAccepted(
            .init(
                identity: try identity(for: publication)
            )
        )
    }

    private static func events(
        from currentPublication: DeliveredPublication?,
        to nextPublication: DeliveredPublication,
        projectionPlan: BridgeReviewMetadataPublicationProjectionPlan
    ) throws -> [BridgeProductSealedMetadataApplicationEvent<BridgeProductReviewMetadataEvent>] {
        let events: [BridgeProductReviewMetadataEvent]
        guard let currentPublication else {
            events =
                [try sourceAcceptedEvent(for: nextPublication)]
                + (try projectionPlan.events(binding: binding(for: nextPublication)))
            return try sealedEvents(events)
        }
        guard
            currentPublication.publicationId != nextPublication.publicationId
                || currentPublication.package != nextPublication.package
        else { return [] }
        let currentPackage = currentPublication.package
        let nextPackage = nextPublication.package
        if let classifiedRefreshImpact = nextPublication.classifiedRefreshImpact,
            canApplyDelta(from: currentPackage, to: nextPackage),
            let sealedDelta = try sealedDeltaEvent(
                from: currentPublication,
                to: nextPublication,
                refreshImpact: classifiedRefreshImpact
            )
        {
            return [sealedDelta]
        }
        let identity = try identity(for: nextPublication)
        events =
            [
                .reset(
                    .init(
                        identity: identity,
                        comparisonOrigin: nextPackage.comparisonOrigin,
                        refreshImpact: nextPublication.classifiedRefreshImpact,
                        reason: .sourceChanged,
                        reviewedSubjectLabel: nextPackage.reviewedSubjectLabel
                    )
                ),
                try sourceAcceptedEvent(for: nextPublication),
            ] + (try projectionPlan.events(binding: binding(for: nextPublication)))
        return try sealedEvents(events)
    }

    private static func binding(
        for publication: DeliveredPublication
    ) throws -> BridgeReviewMetadataPublicationBinding {
        BridgeReviewMetadataPublicationBinding(
            identity: try identity(for: publication),
            presentationRevision: publication.comparisonPresentationRevision,
            reviewComparison: publication.reviewComparison
        )
    }

    private static func sealedEvents(
        _ events: [BridgeProductReviewMetadataEvent]
    ) throws -> [BridgeProductSealedMetadataApplicationEvent<BridgeProductReviewMetadataEvent>] {
        let sealedEvents = try events.map(sealBridgeReviewMetadataEvent)
        guard
            sealedEvents.allSatisfy({
                $0.encodedApplicationByteCount
                    <= BridgeReviewMetadataPublicationProjectionPlan.maximumEncodedEventBytes
            })
        else {
            throw BridgePaneProductReviewMetadataSourceError.metadataEventExceedsByteLimit
        }
        return sealedEvents
    }

    fileprivate static func identity(
        for publication: DeliveredPublication
    ) throws -> BridgeProductReviewMetadataIdentity {
        let package = publication.package
        return try BridgeProductReviewMetadataIdentity(
            generation: package.reviewGeneration.rawValue,
            packageId: package.packageId,
            publicationId: publication.publicationId,
            revision: package.revision,
            sourceIdentity: package.query.queryId,
            operationCorrelationID: publication.operationCorrelationID
        )
    }

    private static func sealedDeltaEvent(
        from currentPublication: DeliveredPublication,
        to nextPublication: DeliveredPublication,
        refreshImpact: BridgeReviewRefreshImpact
    ) throws -> BridgeProductSealedMetadataApplicationEvent<BridgeProductReviewMetadataEvent>? {
        let currentPackage = currentPublication.package
        let nextPackage = nextPublication.package
        guard nextPackage.revision > currentPackage.revision else { return nil }
        let currentItems = currentPackage.itemsById
        let nextItems = nextPackage.itemsById
        let currentOrder = orderedItemIds(in: currentPackage)
        let nextOrder = orderedItemIds(in: nextPackage)
        let currentIds = Set(currentItems.keys)
        let nextIds = Set(nextItems.keys)
        let addedIds = nextOrder.filter { !currentIds.contains($0) }
        let removedIds = currentOrder.filter { !nextIds.contains($0) }
        let updatedIds = nextOrder.filter { itemId in
            guard let currentItem = currentItems[itemId], let nextItem = nextItems[itemId] else { return false }
            return currentItem != nextItem
        }
        let changedIds = addedIds + updatedIds
        let changedItems = changedIds.compactMap { nextItems[$0] }
        var operations: [BridgeProductReviewMetadataOperation] = try changedItems.map {
            .upsertItem(try productItem($0, loadedBy: .delta, lane: .active))
        }
        if !removedIds.isEmpty { operations.append(.removeItems(removedIds)) }
        if currentOrder != nextOrder { operations.append(.replaceItemOrder(nextOrder)) }

        let currentTreeRows = try productTreeRows(for: currentOrder.compactMap { currentItems[$0] }, loadedBy: .delta)
        let nextTreeRows = try productTreeRows(for: nextOrder.compactMap { nextItems[$0] }, loadedBy: .delta)
        if let treeSplice = treeSplice(from: currentTreeRows, to: nextTreeRows) {
            operations.append(treeSplice)
        }
        let extentFacts = changedItems.flatMap(authoritativeProductExtentFacts)
        if !extentFacts.isEmpty { operations.append(.upsertExtentFacts(extentFacts)) }

        let previousDescriptorIds = (removedIds + updatedIds).flatMap { itemId in
            currentItems[itemId]?.contentRoles.allHandles.map(\.handleId) ?? []
        }
        let replacementDescriptorIds = updatedIds.flatMap { itemId in
            nextItems[itemId]?.contentRoles.allHandles.map(\.handleId) ?? []
        }
        let invalidatedDescriptorIds = Set(previousDescriptorIds + replacementDescriptorIds).sorted()
        if !invalidatedDescriptorIds.isEmpty {
            operations.append(.invalidateContentSources(invalidatedDescriptorIds))
        }
        let contentSources = try changedItems.flatMap { try productContentSources(for: $0, package: nextPackage) }
        guard isContractBoundedDelta(operations: operations, contentSources: contentSources) else { return nil }
        let event = try BridgeProductReviewDeltaEvent(
            identity: identity(for: nextPublication),
            contentSources: contentSources,
            fromRevision: currentPackage.revision,
            operations: operations,
            presentationRevision: nextPublication.comparisonPresentationRevision,
            refreshImpact: refreshImpact,
            reviewComparison: nextPublication.reviewComparison,
            summary: try productSummary(nextPackage.summary),
            toRevision: nextPackage.revision
        )
        let sealedEvent = try sealBridgeReviewMetadataEvent(.delta(event))
        guard
            sealedEvent.encodedApplicationByteCount
                <= BridgeReviewMetadataPublicationProjectionPlan.maximumEncodedEventBytes
        else { return nil }
        return sealedEvent
    }

    private static func isContractBoundedDelta(
        operations: [BridgeProductReviewMetadataOperation],
        contentSources: [BridgeProductReviewContentSourceDescriptor]
    ) -> Bool {
        let maximumCount = BridgeProductReviewMetadataLimits.maximumWindowEntryCount
        guard operations.count <= maximumCount, contentSources.count <= maximumCount else { return false }
        return operations.allSatisfy { operation in
            switch operation {
            case .upsertItem:
                true
            case .removeItems(let itemIds), .replaceItemOrder(let itemIds):
                itemIds.count <= maximumCount
            case .spliceTreeRows(_, let deleteCount, let rows):
                deleteCount <= maximumCount && rows.count <= maximumCount
            case .upsertExtentFacts(let facts):
                facts.count <= maximumCount
            case .invalidateContentSources(let descriptorIds):
                descriptorIds.count <= maximumCount
            }
        }
    }

    private static func canApplyDelta(
        from currentPackage: BridgeReviewPackage,
        to nextPackage: BridgeReviewPackage
    ) -> Bool {
        nextPackage.revision > currentPackage.revision
            && currentPackage.query == nextPackage.query
            && currentPackage.baseEndpoint == nextPackage.baseEndpoint
            && currentPackage.headEndpoint == nextPackage.headEndpoint
            && currentPackage.comparisonOrigin == nextPackage.comparisonOrigin
            && currentPackage.reviewedSubjectLabel == nextPackage.reviewedSubjectLabel
    }

    static func orderedItemIds(in package: BridgeReviewPackage) -> [String] {
        var seen = Set<String>()
        var itemIds = package.orderedItemIds.filter { package.itemsById[$0] != nil && seen.insert($0).inserted }
        itemIds.append(contentsOf: package.itemsById.keys.sorted().filter { seen.insert($0).inserted })
        return itemIds
    }

    private static func treeSplice(
        from currentRows: [BridgeProductReviewTreeRowValue],
        to nextRows: [BridgeProductReviewTreeRowValue]
    ) -> BridgeProductReviewMetadataOperation? {
        guard currentRows != nextRows else { return nil }
        var prefixCount = 0
        while prefixCount < min(currentRows.count, nextRows.count),
            currentRows[prefixCount] == nextRows[prefixCount]
        {
            prefixCount += 1
        }
        var suffixCount = 0
        while suffixCount < currentRows.count - prefixCount,
            suffixCount < nextRows.count - prefixCount,
            currentRows[currentRows.count - suffixCount - 1] == nextRows[nextRows.count - suffixCount - 1]
        {
            suffixCount += 1
        }
        return .spliceTreeRows(
            startIndex: prefixCount,
            deleteCount: currentRows.count - prefixCount - suffixCount,
            rows: Array(nextRows[prefixCount..<(nextRows.count - suffixCount)])
        )
    }

}
