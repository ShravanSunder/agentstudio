@testable import AgentStudio

@MainActor
final class AvailabilityReviewPublicationProvider {
    var publication: BridgeReviewCommittedPublication?
}

func availabilityReviewMetadataEvents(
    in frames: [BridgeProductMetadataFrame]
) -> [BridgeProductReviewMetadataEvent] {
    frames.compactMap { frame -> BridgeProductReviewMetadataEvent? in
        guard case .subscriptionData(let data) = frame,
            case .reviewMetadata(let event) = data.data
        else { return nil }
        return event
    }
}
