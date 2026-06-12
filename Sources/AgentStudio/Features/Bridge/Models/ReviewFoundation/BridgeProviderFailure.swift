import Foundation

enum BridgeProviderFailure: Error, Equatable, Sendable {
    case unavailableEndpoint(endpointId: String)
    case staleReviewGeneration(
        storedGeneration: BridgeReviewGeneration,
        requestedGeneration: BridgeReviewGeneration
    )
    case missingContent(handleId: String)
    case contentHashMismatch(handleId: String, expectedHash: String, actualHash: String)
    case oversizedContent(handleId: String, sizeBytes: Int)
    case binaryContent(handleId: String)
    case providerUnavailable
    case providerFailed(message: String)
}
