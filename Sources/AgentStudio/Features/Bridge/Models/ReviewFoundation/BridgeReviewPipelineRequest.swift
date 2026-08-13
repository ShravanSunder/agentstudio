import Foundation

struct BridgeReviewPipelineRequest: Codable, Equatable, Sendable {
    let packageId: String
    let query: BridgeReviewQuery
    let baseEndpoint: BridgeSourceEndpoint
    let headEndpoint: BridgeSourceEndpoint
    let checkpointIds: [String]
    let reviewGeneration: BridgeReviewGeneration
    let generatedAtUnixMilliseconds: Int64
    let preparedComparison: BridgeEndpointComparison?
    let comparisonOrigin: BridgeReviewComparisonOrigin?
    let reviewedSubjectLabel: String?

    init(
        packageId: String,
        query: BridgeReviewQuery,
        baseEndpoint: BridgeSourceEndpoint,
        headEndpoint: BridgeSourceEndpoint,
        checkpointIds: [String],
        reviewGeneration: BridgeReviewGeneration,
        generatedAtUnixMilliseconds: Int64,
        preparedComparison: BridgeEndpointComparison? = nil,
        comparisonOrigin: BridgeReviewComparisonOrigin? = nil,
        reviewedSubjectLabel: String? = nil
    ) {
        self.packageId = packageId
        self.query = query
        self.baseEndpoint = baseEndpoint
        self.headEndpoint = headEndpoint
        self.checkpointIds = checkpointIds
        self.reviewGeneration = reviewGeneration
        self.generatedAtUnixMilliseconds = generatedAtUnixMilliseconds
        self.preparedComparison = preparedComparison
        self.comparisonOrigin = comparisonOrigin
        self.reviewedSubjectLabel = reviewedSubjectLabel
    }
}
