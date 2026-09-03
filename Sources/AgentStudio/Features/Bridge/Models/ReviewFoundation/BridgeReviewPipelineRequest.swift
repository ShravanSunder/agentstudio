import AgentStudioGit
import Foundation

struct BridgeReviewPipelineRequest: Sendable {
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
    let reviewAttemptAuthorityGeneration: UInt64
    let gitRefreshScope: ReviewGitRefreshScope
    let gitRefreshSeed: GitReviewRefreshSeed?

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
        reviewedSubjectLabel: String? = nil,
        reviewAttemptAuthorityGeneration: UInt64 = 0,
        gitRefreshScope: ReviewGitRefreshScope = .complete(reason: .nonExactInput),
        gitRefreshSeed: GitReviewRefreshSeed? = nil
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
        self.reviewAttemptAuthorityGeneration = reviewAttemptAuthorityGeneration
        self.gitRefreshScope = gitRefreshScope
        self.gitRefreshSeed = gitRefreshSeed
    }
}
