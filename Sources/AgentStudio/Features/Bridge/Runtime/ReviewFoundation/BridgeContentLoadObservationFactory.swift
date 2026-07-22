import Foundation

enum BridgeContentLoadObservationFactory {
    static func make(
        cacheResult: BridgeContentLoadObservation.CacheResult,
        handle: BridgeContentHandle?,
        requestedGeneration: BridgeReviewGeneration,
        data: Data?,
        error: (any Error)?
    ) -> BridgeContentLoadObservation {
        let byteSize = byteSize(for: data, handle: handle, error: error)
        return BridgeContentLoadObservation(
            cacheResult: cacheResult,
            role: handle?.role,
            generationRelation: generationRelation(
                handle: handle,
                requestedGeneration: requestedGeneration,
                error: error
            ),
            byteSizeBucket: byteSizeBucket(for: byteSize),
            lineCountBucket: lineCountBucket(for: data),
            isBinary: isBinary(handle: handle, error: error),
            isStale: isStale(error)
        )
    }

    private static func generationRelation(
        handle: BridgeContentHandle?,
        requestedGeneration: BridgeReviewGeneration,
        error: (any Error)?
    ) -> BridgeContentLoadObservation.GenerationRelation {
        if isStale(error) {
            return .stale
        }
        guard let handle else {
            return .unknown
        }
        return handle.reviewGeneration == requestedGeneration ? .current : .stale
    }

    private static func byteSize(for data: Data?, handle: BridgeContentHandle?, error: (any Error)?) -> Int {
        if let data {
            return data.count
        }
        if case .oversizedContent(_, let sizeBytes)? = error as? BridgeProviderFailure {
            return sizeBytes
        }
        return handle?.sizeBytes ?? 0
    }

    private static func isBinary(handle: BridgeContentHandle?, error: (any Error)?) -> Bool {
        if case .binaryContent? = error as? BridgeProviderFailure {
            return true
        }
        return handle?.isBinary ?? false
    }

    private static func isStale(_ error: (any Error)?) -> Bool {
        if case .staleReviewGeneration? = error as? BridgeProviderFailure {
            return true
        }
        return false
    }

    private static func byteSizeBucket(for byteSize: Int) -> Int {
        guard byteSize > 0 else {
            return 0
        }
        var bucket = 1024
        while bucket < byteSize, bucket < 64 * 1024 * 1024 {
            bucket *= 2
        }
        return bucket
    }

    private static func lineCountBucket(for data: Data?) -> Int {
        guard let data, !data.isEmpty else {
            return 0
        }
        let lineCount = data.reduce(1) { partialResult, byte in
            byte == 10 ? partialResult + 1 : partialResult
        }
        var bucket = 1
        while bucket < lineCount, bucket < 1_000_000 {
            bucket *= 2
        }
        return bucket
    }
}
