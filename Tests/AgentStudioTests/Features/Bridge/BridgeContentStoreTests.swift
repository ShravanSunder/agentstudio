import Foundation
import Testing

@testable import AgentStudio

struct BridgeContentStoreTests {
    @Test("content store resolves base and head content by scoped handle")
    func contentStoreResolvesBaseAndHeadContentByScopedHandle() async throws {
        let store = BridgeContentStore()
        let baseHandle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .base,
            endpointId: "base",
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("old")
        )
        let headHandle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            endpointId: "head",
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("new")
        )
        let baseResult = makeContentResult(handle: baseHandle, data: "old")
        let headResult = makeContentResult(handle: headHandle, data: "new")

        try await store.register(baseResult)
        try await store.register(headResult)
        let loadedBase = try await store.load(handleId: baseHandle.handleId, requestedGeneration: 7)
        let loadedHead = try await store.load(handleId: headHandle.handleId, requestedGeneration: 7)

        #expect(loadedBase == baseResult)
        #expect(loadedHead == headResult)
    }

    @Test("content store rejects stale review generation requests")
    func contentStoreRejectsStaleReviewGenerationRequests() async throws {
        let store = BridgeContentStore()
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("hello")
        )
        try await store.register(makeContentResult(handle: handle, data: "hello"))

        await #expect(throws: BridgeProviderFailure.self) {
            _ = try await store.load(handleId: handle.handleId, requestedGeneration: 6)
        }
    }

    @Test("content store rejects unknown handles")
    func contentStoreRejectsUnknownHandles() async throws {
        let store = BridgeContentStore()

        do {
            _ = try await store.load(handleId: "missing", requestedGeneration: 7)
            Issue.record("Expected missing content failure")
        } catch let failure as BridgeProviderFailure {
            #expect(failure == .missingContent(handleId: "missing"))
        } catch {
            Issue.record("Expected BridgeProviderFailure, got \(error)")
        }
    }

    @Test("content store lazily fetches known handles and reuses cached bytes")
    func contentStoreLazilyFetchesKnownHandlesAndReusesCachedBytes() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("lazy")
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "lazy")
            ]
        )
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7)

        let firstLoad = try await store.load(handleId: handle.handleId, requestedGeneration: 7)
        let secondLoad = try await store.load(handleId: handle.handleId, requestedGeneration: 7)

        #expect(firstLoad.data == Data("lazy".utf8))
        #expect(secondLoad.data == Data("lazy".utf8))
        #expect(await provider.recordedContentRequestsCount() == 1)
    }

    @Test("content store observations identify provider load then cache hit")
    func contentStoreObservationsIdentifyProviderLoadThenCacheHit() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("lazy")
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "lazy")
            ]
        )
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7)

        let firstLoad = try await store.loadObserved(handleId: handle.handleId, requestedGeneration: 7)
        let secondLoad = try await store.loadObserved(handleId: handle.handleId, requestedGeneration: 7)

        #expect(firstLoad.observation.cacheResult == .providerLoad)
        #expect(firstLoad.observation.role == .head)
        #expect(firstLoad.observation.generationRelation == .current)
        #expect(firstLoad.observation.byteSizeBucket == 1024)
        #expect(firstLoad.observation.lineCountBucket == 1)
        #expect(firstLoad.observation.isBinary == false)
        #expect(firstLoad.observation.isStale == false)
        #expect(secondLoad.observation.cacheResult == .cacheHit)
        #expect(secondLoad.result.data == Data("lazy".utf8))
    }

    @Test("content store coalesces concurrent loads for the same handle")
    func contentStoreCoalescesConcurrentLoadsForSameHandle() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("coalesced")
        )
        let gate = BridgeContentLoadGate()
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "coalesced")
            ],
            contentLoadGate: gate
        )
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7)

        async let firstLoad = try store.load(handleId: handle.handleId, requestedGeneration: 7)
        await gate.waitForStartedLoadCount(1)
        async let secondLoad = try store.load(handleId: handle.handleId, requestedGeneration: 7)
        async let thirdLoad = try store.load(handleId: handle.handleId, requestedGeneration: 7)
        await Task.yield()
        await gate.releaseAll()
        let loaded = try await [firstLoad, secondLoad, thirdLoad]

        #expect(loaded.map { $0.data } == Array(repeating: Data("coalesced".utf8), count: 3))
        #expect(await provider.recordedContentRequestsCount() == 1)
    }

    @Test("content store observations identify in-flight coalesced loads")
    func contentStoreObservationsIdentifyInFlightCoalescedLoads() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("coalesced")
        )
        let gate = BridgeContentLoadGate()
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "coalesced")
            ],
            contentLoadGate: gate
        )
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7)

        async let firstLoad = try store.loadObserved(handleId: handle.handleId, requestedGeneration: 7)
        await gate.waitForStartedLoadCount(1)
        async let secondLoad = try store.loadObserved(handleId: handle.handleId, requestedGeneration: 7)
        await gate.releaseAll()

        let observations = try await [firstLoad.observation, secondLoad.observation]
        #expect(observations.map(\.cacheResult).contains(.providerLoad))
        #expect(observations.map(\.cacheResult).contains(.inFlightCoalesced))
        #expect(await provider.recordedContentRequestsCount() == 1)
    }

    @Test("content store rejects provider content hash mismatches")
    func contentStoreRejectsProviderContentHashMismatches() async throws {
        let changedHash = bridgeSHA256ContentHash("changed")
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("expected")
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: BridgeContentLoadResult(
                    handle: handle,
                    data: Data("changed".utf8),
                    mimeType: handle.mimeType,
                    contentHash: changedHash,
                    contentHashAlgorithm: handle.contentHashAlgorithm
                )
            ]
        )
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7)

        do {
            _ = try await store.load(handleId: handle.handleId, requestedGeneration: 7)
            Issue.record("Expected content hash mismatch")
        } catch let failure as BridgeProviderFailure {
            #expect(
                failure
                    == .contentHashMismatch(
                        handleId: handle.handleId,
                        expectedHash: handle.contentHash,
                        actualHash: changedHash
                    ))
        } catch {
            Issue.record("Expected BridgeProviderFailure, got \(error)")
        }
    }

    @Test("content store rejects provider bytes that do not match expected hash")
    func contentStoreRejectsProviderBytesThatDoNotMatchExpectedHash() async throws {
        let tamperedHash = bridgeSHA256ContentHash("tampered")
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("original")
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: BridgeContentLoadResult(
                    handle: handle,
                    data: Data("tampered".utf8),
                    mimeType: handle.mimeType,
                    contentHash: handle.contentHash,
                    contentHashAlgorithm: handle.contentHashAlgorithm
                )
            ]
        )
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7)

        do {
            _ = try await store.load(handleId: handle.handleId, requestedGeneration: 7)
            Issue.record("Expected content hash mismatch")
        } catch let failure as BridgeProviderFailure {
            #expect(
                failure
                    == .contentHashMismatch(
                        handleId: handle.handleId,
                        expectedHash: handle.contentHash,
                        actualHash: tamperedHash
                    ))
        } catch {
            Issue.record("Expected BridgeProviderFailure, got \(error)")
        }
    }

    @Test("content store rejects binary handles before loading provider bytes")
    func contentStoreRejectsBinaryHandlesBeforeLoadingProviderBytes() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("binary"),
            isBinary: true
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "binary")
            ]
        )
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7)

        do {
            _ = try await store.load(handleId: handle.handleId, requestedGeneration: 7)
            Issue.record("Expected binary content failure")
        } catch let failure as BridgeProviderFailure {
            #expect(failure == .binaryContent(handleId: handle.handleId))
        } catch {
            Issue.record("Expected BridgeProviderFailure, got \(error)")
        }
        #expect(await provider.recordedContentRequestsCount() == 0)
    }

    @Test("content store observations identify binary rejections")
    func contentStoreObservationsIdentifyBinaryRejections() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("binary"),
            isBinary: true
        )
        let store = BridgeContentStore()
        await store.activate(handles: [handle], reviewGeneration: 7)

        do {
            _ = try await store.loadObserved(handleId: handle.handleId, requestedGeneration: 7)
            Issue.record("Expected binary content failure")
        } catch let failure as BridgeContentLoadObservedFailure {
            #expect(failure.underlyingError as? BridgeProviderFailure == .binaryContent(handleId: handle.handleId))
            #expect(failure.observation.cacheResult == .rejected)
            #expect(failure.observation.isBinary == true)
            #expect(failure.observation.isStale == false)
        } catch {
            Issue.record("Expected BridgeContentLoadObservedFailure, got \(error)")
        }
    }

    @Test("content store rejects payloads larger than per-item byte cap")
    func contentStoreRejectsPayloadsLargerThanPerItemByteCap() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("seven!!"),
            sizeBytes: 7
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "seven!!")
            ]
        )
        let store = BridgeContentStore(provider: provider, contentMaxBytesPerItem: 6)
        await store.activate(handles: [handle], reviewGeneration: 7)

        do {
            _ = try await store.load(handleId: handle.handleId, requestedGeneration: 7)
            Issue.record("Expected oversized content failure")
        } catch let failure as BridgeProviderFailure {
            #expect(failure == .oversizedContent(handleId: handle.handleId, sizeBytes: 7))
        } catch {
            Issue.record("Expected BridgeProviderFailure, got \(error)")
        }
    }

    @Test("content store observations identify oversized provider bytes")
    func contentStoreObservationsIdentifyOversizedProviderBytes() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("seven!!"),
            sizeBytes: 7
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "seven!!")
            ]
        )
        let store = BridgeContentStore(provider: provider, contentMaxBytesPerItem: 6)
        await store.activate(handles: [handle], reviewGeneration: 7)

        do {
            _ = try await store.loadObserved(handleId: handle.handleId, requestedGeneration: 7)
            Issue.record("Expected oversized content failure")
        } catch let failure as BridgeContentLoadObservedFailure {
            let expected = BridgeProviderFailure.oversizedContent(
                handleId: handle.handleId,
                sizeBytes: 7
            )
            #expect(failure.underlyingError as? BridgeProviderFailure == expected)
            #expect(failure.observation.cacheResult == .providerLoad)
            #expect(failure.observation.byteSizeBucket == 1024)
            #expect(failure.observation.isBinary == false)
        } catch {
            Issue.record("Expected BridgeContentLoadObservedFailure, got \(error)")
        }
    }

    @Test("content store observations identify stale generation rejections")
    func contentStoreObservationsIdentifyStaleGenerationRejections() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("hello")
        )
        let store = BridgeContentStore()
        try await store.register(makeContentResult(handle: handle, data: "hello"))

        do {
            _ = try await store.loadObserved(handleId: handle.handleId, requestedGeneration: 6)
            Issue.record("Expected stale content failure")
        } catch let failure as BridgeContentLoadObservedFailure {
            #expect(
                failure.underlyingError as? BridgeProviderFailure
                    == .staleReviewGeneration(storedGeneration: 7, requestedGeneration: 6)
            )
            #expect(failure.observation.cacheResult == .rejected)
            #expect(failure.observation.generationRelation == .stale)
            #expect(failure.observation.isStale == true)
        } catch {
            Issue.record("Expected BridgeContentLoadObservedFailure, got \(error)")
        }
    }

    @Test("content store rejects stale in-flight loads after generation activation")
    func contentStoreRejectsStaleInFlightLoadsAfterGenerationActivation() async throws {
        let oldHandle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("old")
        )
        let newHandle = makeBridgeContentHandle(itemId: "item-1", role: .head, reviewGeneration: 8)
        let gate = BridgeContentLoadGate()
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                oldHandle.handleId: makeContentResult(handle: oldHandle, data: "old")
            ],
            contentLoadGate: gate
        )
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [oldHandle], reviewGeneration: 7)

        async let staleLoad = try store.load(handleId: oldHandle.handleId, requestedGeneration: 7)
        await gate.waitForStartedLoadCount(1)
        await store.activate(handles: [newHandle], reviewGeneration: 8)
        await gate.releaseAll()

        do {
            _ = try await staleLoad
            Issue.record("Expected stale generation failure")
        } catch let failure as BridgeProviderFailure {
            #expect(failure == .staleReviewGeneration(storedGeneration: 8, requestedGeneration: 7))
        } catch {
            Issue.record("Expected BridgeProviderFailure, got \(error)")
        }
    }

    @Test("content store rejects in-flight loads after deactivation")
    func contentStoreRejectsInFlightLoadsAfterDeactivation() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("revoked")
        )
        let gate = BridgeContentLoadGate()
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                handle.handleId: makeContentResult(handle: handle, data: "revoked")
            ],
            contentLoadGate: gate
        )
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7)

        async let revokedLoad = try store.load(handleId: handle.handleId, requestedGeneration: 7)
        await gate.waitForStartedLoadCount(1)
        await store.deactivate()
        await gate.releaseAll()

        do {
            _ = try await revokedLoad
            Issue.record("Expected revoked content authority failure")
        } catch let failure as BridgeProviderFailure {
            #expect(failure == .missingContent(handleId: handle.handleId))
        } catch {
            Issue.record("Expected BridgeProviderFailure, got \(error)")
        }
    }

    @Test("content store rejects invalid direct registrations")
    func contentStoreRejectsInvalidDirectRegistrations() async throws {
        let handle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("expected")
        )
        let result = BridgeContentLoadResult(
            handle: handle,
            data: Data("tampered".utf8),
            mimeType: handle.mimeType,
            contentHash: handle.contentHash,
            contentHashAlgorithm: handle.contentHashAlgorithm
        )
        let store = BridgeContentStore()

        do {
            try await store.register(result)
            Issue.record("Expected content hash mismatch")
        } catch let failure as BridgeProviderFailure {
            #expect(
                failure
                    == .contentHashMismatch(
                        handleId: handle.handleId,
                        expectedHash: handle.contentHash,
                        actualHash: bridgeSHA256ContentHash("tampered")
                    ))
        } catch {
            Issue.record("Expected BridgeProviderFailure, got \(error)")
        }
    }

    @Test("content store translates cancellation-aware stale in-flight loads")
    func contentStoreTranslatesCancellationAwareStaleInFlightLoads() async throws {
        let oldHandle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("old")
        )
        let newHandle = makeBridgeContentHandle(itemId: "item-1", role: .head, reviewGeneration: 8)
        let gate = BridgeContentLoadGate()
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                oldHandle.handleId: makeContentResult(handle: oldHandle, data: "old")
            ],
            contentLoadGate: gate,
            checksCancellationAfterGate: true
        )
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [oldHandle], reviewGeneration: 7)

        async let staleLoad = try store.load(handleId: oldHandle.handleId, requestedGeneration: 7)
        await gate.waitForStartedLoadCount(1)
        await store.activate(handles: [newHandle], reviewGeneration: 8)
        await gate.releaseAll()

        do {
            _ = try await staleLoad
            Issue.record("Expected stale generation failure")
        } catch let failure as BridgeProviderFailure {
            #expect(failure == .staleReviewGeneration(storedGeneration: 8, requestedGeneration: 7))
        } catch {
            Issue.record("Expected BridgeProviderFailure, got \(error)")
        }
    }

    @Test("content store evicts active generation content by LRU byte cap")
    func contentStoreEvictsActiveGenerationContentByLRUByteCap() async throws {
        let firstHandle = makeBridgeContentHandle(
            itemId: "item-1",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("one")
        )
        let secondHandle = makeBridgeContentHandle(
            itemId: "item-2",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("two")
        )
        let thirdHandle = makeBridgeContentHandle(
            itemId: "item-3",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash("tri")
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [
                firstHandle.handleId: makeContentResult(handle: firstHandle, data: "one"),
                secondHandle.handleId: makeContentResult(handle: secondHandle, data: "two"),
                thirdHandle.handleId: makeContentResult(handle: thirdHandle, data: "tri"),
            ]
        )
        let store = BridgeContentStore(provider: provider, contentCacheMaxBytes: 6)
        await store.activate(handles: [firstHandle, secondHandle, thirdHandle], reviewGeneration: 7)

        _ = try await store.load(handleId: firstHandle.handleId, requestedGeneration: 7)
        _ = try await store.load(handleId: secondHandle.handleId, requestedGeneration: 7)
        _ = try await store.load(handleId: firstHandle.handleId, requestedGeneration: 7)
        _ = try await store.load(handleId: thirdHandle.handleId, requestedGeneration: 7)
        _ = try await store.load(handleId: firstHandle.handleId, requestedGeneration: 7)
        _ = try await store.load(handleId: secondHandle.handleId, requestedGeneration: 7)

        #expect(await provider.recordedContentRequestsCount(handleId: firstHandle.handleId) == 1)
        #expect(await provider.recordedContentRequestsCount(handleId: secondHandle.handleId) == 2)
        #expect(await provider.recordedContentRequestsCount(handleId: thirdHandle.handleId) == 1)
    }
}
