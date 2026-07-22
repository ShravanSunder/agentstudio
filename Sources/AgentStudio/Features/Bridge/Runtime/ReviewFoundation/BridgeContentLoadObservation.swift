import Foundation

struct BridgeContentLoadObservation: Equatable, Sendable {
    enum CacheResult: String, Equatable, Sendable {
        case cacheHit = "cache_hit"
        case providerLoad = "provider_load"
        case inFlightCoalesced = "in_flight_coalesced"
        case rejected
    }

    enum GenerationRelation: String, Equatable, Sendable {
        case current
        case stale
        case unknown
    }

    let cacheResult: CacheResult
    let role: BridgeContentHandle.Role?
    let generationRelation: GenerationRelation
    let byteSizeBucket: Int
    let lineCountBucket: Int
    let isBinary: Bool
    let isStale: Bool
}

struct BridgeContentLoadObservedResult: Equatable, Sendable {
    let result: BridgeContentLoadResult
    let observation: BridgeContentLoadObservation
}

struct BridgeContentStreamObservedResult: Equatable, Sendable {
    let result: BridgeContentStreamResult
    let observation: BridgeContentLoadObservation
}

struct BridgeContentLoadObservedFailure: Error, @unchecked Sendable {
    let underlyingError: any Error
    let observation: BridgeContentLoadObservation
}
