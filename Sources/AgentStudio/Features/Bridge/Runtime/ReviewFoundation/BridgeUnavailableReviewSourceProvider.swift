import Foundation

actor BridgeUnavailableReviewSourceProvider: BridgeReviewSourceProvider {
    func resolveEndpoint(_ request: BridgeEndpointResolutionRequest) async throws -> BridgeSourceEndpoint {
        throw BridgeProviderFailure.providerUnavailable
    }

    func compareEndpoints(_ request: BridgeEndpointComparisonRequest) async throws -> BridgeEndpointComparison {
        throw BridgeProviderFailure.providerUnavailable
    }

    func readTree(_ request: BridgeTreeReadRequest) async throws -> BridgeTreeReadResult {
        throw BridgeProviderFailure.providerUnavailable
    }

    func readReviewItemDescriptor(_ request: BridgeReviewItemDescriptorRequest) async throws
        -> BridgeReviewItemDescriptor
    {
        throw BridgeProviderFailure.providerUnavailable
    }

    func resolveCheckpointEndpoint(_ request: BridgeCheckpointEndpointRequest) async throws -> BridgeSourceEndpoint {
        throw BridgeProviderFailure.providerUnavailable
    }

    func loadContent(_ request: BridgeContentLoadRequest) async throws -> BridgeContentLoadResult {
        throw BridgeProviderFailure.providerUnavailable
    }
}
