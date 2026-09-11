@testable import AgentStudioBridge

@MainActor
final class AvailabilityReviewPublicationProvider {
    var publication: BridgeReviewCommittedPublication?
}

func availabilityReviewMetadataEvents(
    in frames: [BridgeProductMetadataFrame]
) -> [BridgeProductReviewMetadataEvent] {
    frames.compactMap { frame -> BridgeProductReviewMetadataEvent? in
        guard case .subscriptionData(let data) = frame,
            let event = data.data.reviewMetadataEvent
        else { return nil }
        return event
    }
}
