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

    private struct ValidatedContent {
        let result: BridgeContentLoadResult
    }

    private let provider: (any BridgeReviewSourceProvider)?
    private let contentCacheMaxBytes: Int
    private let contentMaxBytesPerItem: Int
    private var activeReviewGeneration: BridgeReviewGeneration?
    private var activeAuthorityRevision = 0
    private var handleByKey: [ContentKey: BridgeContentHandle] = [:]
    private var contentByKey: [ContentKey: ValidatedContent] = [:]
    private var keyByHandleId: [String: ContentKey] = [:]
    private var inFlightLoadByKey: [ContentKey: BridgeContentSharedLoad] = [:]
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

    var diagnosticSnapshot: BridgeContentStoreDiagnosticSnapshot {
        BridgeContentStoreDiagnosticSnapshot(
            activeHandleCount: handleByKey.count,
            cachedContentCount: contentByKey.count,
            inFlightLoadCount: inFlightLoadByKey.count,
            totalCachedBytes: totalCachedBytes
        )
    }

    @discardableResult
    func activate(
        handles: [BridgeContentHandle],
        reviewGeneration: BridgeReviewGeneration,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        guard (productAdmission.withValidAdmission { true }) == true else { return false }
        var replacementHandleByKey: [ContentKey: BridgeContentHandle] = [:]
        var replacementKeyByHandleId: [String: ContentKey] = [:]
        for handle in handles where handle.reviewGeneration == reviewGeneration {
            let key = contentKey(for: handle)
            replacementHandleByKey[key] = handle
            replacementKeyByHandleId[handle.handleId] = key
        }
        let activeKeys = Set(replacementHandleByKey.keys)
        let replacementContentByKey = contentByKey.filter { activeKeys.contains($0.key) }
        let replacementCachedByteCountByKey = cachedByteCountByKey.filter { activeKeys.contains($0.key) }
        let replacementLastAccessCounterByKey = lastAccessCounterByKey.filter { activeKeys.contains($0.key) }
        let replacementTotalCachedBytes = replacementCachedByteCountByKey.values.reduce(0, +)
        let replacementInFlightLoadByKey = inFlightLoadByKey.filter { activeKeys.contains($0.key) }
        let removedInFlightLoads = inFlightLoadByKey.compactMap { key, load in
            activeKeys.contains(key) ? nil : load
        }
        let committed =
            productAdmission.withValidAdmission {
                activeAuthorityRevision += 1
                activeReviewGeneration = reviewGeneration
                handleByKey = replacementHandleByKey
                keyByHandleId = replacementKeyByHandleId
                contentByKey = replacementContentByKey
                cachedByteCountByKey = replacementCachedByteCountByKey
                lastAccessCounterByKey = replacementLastAccessCounterByKey
                totalCachedBytes = replacementTotalCachedBytes
                inFlightLoadByKey = replacementInFlightLoadByKey
                return true
            } ?? false
        if committed {
            for removedInFlightLoad in removedInFlightLoads {
                removedInFlightLoad.cancel()
            }
        }
        return committed
    }

    func deactivate() {
        activeAuthorityRevision += 1
        activeReviewGeneration = nil
        handleByKey.removeAll(keepingCapacity: true)
        keyByHandleId.removeAll(keepingCapacity: true)
        for key in contentByKey.keys {
            removeCachedContent(for: key)
        }
        for (_, inFlightLoad) in inFlightLoadByKey {
            inFlightLoad.cancel()
        }
        inFlightLoadByKey.removeAll(keepingCapacity: true)
    }

    @discardableResult
    func register(
        _ handle: BridgeContentHandle,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        productAdmission.withValidAdmission {
            activeReviewGeneration = activeReviewGeneration ?? handle.reviewGeneration
            let key = contentKey(for: handle)
            handleByKey[key] = handle
            keyByHandleId[handle.handleId] = key
            return true
        } ?? false
    }

    @discardableResult
    func register(
        _ result: BridgeContentLoadResult,
        productAdmission: BridgeProductAdmissionContext
    ) throws -> Bool {
        guard (productAdmission.withValidAdmission { true }) == true else { return false }
        try validateResult(result, for: result.handle)
        return productAdmission.withValidAdmission {
            activeReviewGeneration = activeReviewGeneration ?? result.handle.reviewGeneration
            let key = contentKey(for: result.handle)
            handleByKey[key] = result.handle
            keyByHandleId[result.handle.handleId] = key
            cache(result, for: key)
            return true
        } ?? false
    }

    func load(
        handleId: String,
        requestedGeneration: BridgeReviewGeneration,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgeContentLoadResult {
        do {
            return try await loadObserved(
                handleId: handleId,
                requestedGeneration: requestedGeneration,
                productAdmission: productAdmission
            ).result
        } catch let failure as BridgeContentLoadObservedFailure {
            throw failure.underlyingError
        }
    }

    func loadObserved(
        handleId: String,
        requestedGeneration: BridgeReviewGeneration,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgeContentLoadObservedResult {
        try Task.checkCancellation()
        guard
            let lookup = try productAdmission.withValidAdmission({
                try activeContentHandleLookup(
                    handleId: handleId,
                    requestedGeneration: requestedGeneration
                )
            })
        else { throw BridgeContentStoreError.productAdmissionRejected }
        let key = lookup.key
        let handle = lookup.handle

        if let cachedObservedResult = try cachedObservedResult(
            lookup: lookup,
            requestedGeneration: requestedGeneration,
            productAdmission: productAdmission
        ) {
            return cachedObservedResult
        }

        let inFlightLoad: BridgeContentSharedLoad
        let cacheResult: BridgeContentLoadObservation.CacheResult
        if let activeInFlightLoad = inFlightLoadByKey[key], !activeInFlightLoad.isTerminal {
            inFlightLoad = activeInFlightLoad
            cacheResult = .inFlightCoalesced
        } else {
            inFlightLoadByKey[key] = nil
            guard let provider else {
                throw observedFailure(
                    BridgeProviderFailure.providerUnavailable,
                    handle: handle,
                    requestedGeneration: requestedGeneration,
                    cacheResult: .rejected
                )
            }
            guard
                let admittedLoad = productAdmission.withValidAdmission({
                    let task = Task {
                        try await provider.loadContent(
                            BridgeContentLoadRequest(
                                handle: handle,
                                requestedGeneration: requestedGeneration
                            )
                        )
                    }
                    let admittedLoad = BridgeContentSharedLoad(task: task)
                    inFlightLoadByKey[key] = admittedLoad
                    return admittedLoad
                })
            else { throw BridgeContentStoreError.productAdmissionRejected }
            inFlightLoad = admittedLoad
            cacheResult = .providerLoad
        }

        do {
            let result = try await inFlightLoad.value()
            removeInFlightLoadIfTerminal(inFlightLoad, for: key)
            try Task.checkCancellation()

            let normalizedResult: BridgeContentLoadResult
            let shouldCacheResult: Bool
            if let cachedContent = contentByKey[key] {
                normalizedResult = try normalizeValidatedCachedResult(
                    cachedContent,
                    lookup: lookup,
                    requestedGeneration: requestedGeneration
                )
                shouldCacheResult = false
            } else {
                normalizedResult = try normalizeActiveResult(
                    result,
                    lookup: lookup,
                    requestedGeneration: requestedGeneration
                )
                shouldCacheResult = true
            }
            let normalizedObservedResult = observedResult(normalizedResult, cacheResult: cacheResult)
            guard
                (productAdmission.withValidAdmission {
                    if shouldCacheResult {
                        cache(normalizedResult, for: key)
                    } else {
                        touchCachedContent(for: key)
                    }
                    return true
                }) == true
            else { throw BridgeContentStoreError.productAdmissionRejected }
            try Task.checkCancellation()
            return normalizedObservedResult
        } catch {
            removeInFlightLoadIfTerminal(inFlightLoad, for: key)
            try throwObservedStaleGenerationIfInvalidated(
                error,
                lookup: lookup,
                requestedGeneration: requestedGeneration,
                cacheResult: cacheResult
            )
        }
    }

    private func cachedObservedResult(
        lookup: ActiveContentHandleLookup,
        requestedGeneration: BridgeReviewGeneration,
        productAdmission: BridgeProductAdmissionContext
    ) throws -> BridgeContentLoadObservedResult? {
        guard let validatedContent = contentByKey[lookup.key] else { return nil }
        let normalizedResult = try normalizeValidatedCachedResult(
            validatedContent,
            lookup: lookup,
            requestedGeneration: requestedGeneration
        )
        let normalizedObservedResult = observedResult(normalizedResult, cacheResult: .cacheHit)
        guard
            (productAdmission.withValidAdmission {
                touchCachedContent(for: lookup.key)
                return true
            }) == true
        else { throw BridgeContentStoreError.productAdmissionRejected }
        return normalizedObservedResult
    }

    private func removeInFlightLoadIfTerminal(_ inFlightLoad: BridgeContentSharedLoad, for key: ContentKey) {
        guard inFlightLoad.isTerminal, inFlightLoadByKey[key] === inFlightLoad else { return }
        inFlightLoadByKey[key] = nil
    }

    func streamObserved(
        handleId: String,
        requestedGeneration: BridgeReviewGeneration,
        chunkByteCount: Int,
        productAdmission: BridgeProductAdmissionContext,
        emitChunk: BridgeContentStreamEmitter
    ) async throws -> BridgeContentStreamObservedResult {
        guard
            let lookup = try productAdmission.withValidAdmission({
                try activeContentHandleLookup(
                    handleId: handleId,
                    requestedGeneration: requestedGeneration
                )
            })
        else { throw BridgeContentStoreError.productAdmissionRejected }
        let key = lookup.key
        let handle = lookup.handle

        if let validatedContent = contentByKey[key] {
            let normalizedResult = try normalizeValidatedCachedResult(
                validatedContent,
                lookup: lookup,
                requestedGeneration: requestedGeneration
            )
            guard
                (productAdmission.withValidAdmission {
                    touchCachedContent(for: key)
                    return true
                }) == true
            else { throw BridgeContentStoreError.productAdmissionRejected }
            try await emitContentDataChunks(
                normalizedResult.data,
                chunkByteCount: chunkByteCount,
                productAdmission: productAdmission,
                emitChunk: emitChunk
            )
            let observedResult = streamObservedResult(
                streamResult(from: normalizedResult),
                handle: normalizedResult.handle,
                requestedGeneration: requestedGeneration,
                cacheResult: .cacheHit
            )
            guard (productAdmission.withValidAdmission { true }) == true else {
                throw BridgeContentStoreError.productAdmissionRejected
            }
            return observedResult
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
                guard (productAdmission.withValidAdmission { true }) == true else {
                    throw BridgeContentStoreError.productAdmissionRejected
                }
                try streamValidator.record(chunk)
                guard (productAdmission.withValidAdmission { true }) == true else {
                    throw BridgeContentStoreError.productAdmissionRejected
                }
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
            let observedResult = streamObservedResult(
                normalizedResult,
                handle: activeHandle,
                requestedGeneration: requestedGeneration,
                cacheResult: .providerLoad
            )
            guard (productAdmission.withValidAdmission { true }) == true else {
                throw BridgeContentStoreError.productAdmissionRejected
            }
            return observedResult
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

    private func normalizeValidatedCachedResult(
        _ validatedContent: ValidatedContent,
        lookup: ActiveContentHandleLookup,
        requestedGeneration: BridgeReviewGeneration
    ) throws -> BridgeContentLoadResult {
        let result = validatedContent.result
        let activeHandle = try validateActiveContentHandle(lookup, requestedGeneration: requestedGeneration)
        try validateResultEnvelope(result, for: activeHandle)
        try validateResultGeneration(result, for: activeHandle)
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
        try validateResultEnvelope(result, for: handle)
        let computedHash = try bridgeComputedContentHash(for: result.data, algorithm: handle.contentHashAlgorithm)
        guard computedHash == handle.contentHash else {
            throw BridgeProviderFailure.contentHashMismatch(
                handleId: handle.handleId,
                expectedHash: handle.contentHash,
                actualHash: computedHash
            )
        }
        try validateResultGeneration(result, for: handle)
    }

    private func validateResultEnvelope(
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
    }

    private func validateResultGeneration(
        _ result: BridgeContentLoadResult,
        for handle: BridgeContentHandle
    ) throws {
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
            observation: BridgeContentLoadObservationFactory.make(
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
            observation: BridgeContentLoadObservationFactory.make(
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
            observation: BridgeContentLoadObservationFactory.make(
                cacheResult: cacheResult,
                handle: handle,
                requestedGeneration: requestedGeneration,
                data: nil,
                error: error
            )
        )
    }

    private func cache(_ result: BridgeContentLoadResult, for key: ContentKey) {
        let previousByteCount = cachedByteCountByKey[key] ?? 0
        let byteCount = result.data.count
        contentByKey[key] = ValidatedContent(result: result)
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
