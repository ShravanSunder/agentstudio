import CryptoKit
import Foundation

actor BridgeContentStore {
    private struct ContentKey: Hashable {
        let handleId: String
        let reviewGeneration: BridgeReviewGeneration
        let itemId: String
        let role: BridgeContentHandle.Role
        let endpointId: String
        let contentHash: String
    }

    private let provider: (any BridgeReviewSourceProvider)?
    private let contentCacheMaxBytes: Int
    private let contentMaxBytesPerItem: Int
    private var activeReviewGeneration: BridgeReviewGeneration?
    private var handleByKey: [ContentKey: BridgeContentHandle] = [:]
    private var contentByKey: [ContentKey: BridgeContentLoadResult] = [:]
    private var keyByHandleId: [String: ContentKey] = [:]
    private var inFlightLoadByKey: [ContentKey: Task<BridgeContentLoadResult, any Error>] = [:]
    private var cachedByteCountByKey: [ContentKey: Int] = [:]
    private var lastAccessCounterByKey: [ContentKey: Int] = [:]
    private var accessCounter: Int = 0
    private var totalCachedBytes: Int = 0

    init(
        provider: (any BridgeReviewSourceProvider)? = nil,
        contentCacheMaxBytes: Int = AppPolicies.Bridge.contentCacheMaxBytes,
        contentMaxBytesPerItem: Int = AppPolicies.Bridge.contentMaxBytesPerItem
    ) {
        self.provider = provider
        self.contentCacheMaxBytes = contentCacheMaxBytes
        self.contentMaxBytesPerItem = contentMaxBytesPerItem
    }

    func activate(handles: [BridgeContentHandle], reviewGeneration: BridgeReviewGeneration) {
        activeReviewGeneration = reviewGeneration

        var activeKeys: Set<ContentKey> = []
        handleByKey.removeAll(keepingCapacity: true)
        keyByHandleId.removeAll(keepingCapacity: true)
        for handle in handles where handle.reviewGeneration == reviewGeneration {
            let key = contentKey(for: handle)
            activeKeys.insert(key)
            handleByKey[key] = handle
            keyByHandleId[handle.handleId] = key
        }

        for key in contentByKey.keys where !activeKeys.contains(key) {
            removeCachedContent(for: key)
        }
        for (key, task) in inFlightLoadByKey where !activeKeys.contains(key) {
            task.cancel()
            inFlightLoadByKey[key] = nil
        }
    }

    func register(_ handle: BridgeContentHandle) {
        activeReviewGeneration = activeReviewGeneration ?? handle.reviewGeneration
        let key = contentKey(for: handle)
        handleByKey[key] = handle
        keyByHandleId[handle.handleId] = key
    }

    func register(_ result: BridgeContentLoadResult) throws {
        try validateResult(result, for: result.handle)
        register(result.handle)
        let key = contentKey(for: result.handle)
        cache(result, for: key)
    }

    func load(handleId: String, requestedGeneration: BridgeReviewGeneration) async throws -> BridgeContentLoadResult {
        try validateActiveGeneration(requestedGeneration)
        guard let key = keyByHandleId[handleId], let handle = handleByKey[key] else {
            throw BridgeProviderFailure.missingContent(handleId: handleId)
        }
        try validateHandleCanLoad(handle)
        guard key.reviewGeneration == requestedGeneration else {
            throw BridgeProviderFailure.staleReviewGeneration(
                storedGeneration: key.reviewGeneration,
                requestedGeneration: requestedGeneration
            )
        }

        if let result = contentByKey[key] {
            touchCachedContent(for: key)
            return result
        }

        if let task = inFlightLoadByKey[key] {
            do {
                let result = try await task.value
                try validateActiveGeneration(requestedGeneration)
                try validateResult(result, for: handle)
                return result
            } catch {
                try throwStaleGenerationIfInvalidated(error, requestedGeneration: requestedGeneration)
            }
        }

        guard let provider else {
            throw BridgeProviderFailure.providerUnavailable
        }
        let task = Task {
            try await provider.loadContent(
                BridgeContentLoadRequest(handle: handle, requestedGeneration: requestedGeneration)
            )
        }
        inFlightLoadByKey[key] = task
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            inFlightLoadByKey[key] = nil
            try validateActiveGeneration(requestedGeneration)
            try validateResult(result, for: handle)
            cache(result, for: key)
            return result
        } catch {
            inFlightLoadByKey[key] = nil
            try throwStaleGenerationIfInvalidated(error, requestedGeneration: requestedGeneration)
        }
    }

    private func validateActiveGeneration(_ requestedGeneration: BridgeReviewGeneration) throws {
        guard let activeReviewGeneration, activeReviewGeneration != requestedGeneration else { return }
        throw BridgeProviderFailure.staleReviewGeneration(
            storedGeneration: activeReviewGeneration,
            requestedGeneration: requestedGeneration
        )
    }

    private func validateResult(
        _ result: BridgeContentLoadResult,
        for handle: BridgeContentHandle
    ) throws {
        try validateHandleCanLoad(handle)
        guard result.data.count <= contentMaxBytesPerItem else {
            throw BridgeProviderFailure.oversizedContent(
                handleId: handle.handleId,
                sizeBytes: result.data.count
            )
        }
        guard result.contentHashAlgorithm == handle.contentHashAlgorithm else {
            throw BridgeProviderFailure.contentHashMismatch(
                handleId: handle.handleId,
                expectedHash: handle.contentHash,
                actualHash: result.contentHash
            )
        }
        guard result.contentHash == handle.contentHash else {
            throw BridgeProviderFailure.contentHashMismatch(
                handleId: handle.handleId,
                expectedHash: handle.contentHash,
                actualHash: result.contentHash
            )
        }
        let computedHash = try computedContentHash(for: result.data, algorithm: handle.contentHashAlgorithm)
        guard computedHash == handle.contentHash else {
            throw BridgeProviderFailure.contentHashMismatch(
                handleId: handle.handleId,
                expectedHash: handle.contentHash,
                actualHash: computedHash
            )
        }
        guard result.handle.reviewGeneration == handle.reviewGeneration else {
            throw BridgeProviderFailure.staleReviewGeneration(
                storedGeneration: handle.reviewGeneration,
                requestedGeneration: result.handle.reviewGeneration
            )
        }
    }

    private func validateHandleCanLoad(_ handle: BridgeContentHandle) throws {
        if handle.isBinary {
            throw BridgeProviderFailure.binaryContent(handleId: handle.handleId)
        }
    }

    private func computedContentHash(for data: Data, algorithm: String) throws -> String {
        switch algorithm.lowercased() {
        case "sha256", "sha-256":
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            return "sha256:\(hex)"
        default:
            throw BridgeProviderFailure.providerFailed(message: "Unsupported content hash algorithm: \(algorithm)")
        }
    }

    private func throwStaleGenerationIfInvalidated(
        _ error: any Error,
        requestedGeneration: BridgeReviewGeneration
    ) throws -> Never {
        do {
            try validateActiveGeneration(requestedGeneration)
        } catch {
            throw error
        }
        throw error
    }

    private func cache(_ result: BridgeContentLoadResult, for key: ContentKey) {
        let previousByteCount = cachedByteCountByKey[key] ?? 0
        let byteCount = result.data.count
        contentByKey[key] = result
        cachedByteCountByKey[key] = byteCount
        totalCachedBytes += byteCount - previousByteCount
        touchCachedContent(for: key)
        evictLeastRecentlyUsedContent(preserving: key)
    }

    private func touchCachedContent(for key: ContentKey) {
        accessCounter += 1
        lastAccessCounterByKey[key] = accessCounter
    }

    private func evictLeastRecentlyUsedContent(preserving preservedKey: ContentKey) {
        while totalCachedBytes > contentCacheMaxBytes, contentByKey.count > 1 {
            let evictableKey =
                lastAccessCounterByKey
                .filter { $0.key != preservedKey && contentByKey[$0.key] != nil }
                .min { lhs, rhs in lhs.value < rhs.value }?
                .key
            guard let evictableKey else { return }
            removeCachedContent(for: evictableKey)
        }
    }

    private func removeCachedContent(for key: ContentKey) {
        guard contentByKey.removeValue(forKey: key) != nil else { return }
        totalCachedBytes -= cachedByteCountByKey.removeValue(forKey: key) ?? 0
        lastAccessCounterByKey.removeValue(forKey: key)
    }

    private func contentKey(for handle: BridgeContentHandle) -> ContentKey {
        ContentKey(
            handleId: handle.handleId,
            reviewGeneration: handle.reviewGeneration,
            itemId: handle.itemId,
            role: handle.role,
            endpointId: handle.endpointId,
            contentHash: handle.contentHash
        )
    }
}
