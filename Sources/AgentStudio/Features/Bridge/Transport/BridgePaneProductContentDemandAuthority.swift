import Foundation

actor BridgePaneProductContentDemandAuthority {
    private let fileMetadataSource: any BridgePaneProductFileMetadataProducing
    private let reviewContentSource: any BridgePaneProductReviewContentProducing
    private var committedSubscriptionById: [String: BridgeProductSubscriptionSnapshot] = [:]

    init(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewContentSource: any BridgePaneProductReviewContentProducing
    ) {
        self.fileMetadataSource = fileMetadataSource
        self.reviewContentSource = reviewContentSource
    }

    func apply(
        _ effect: BridgeProductSessionCompletionEffect,
        productAdmission: BridgeProductAdmissionContext
    ) {
        switch effect {
        case .subscriptionOpened(let subscription),
            .subscriptionInterestsCommitted(_, let subscription):
            _ = productAdmission.withValidAdmission {
                committedSubscriptionById[subscription.subscriptionId] = subscription
            }
        case .subscriptionCancelled(let subscription):
            committedSubscriptionById.removeValue(forKey: subscription.subscriptionId)
        case .resynced(let result):
            for outcome in result.reconciliation {
                switch outcome {
                case .retained:
                    break
                case .cancelled, .reopenRequired, .reset:
                    committedSubscriptionById.removeValue(forKey: outcome.subscriptionId)
                }
            }
            for subscriptionId in result.revokedNativeOnlySubscriptionIds {
                committedSubscriptionById.removeValue(forKey: subscriptionId)
            }
            for resetIntent in result.resetIntents {
                committedSubscriptionById.removeValue(forKey: resetIntent.subscriptionId)
            }
        case .noEffect, .productCall:
            break
        }
    }

    func removeAll() {
        committedSubscriptionById.removeAll(keepingCapacity: false)
    }

    func interest(
        for request: BridgeProductContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgeContentDemandInterest {
        let highestLane: BridgeProductDemandLane?
        switch request {
        case .fileContent(let fileRequest):
            guard
                let path = await fileMetadataSource.authoritativePath(
                    for: fileRequest,
                    productAdmission: productAdmission
                )
            else {
                return .unspecified
            }
            guard
                let admittedHighestLane = productAdmission.withValidAdmission({
                    highestFileDemandLane(for: path)
                })
            else { return .unspecified }
            highestLane = admittedHighestLane
        case .reviewContent(let reviewRequest):
            guard
                let itemId = await reviewContentSource.authoritativeItemId(
                    for: reviewRequest,
                    productAdmission: productAdmission
                )
            else {
                return .unspecified
            }
            guard
                let admittedHighestLane = productAdmission.withValidAdmission({
                    highestReviewDemandLane(for: itemId)
                })
            else { return .unspecified }
            highestLane = admittedHighestLane
        }
        return highestLane.map(Self.contentDemandInterest(for:)) ?? .unspecified
    }

    private func highestFileDemandLane(for path: String) -> BridgeProductDemandLane? {
        var highestLane: BridgeProductDemandLane?
        for subscription in committedSubscriptionById.values {
            guard case .fileMetadata(let interests, _) = subscription.interestState else {
                continue
            }
            for interest in interests where interest.paths.contains(path) {
                highestLane = Self.higherPriorityLane(highestLane, interest.lane)
            }
        }
        return highestLane
    }

    private func highestReviewDemandLane(for itemId: String) -> BridgeProductDemandLane? {
        var highestLane: BridgeProductDemandLane?
        for subscription in committedSubscriptionById.values {
            guard case .reviewMetadata(let interests) = subscription.interestState else {
                continue
            }
            for interest in interests where interest.itemIds.contains(itemId) {
                highestLane = Self.higherPriorityLane(highestLane, interest.lane)
            }
        }
        return highestLane
    }

    private static func higherPriorityLane(
        _ current: BridgeProductDemandLane?,
        _ candidate: BridgeProductDemandLane
    ) -> BridgeProductDemandLane {
        guard let current else { return candidate }
        return contentDemandPriority(candidate) < contentDemandPriority(current)
            ? candidate
            : current
    }

    private static func contentDemandInterest(
        for lane: BridgeProductDemandLane
    ) -> BridgeContentDemandInterest {
        switch lane {
        case .foreground, .active: .selected
        case .visible: .visible
        case .nearby: .nearby
        case .speculative: .speculative
        case .idle: .background
        }
    }

    private static func contentDemandPriority(_ lane: BridgeProductDemandLane) -> Int {
        switch lane {
        case .foreground, .active: 0
        case .visible: 1
        case .nearby: 2
        case .speculative: 3
        case .idle: 4
        }
    }
}
