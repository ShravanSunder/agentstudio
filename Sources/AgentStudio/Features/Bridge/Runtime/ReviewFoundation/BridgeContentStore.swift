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
        let contentHashAlgorithm: String
        let isBinary: Bool
    }

    private struct ContentHandleAuthority: Equatable {
        let handleId: String
        let reviewGeneration: BridgeReviewGeneration
        let itemId: String
        let role: BridgeContentHandle.Role
        let endpointId: String
        let contentHash: String
        let contentHashAlgorithm: String
        let isBinary: Bool
    }

    private struct ActiveContentHandleLookup {
        let key: ContentKey
        let handle: BridgeContentHandle
        let handleAuthority: ContentHandleAuthority
        let authorityRevision: Int
    }

    private let provider: (any BridgeReviewSourceProvider)?
    private let contentCacheMaxBytes: Int
    private let contentMaxBytesPerItem: Int
    private var activeReviewGeneration: BridgeReviewGeneration?
    private var activeAuthorityRevision = 0
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
        activeAuthorityRevision += 1
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

    func deactivate() {
        activeAuthorityRevision += 1
        activeReviewGeneration = nil
        handleByKey.removeAll(keepingCapacity: true)
        keyByHandleId.removeAll(keepingCapacity: true)
        for key in contentByKey.keys {
            removeCachedContent(for: key)
        }
        for (_, task) in inFlightLoadByKey {
            task.cancel()
        }
        inFlightLoadByKey.removeAll(keepingCapacity: true)
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
        do {
            return try await loadObserved(
                handleId: handleId,
                requestedGeneration: requestedGeneration
            ).result
        } catch let failure as BridgeContentLoadObservedFailure {
            throw failure.underlyingError
        }
    }

    func loadObserved(
        handleId: String,
        requestedGeneration: BridgeReviewGeneration
    ) async throws -> BridgeContentLoadObservedResult {
        let lookup = try activeContentHandleLookup(
            handleId: handleId,
            requestedGeneration: requestedGeneration
        )
        let key = lookup.key
        let handle = lookup.handle

        if let result = contentByKey[key] {
            let normalizedResult = try normalizeActiveResult(
                result,
                lookup: lookup,
                requestedGeneration: requestedGeneration
            )
            cache(normalizedResult, for: key)
            return observedResult(normalizedResult, cacheResult: .cacheHit)
        }

        if let task = inFlightLoadByKey[key] {
            do {
                let result = try await task.value
                let normalizedResult = try normalizeActiveResult(
                    result,
                    lookup: lookup,
                    requestedGeneration: requestedGeneration
                )
                return observedResult(normalizedResult, cacheResult: .inFlightCoalesced)
            } catch {
                try throwObservedStaleGenerationIfInvalidated(
                    error,
                    lookup: lookup,
                    requestedGeneration: requestedGeneration,
                    cacheResult: .inFlightCoalesced
                )
            }
        }

        guard let provider else {
            throw observedFailure(
                BridgeProviderFailure.providerUnavailable,
                handle: handle,
                requestedGeneration: requestedGeneration,
                cacheResult: .rejected
            )
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
            let normalizedResult = try normalizeActiveResult(
                result,
                lookup: lookup,
                requestedGeneration: requestedGeneration
            )
            cache(normalizedResult, for: key)
            return observedResult(normalizedResult, cacheResult: .providerLoad)
        } catch {
            inFlightLoadByKey[key] = nil
            try throwObservedStaleGenerationIfInvalidated(
                error,
                lookup: lookup,
                requestedGeneration: requestedGeneration,
                cacheResult: .providerLoad
            )
        }
    }

    func streamObserved(
        handleId: String,
        requestedGeneration: BridgeReviewGeneration,
        chunkByteCount: Int,
        emitChunk: BridgeContentStreamEmitter
    ) async throws -> BridgeContentStreamObservedResult {
        let lookup = try activeContentHandleLookup(
            handleId: handleId,
            requestedGeneration: requestedGeneration
        )
        let key = lookup.key
        let handle = lookup.handle

        if let result = contentByKey[key] {
            let normalizedResult = try normalizeActiveResult(
                result,
                lookup: lookup,
                requestedGeneration: requestedGeneration
            )
            cache(normalizedResult, for: key)
            try await emitContentDataChunks(
                normalizedResult.data,
                chunkByteCount: chunkByteCount,
                emitChunk: emitChunk
            )
            return streamObservedResult(
                streamResult(from: normalizedResult),
                handle: normalizedResult.handle,
                requestedGeneration: requestedGeneration,
                cacheResult: .cacheHit
            )
        }

        guard let provider else {
            throw observedFailure(
                BridgeProviderFailure.providerUnavailable,
                handle: handle,
                requestedGeneration: requestedGeneration,
                cacheResult: .rejected
            )
        }

        let streamValidator = try BridgeContentStreamValidationRecorder(handle: handle)
        do {
            let result = try await provider.streamContent(
                BridgeContentStreamRequest(handle: handle, requestedGeneration: requestedGeneration),
                chunkByteCount: chunkByteCount
            ) { chunk in
                try streamValidator.record(chunk)
                try await emitChunk(chunk)
            }
            let activeHandle = try validateActiveContentHandle(
                lookup,
                requestedGeneration: requestedGeneration
            )
            let normalizedResult = try normalizeActiveStreamResult(
                result,
                activeHandle: activeHandle,
                requestedGeneration: requestedGeneration,
                computedHash: streamValidator.finalContentHash(),
                streamedByteCount: streamValidator.byteCount
            )
            return streamObservedResult(
                normalizedResult,
                handle: activeHandle,
                requestedGeneration: requestedGeneration,
                cacheResult: .providerLoad
            )
        } catch {
            try throwObservedStaleGenerationIfInvalidated(
                error,
                lookup: lookup,
                requestedGeneration: requestedGeneration,
                cacheResult: .providerLoad
            )
        }
    }

    private func activeContentHandleLookup(
        handleId: String,
        requestedGeneration: BridgeReviewGeneration
    ) throws -> ActiveContentHandleLookup {
        do {
            try validateActiveGeneration(requestedGeneration)
        } catch {
            throw observedFailure(
                error,
                handle: nil,
                requestedGeneration: requestedGeneration,
                cacheResult: .rejected
            )
        }
        guard let key = keyByHandleId[handleId], let handle = handleByKey[key] else {
            throw observedFailure(
                BridgeProviderFailure.missingContent(handleId: handleId),
                handle: nil,
                requestedGeneration: requestedGeneration,
                cacheResult: .rejected
            )
        }
        do {
            try validateHandleCanLoad(handle)
        } catch {
            throw observedFailure(
                error,
                handle: handle,
                requestedGeneration: requestedGeneration,
                cacheResult: .rejected
            )
        }
        guard key.reviewGeneration == requestedGeneration else {
            throw observedFailure(
                BridgeProviderFailure.staleReviewGeneration(
                    storedGeneration: key.reviewGeneration,
                    requestedGeneration: requestedGeneration
                ),
                handle: handle,
                requestedGeneration: requestedGeneration,
                cacheResult: .rejected
            )
        }
        return ActiveContentHandleLookup(
            key: key,
            handle: handle,
            handleAuthority: contentHandleAuthority(for: handle),
            authorityRevision: activeAuthorityRevision
        )
    }

    func metadata(handleId: String, requestedGeneration: BridgeReviewGeneration) throws -> BridgeContentHandle {
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
        return handle
    }

    private func validateActiveGeneration(_ requestedGeneration: BridgeReviewGeneration) throws {
        guard let activeReviewGeneration, activeReviewGeneration != requestedGeneration else { return }
        throw BridgeProviderFailure.staleReviewGeneration(
            storedGeneration: activeReviewGeneration,
            requestedGeneration: requestedGeneration
        )
    }

    private func validateActiveContentHandle(
        _ lookup: ActiveContentHandleLookup,
        requestedGeneration: BridgeReviewGeneration
    ) throws -> BridgeContentHandle {
        try validateActiveGeneration(requestedGeneration)
        guard lookup.authorityRevision != activeAuthorityRevision else { return lookup.handle }
        guard let activeHandle = handleByKey[lookup.key],
            contentHandleAuthority(for: activeHandle) == lookup.handleAuthority,
            keyByHandleId[lookup.handle.handleId] == lookup.key
        else {
            throw BridgeProviderFailure.missingContent(handleId: lookup.handle.handleId)
        }
        return activeHandle
    }

    private func normalizeActiveResult(
        _ result: BridgeContentLoadResult,
        lookup: ActiveContentHandleLookup,
        requestedGeneration: BridgeReviewGeneration
    ) throws -> BridgeContentLoadResult {
        let activeHandle = try validateActiveContentHandle(lookup, requestedGeneration: requestedGeneration)
        try validateResult(result, for: activeHandle)
        return BridgeContentLoadResult(
            handle: activeHandle,
            data: result.data,
            mimeType: activeHandle.mimeType,
            contentHash: activeHandle.contentHash,
            contentHashAlgorithm: activeHandle.contentHashAlgorithm
        )
    }

    private func normalizeActiveStreamResult(
        _ result: BridgeContentStreamResult,
        activeHandle: BridgeContentHandle,
        requestedGeneration: BridgeReviewGeneration,
        computedHash: String,
        streamedByteCount: Int
    ) throws -> BridgeContentStreamResult {
        try validateStreamResult(
            result,
            for: activeHandle,
            computedHash: computedHash,
            streamedByteCount: streamedByteCount
        )
        guard result.handle.reviewGeneration == requestedGeneration else {
            throw BridgeProviderFailure.staleReviewGeneration(
                storedGeneration: activeHandle.reviewGeneration,
                requestedGeneration: result.handle.reviewGeneration
            )
        }
        return BridgeContentStreamResult(
            handle: activeHandle,
            byteCount: result.byteCount,
            mimeType: activeHandle.mimeType,
            contentHash: activeHandle.contentHash,
            contentHashAlgorithm: activeHandle.contentHashAlgorithm
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
        guard handle.sizeBytesIsExact == false || result.data.count <= handle.sizeBytes else {
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

    private func validateStreamResult(
        _ result: BridgeContentStreamResult,
        for handle: BridgeContentHandle,
        computedHash: String,
        streamedByteCount: Int
    ) throws {
        try validateHandleCanLoad(handle)
        guard result.byteCount == streamedByteCount else {
            throw BridgeProviderFailure.providerFailed(
                message:
                    "Streamed content byte count mismatch for \(handle.handleId): expected=\(result.byteCount):actual=\(streamedByteCount)"
            )
        }
        guard result.byteCount <= contentMaxBytesPerItem else {
            throw BridgeProviderFailure.oversizedContent(
                handleId: handle.handleId,
                sizeBytes: result.byteCount
            )
        }
        guard handle.sizeBytesIsExact == false || result.byteCount <= handle.sizeBytes else {
            throw BridgeProviderFailure.oversizedContent(
                handleId: handle.handleId,
                sizeBytes: result.byteCount
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
        case "git-blob-sha1":
            var blobData = Data("blob \(data.count)\0".utf8)
            blobData.append(data)
            let digest = Insecure.SHA1.hash(data: blobData)
            return digest.map { String(format: "%02x", $0) }.joined()
        default:
            throw BridgeProviderFailure.providerFailed(message: "Unsupported content hash algorithm: \(algorithm)")
        }
    }

    private func throwObservedStaleGenerationIfInvalidated(
        _ error: any Error,
        lookup: ActiveContentHandleLookup,
        requestedGeneration: BridgeReviewGeneration,
        cacheResult: BridgeContentLoadObservation.CacheResult
    ) throws -> Never {
        do {
            _ = try validateActiveContentHandle(lookup, requestedGeneration: requestedGeneration)
        } catch let invalidationError {
            throw observedFailure(
                invalidationError,
                handle: lookup.handle,
                requestedGeneration: requestedGeneration,
                cacheResult: .rejected
            )
        }
        throw observedFailure(
            error,
            handle: lookup.handle,
            requestedGeneration: requestedGeneration,
            cacheResult: cacheResult
        )
    }

    private func observedResult(
        _ result: BridgeContentLoadResult,
        cacheResult: BridgeContentLoadObservation.CacheResult
    ) -> BridgeContentLoadObservedResult {
        BridgeContentLoadObservedResult(
            result: result,
            observation: observation(
                cacheResult: cacheResult,
                handle: result.handle,
                requestedGeneration: result.handle.reviewGeneration,
                data: result.data,
                error: nil
            )
        )
    }

    private func streamObservedResult(
        _ result: BridgeContentStreamResult,
        handle: BridgeContentHandle,
        requestedGeneration: BridgeReviewGeneration,
        cacheResult: BridgeContentLoadObservation.CacheResult
    ) -> BridgeContentStreamObservedResult {
        BridgeContentStreamObservedResult(
            result: result,
            observation: observation(
                cacheResult: cacheResult,
                handle: handle,
                requestedGeneration: requestedGeneration,
                data: nil,
                error: nil
            )
        )
    }

    private func streamResult(from result: BridgeContentLoadResult) -> BridgeContentStreamResult {
        BridgeContentStreamResult(
            handle: result.handle,
            byteCount: result.data.count,
            mimeType: result.mimeType,
            contentHash: result.contentHash,
            contentHashAlgorithm: result.contentHashAlgorithm
        )
    }

    private func observedFailure(
        _ error: any Error,
        handle: BridgeContentHandle?,
        requestedGeneration: BridgeReviewGeneration,
        cacheResult: BridgeContentLoadObservation.CacheResult
    ) -> BridgeContentLoadObservedFailure {
        BridgeContentLoadObservedFailure(
            underlyingError: error,
            observation: observation(
                cacheResult: cacheResult,
                handle: handle,
                requestedGeneration: requestedGeneration,
                data: nil,
                error: error
            )
        )
    }

    private func observation(
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

    private func generationRelation(
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

    private func byteSize(for data: Data?, handle: BridgeContentHandle?, error: (any Error)?) -> Int {
        if let data {
            return data.count
        }
        if case .oversizedContent(_, let sizeBytes)? = error as? BridgeProviderFailure {
            return sizeBytes
        }
        return handle?.sizeBytes ?? 0
    }

    private func isBinary(handle: BridgeContentHandle?, error: (any Error)?) -> Bool {
        if case .binaryContent? = error as? BridgeProviderFailure {
            return true
        }
        return handle?.isBinary ?? false
    }

    private func isStale(_ error: (any Error)?) -> Bool {
        if case .staleReviewGeneration? = error as? BridgeProviderFailure {
            return true
        }
        return false
    }

    private func byteSizeBucket(for byteSize: Int) -> Int {
        guard byteSize > 0 else {
            return 0
        }
        var bucket = 1024
        while bucket < byteSize, bucket < 64 * 1024 * 1024 {
            bucket *= 2
        }
        return bucket
    }

    private func lineCountBucket(for data: Data?) -> Int {
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

    private func cache(_ result: BridgeContentLoadResult, for key: ContentKey) {
        let previousByteCount = cachedByteCountByKey[key] ?? 0
        let byteCount = result.data.count
        contentByKey[key] = result
        cachedByteCountByKey[key] = byteCount
        totalCachedBytes += byteCount - previousByteCount
        touchCachedContent(for: key)
        evictLeastRecentlyUsedContent(preserving: key)
    }

    private func emitContentDataChunks(
        _ data: Data,
        chunkByteCount: Int,
        emitChunk: BridgeContentStreamEmitter
    ) async throws {
        var offset = 0
        while offset < data.count {
            let endOffset = min(offset + chunkByteCount, data.count)
            try await emitChunk(data.subdata(in: offset..<endOffset))
            offset = endOffset
        }
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
            contentHash: handle.contentHash,
            contentHashAlgorithm: handle.contentHashAlgorithm,
            isBinary: handle.isBinary
        )
    }

    private func contentHandleAuthority(for handle: BridgeContentHandle) -> ContentHandleAuthority {
        ContentHandleAuthority(
            handleId: handle.handleId,
            reviewGeneration: handle.reviewGeneration,
            itemId: handle.itemId,
            role: handle.role,
            endpointId: handle.endpointId,
            contentHash: handle.contentHash,
            contentHashAlgorithm: handle.contentHashAlgorithm,
            isBinary: handle.isBinary
        )
    }
}

private enum BridgeContentStreamHasher {
    case sha256(SHA256)
    case gitBlobSHA1(Insecure.SHA1)
    case deferredGitBlobSHA1(Data)

    init(handle: BridgeContentHandle) throws {
        switch handle.contentHashAlgorithm.lowercased() {
        case "sha256", "sha-256":
            self = .sha256(SHA256())
        case "git-blob-sha1":
            guard handle.sizeBytesIsExact else {
                self = .deferredGitBlobSHA1(Data())
                return
            }
            var hasher = Insecure.SHA1()
            hasher.update(data: Data("blob \(handle.sizeBytes)\0".utf8))
            self = .gitBlobSHA1(hasher)
        default:
            throw BridgeProviderFailure.providerFailed(
                message: "Unsupported content hash algorithm: \(handle.contentHashAlgorithm)"
            )
        }
    }

    mutating func update(data: Data) {
        switch self {
        case .sha256(var hasher):
            hasher.update(data: data)
            self = .sha256(hasher)
        case .gitBlobSHA1(var hasher):
            hasher.update(data: data)
            self = .gitBlobSHA1(hasher)
        case .deferredGitBlobSHA1(var bufferedData):
            bufferedData.append(data)
            self = .deferredGitBlobSHA1(bufferedData)
        }
    }

    mutating func finalize() -> String {
        switch self {
        case .sha256(let hasher):
            let digest = hasher.finalize()
            self = .sha256(SHA256())
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            return "sha256:\(hex)"
        case .gitBlobSHA1(let hasher):
            let digest = hasher.finalize()
            self = .gitBlobSHA1(Insecure.SHA1())
            return digest.map { String(format: "%02x", $0) }.joined()
        case .deferredGitBlobSHA1(let bufferedData):
            var hasher = Insecure.SHA1()
            hasher.update(data: Data("blob \(bufferedData.count)\0".utf8))
            hasher.update(data: bufferedData)
            let digest = hasher.finalize()
            self = .deferredGitBlobSHA1(Data())
            return digest.map { String(format: "%02x", $0) }.joined()
        }
    }
}

private final class BridgeContentStreamValidationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let handleId: String
    private let maxByteCount: Int
    private var hasher: BridgeContentStreamHasher
    private var recordedByteCount = 0

    var byteCount: Int {
        lock.withLock { recordedByteCount }
    }

    init(handle: BridgeContentHandle) throws {
        self.handleId = handle.handleId
        self.maxByteCount =
            handle.sizeBytesIsExact
            ? min(handle.sizeBytes, AppPolicies.Bridge.contentMaxBytesPerItem)
            : AppPolicies.Bridge.contentMaxBytesPerItem
        self.hasher = try BridgeContentStreamHasher(handle: handle)
    }

    func record(_ chunk: Data) throws {
        try lock.withLock {
            recordedByteCount += chunk.count
            guard recordedByteCount <= maxByteCount else {
                throw BridgeProviderFailure.oversizedContent(
                    handleId: handleId,
                    sizeBytes: recordedByteCount
                )
            }
            hasher.update(data: chunk)
        }
    }

    func finalContentHash() -> String {
        lock.withLock {
            hasher.finalize()
        }
    }
}
