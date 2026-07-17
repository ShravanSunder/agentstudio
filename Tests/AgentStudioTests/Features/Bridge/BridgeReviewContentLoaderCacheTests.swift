import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge Review content loader cache")
struct BridgeReviewContentLoaderCacheTests {
    @Test("loader cache owns loading and caching, never publication authority")
    func loaderCacheOwnsOnlyLoadingAndCaching() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/BridgeReviewContentLoaderCache.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("actor BridgeReviewContentLoaderCache"))
        #expect(!source.contains("activeReviewGeneration"))
        #expect(!source.contains("activeAuthorityRevision"))
        #expect(!source.contains("handleByKey"))
        #expect(!source.contains("keyByHandleId"))
        #expect(!source.contains("func activate("))
        #expect(!source.contains("func deactivate("))
        #expect(!source.contains("func register("))
        #expect(!source.contains("func metadata("))
    }

    @Test("first handle load validates provider bytes and the second hits cache")
    func firstLoadValidatesProviderAndSecondLoadHitsCache() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let handle = makeLoaderCacheHandle(content: "cached")
        let provider = makeLoaderCacheProvider(results: [makeContentResult(handle: handle, data: "cached")])
        let cache = BridgeReviewContentLoaderCache(provider: provider)

        let first = try await cache.loadObserved(
            handle: handle,
            productAdmission: admission.context
        )
        let second = try await cache.loadObserved(
            handle: handle,
            productAdmission: admission.context
        )

        #expect(first.result.data == Data("cached".utf8))
        #expect(first.observation.cacheResult == .providerLoad)
        #expect(second.observation.cacheResult == .cacheHit)
        #expect(await provider.recordedContentRequestsCount() == 1)
    }

    @Test("concurrent callers coalesce one immutable handle load")
    func concurrentCallersCoalesceOneLoad() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let handle = makeLoaderCacheHandle(content: "coalesced")
        let gate = BridgeContentLoadGate()
        let provider = makeLoaderCacheProvider(
            results: [makeContentResult(handle: handle, data: "coalesced")],
            gate: gate
        )
        let cache = BridgeReviewContentLoaderCache(provider: provider)

        async let first = cache.loadObserved(handle: handle, productAdmission: admission.context)
        await gate.waitForStartedLoadCount(1)
        async let second = cache.loadObserved(handle: handle, productAdmission: admission.context)
        async let third = cache.loadObserved(handle: handle, productAdmission: admission.context)
        await Task.yield()
        await gate.releaseAll()
        let results = try await [first, second, third]

        #expect(results.map(\.result.data) == Array(repeating: Data("coalesced".utf8), count: 3))
        #expect(results.map(\.observation.cacheResult).contains(.providerLoad))
        #expect(results.map(\.observation.cacheResult).filter { $0 == .inFlightCoalesced }.count == 2)
        #expect(await provider.recordedContentRequestsCount() == 1)
    }

    @Test("cache rejects a provider result with mismatched handle identity")
    func rejectsMismatchedProviderIdentity() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let handle = makeLoaderCacheHandle(content: "identity")
        let mismatchedHandle = BridgeContentHandle(
            handleId: handle.handleId,
            itemId: "different-item",
            role: handle.role,
            endpointId: handle.endpointId,
            reviewGeneration: handle.reviewGeneration,
            contentHash: handle.contentHash,
            contentHashAlgorithm: handle.contentHashAlgorithm,
            cacheKey: handle.cacheKey,
            mimeType: handle.mimeType,
            language: handle.language,
            sizeBytes: handle.sizeBytes,
            sizeBytesIsExact: handle.sizeBytesIsExact,
            isBinary: handle.isBinary
        )
        let provider = makeLoaderCacheProvider(
            results: [makeContentResult(handle: mismatchedHandle, data: "identity")]
        )
        let cache = BridgeReviewContentLoaderCache(provider: provider)

        await #expect(throws: BridgeProviderFailure.self) {
            _ = try await cache.load(handle: handle, productAdmission: admission.context)
        }
    }

    @Test("cache rejects content whose computed hash differs from the issued handle")
    func rejectsComputedHashMismatch() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let handle = makeLoaderCacheHandle(content: "expected")
        let forgedResult = BridgeContentLoadResult(
            handle: handle,
            data: Data("different".utf8),
            mimeType: handle.mimeType,
            contentHash: handle.contentHash,
            contentHashAlgorithm: handle.contentHashAlgorithm
        )
        let cache = BridgeReviewContentLoaderCache(
            provider: makeLoaderCacheProvider(results: [forgedResult])
        )

        await #expect(throws: BridgeProviderFailure.self) {
            _ = try await cache.load(handle: handle, productAdmission: admission.context)
        }
    }

    @Test("cache rejects binary and oversized handles before publication")
    func rejectsBinaryAndOversizedContent() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let binaryHandle = makeBridgeContentHandle(
            itemId: "binary-item",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("binary"),
            sizeBytes: 6,
            isBinary: true
        )
        let oversizedHandle = makeLoaderCacheHandle(content: "1234567", itemId: "oversized-item")
        let provider = makeLoaderCacheProvider(
            results: [makeContentResult(handle: oversizedHandle, data: "1234567")]
        )
        let cache = BridgeReviewContentLoaderCache(
            provider: provider,
            contentMaxBytesPerItem: 6
        )

        await #expect(throws: BridgeProviderFailure.self) {
            _ = try await cache.load(handle: binaryHandle, productAdmission: admission.context)
        }
        await #expect(throws: BridgeProviderFailure.self) {
            _ = try await cache.load(handle: oversizedHandle, productAdmission: admission.context)
        }
    }

    @Test("closing admission while provider is suspended prevents cache publication")
    func admissionClosePreventsLateCachePublication() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let handle = makeLoaderCacheHandle(content: "late")
        let gate = BridgeContentLoadGate()
        let provider = makeLoaderCacheProvider(
            results: [makeContentResult(handle: handle, data: "late")],
            gate: gate
        )
        let cache = BridgeReviewContentLoaderCache(provider: provider)
        let load = Task {
            try await cache.load(handle: handle, productAdmission: admission.context)
        }
        await gate.waitForStartedLoadCount(1)

        admission.close()
        await gate.releaseAll()

        await #expect(throws: BridgeReviewContentLoaderCacheError.self) {
            _ = try await load.value
        }
        #expect((await cache.diagnosticSnapshot).cachedContentCount == 0)
    }

    @Test("close and drain rejects future work and reports zero residue")
    func closeAndDrainRejectsFutureWorkAndReportsZeroResidue() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let handle = makeLoaderCacheHandle(content: "draining")
        let gate = BridgeContentLoadGate()
        let provider = makeLoaderCacheProvider(
            results: [makeContentResult(handle: handle, data: "draining")],
            gate: gate
        )
        let cache = BridgeReviewContentLoaderCache(provider: provider)
        let load = Task {
            try await cache.load(handle: handle, productAdmission: admission.context)
        }
        await gate.waitForStartedLoadCount(1)
        let close = Task { await cache.closeAndDrain() }
        await gate.releaseAll()

        _ = try? await load.value
        await close.value
        let snapshot = await cache.diagnosticSnapshot

        #expect(snapshot.isClosed)
        #expect(snapshot.cachedContentCount == 0)
        #expect(snapshot.inFlightLoadCount == 0)
        #expect(snapshot.totalCachedBytes == 0)
        await #expect(throws: BridgeReviewContentLoaderCacheError.self) {
            _ = try await cache.load(handle: handle, productAdmission: admission.context)
        }
    }

    @Test("byte-bounded LRU evicts the least recently used immutable item")
    func byteBoundedLRUEvictsLeastRecentlyUsedItem() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let firstHandle = makeLoaderCacheHandle(content: "111", itemId: "first")
        let secondHandle = makeLoaderCacheHandle(content: "222", itemId: "second")
        let thirdHandle = makeLoaderCacheHandle(content: "333", itemId: "third")
        let provider = makeLoaderCacheProvider(
            results: [
                makeContentResult(handle: firstHandle, data: "111"),
                makeContentResult(handle: secondHandle, data: "222"),
                makeContentResult(handle: thirdHandle, data: "333"),
            ]
        )
        let cache = BridgeReviewContentLoaderCache(provider: provider, contentCacheMaxBytes: 6)

        _ = try await cache.load(handle: firstHandle, productAdmission: admission.context)
        _ = try await cache.load(handle: secondHandle, productAdmission: admission.context)
        _ = try await cache.load(handle: firstHandle, productAdmission: admission.context)
        _ = try await cache.load(handle: thirdHandle, productAdmission: admission.context)
        _ = try await cache.load(handle: firstHandle, productAdmission: admission.context)
        _ = try await cache.load(handle: secondHandle, productAdmission: admission.context)

        #expect(await provider.recordedContentRequestsCount() == 4)
        #expect((await cache.diagnosticSnapshot).totalCachedBytes == 6)
    }
}

private func makeLoaderCacheHandle(
    content: String,
    itemId: String = "loader-item"
) -> BridgeContentHandle {
    makeBridgeContentHandle(
        itemId: itemId,
        role: .head,
        reviewGeneration: 7,
        contentHash: bridgeSHA256ContentHash(content),
        sizeBytes: content.utf8.count
    )
}

private func makeLoaderCacheProvider(
    results: [BridgeContentLoadResult],
    gate: BridgeContentLoadGate? = nil
) -> BridgeReviewSourceProviderFake {
    BridgeReviewSourceProviderFake(
        comparison: BridgeEndpointComparison(
            baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
            headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
            changedFiles: []
        ),
        contentByHandleId: Dictionary(
            results.map { ($0.handle.handleId, $0) },
            uniquingKeysWith: { _, replacement in replacement }
        ),
        contentLoadGate: gate
    )
}
