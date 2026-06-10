import Foundation

enum BridgeProviderFailure: Error, Equatable, Sendable {
    case unavailableEndpoint(endpointId: String)
    case staleReviewGeneration(expected: BridgeReviewGeneration, actual: BridgeReviewGeneration)
    case missingContent(handleId: String)
    case oversizedContent(handleId: String, sizeBytes: Int)
    case binaryContent(handleId: String)
    case providerUnavailable
    case providerFailed(message: String)
}
