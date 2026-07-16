import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge content store ranges")
struct BridgeContentStoreRangeTests {
    @Test("disjoint ranges share one validated provider load")
    func disjointRangesShareValidatedWholeContent() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let content = "0123456789"
        let handle = makeBridgeContentHandle(
            itemId: "item-range-cache",
            role: .head,
            contentHash: bridgeSHA256ContentHash(content),
            sizeBytes: content.utf8.count
        )
        let provider = makeRangeProvider(handle: handle, content: content)
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7, productAdmission: productAdmission.context)

        let firstRange = try await store.loadRangeObserved(
            handleId: handle.handleId,
            requestedGeneration: 7,
            startByte: 0,
            maximumBytes: 4,
            productAdmission: productAdmission.context
        )
        let secondRange = try await store.loadRangeObserved(
            handleId: handle.handleId,
            requestedGeneration: 7,
            startByte: 4,
            maximumBytes: 3,
            productAdmission: productAdmission.context
        )

        #expect(firstRange.bytes == Data("0123".utf8))
        #expect(firstRange.observation.cacheResult == .providerLoad)
        #expect(secondRange.bytes == Data("456".utf8))
        #expect(secondRange.observation.cacheResult == .cacheHit)
        #expect(await provider.recordedContentRequestsCount() == 1)
    }

    @Test("ranges preserve exact raw half-open bytes without text-boundary adjustment")
    func rangesPreserveExactRawHalfOpenBytes() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let content = "aé\nb"
        let handle = makeBridgeContentHandle(
            itemId: "item-raw-range",
            role: .head,
            contentHash: bridgeSHA256ContentHash(content),
            sizeBytes: content.utf8.count
        )
        let provider = makeRangeProvider(handle: handle, content: content)
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7, productAdmission: productAdmission.context)

        let range = try await store.loadRangeObserved(
            handleId: handle.handleId,
            requestedGeneration: 7,
            startByte: 2,
            maximumBytes: 2,
            productAdmission: productAdmission.context
        )

        let expectedBytes = Data([0xa9, 0x0a])
        #expect(range.bytes == expectedBytes)
        #expect(range.startByte == 2)
        #expect(range.wholeByteLength == 5)
        #expect(range.sha256 == rawSHA256(expectedBytes))
        #expect(range.isFinalRange == false)
        #expect(range.handle == handle)
    }

    @Test("range finality includes truncated and empty terminal ranges")
    func rangeFinalityIncludesTruncatedAndEmptyTerminalRanges() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let content = "abcdef"
        let handle = makeBridgeContentHandle(
            itemId: "item-range-finality",
            role: .head,
            contentHash: bridgeSHA256ContentHash(content),
            sizeBytes: content.utf8.count
        )
        let provider = makeRangeProvider(handle: handle, content: content)
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7, productAdmission: productAdmission.context)

        let middleRange = try await store.loadRangeObserved(
            handleId: handle.handleId,
            requestedGeneration: 7,
            startByte: 1,
            maximumBytes: 2,
            productAdmission: productAdmission.context
        )
        let truncatedFinalRange = try await store.loadRangeObserved(
            handleId: handle.handleId,
            requestedGeneration: 7,
            startByte: 3,
            maximumBytes: 10,
            productAdmission: productAdmission.context
        )
        let emptyFinalRange = try await store.loadRangeObserved(
            handleId: handle.handleId,
            requestedGeneration: 7,
            startByte: 6,
            maximumBytes: 3,
            productAdmission: productAdmission.context
        )

        #expect(middleRange.bytes == Data("bc".utf8))
        #expect(middleRange.isFinalRange == false)
        #expect(truncatedFinalRange.bytes == Data("def".utf8))
        #expect(truncatedFinalRange.isFinalRange == true)
        #expect(emptyFinalRange.bytes.isEmpty)
        #expect(emptyFinalRange.sha256 == rawSHA256(Data()))
        #expect(emptyFinalRange.isFinalRange == true)
    }

    @Test("range bounds reject invalid offsets lengths and overflow")
    func rangeBoundsRejectInvalidInputs() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let content = "abc"
        let handle = makeBridgeContentHandle(
            itemId: "item-range-bounds",
            role: .head,
            contentHash: bridgeSHA256ContentHash(content),
            sizeBytes: content.utf8.count
        )
        let provider = makeRangeProvider(handle: handle, content: content)
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7, productAdmission: productAdmission.context)

        await expectRangeError(.invalidStartByte(-1)) {
            try await store.loadRangeObserved(
                handleId: handle.handleId,
                requestedGeneration: 7,
                startByte: -1,
                maximumBytes: 1,
                productAdmission: productAdmission.context
            )
        }
        await expectRangeError(.invalidMaximumBytes(0)) {
            try await store.loadRangeObserved(
                handleId: handle.handleId,
                requestedGeneration: 7,
                startByte: 0,
                maximumBytes: 0,
                productAdmission: productAdmission.context
            )
        }
        await expectRangeError(.rangeOverflow(startByte: Int.max, maximumBytes: 1)) {
            try await store.loadRangeObserved(
                handleId: handle.handleId,
                requestedGeneration: 7,
                startByte: Int.max,
                maximumBytes: 1,
                productAdmission: productAdmission.context
            )
        }
        await expectRangeError(.startByteBeyondContent(startByte: 4, wholeByteLength: 3)) {
            try await store.loadRangeObserved(
                handleId: handle.handleId,
                requestedGeneration: 7,
                startByte: 4,
                maximumBytes: 1,
                productAdmission: productAdmission.context
            )
        }
    }

    @Test("cancelling one coalesced range waiter preserves shared provider work")
    func cancellingOneRangeWaiterPreservesSharedProviderWork() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let content = "coalesced-range"
        let handle = makeBridgeContentHandle(
            itemId: "item-range-cancel-one",
            role: .head,
            contentHash: bridgeSHA256ContentHash(content),
            sizeBytes: content.utf8.count
        )
        let loadGate = BridgeContentLoadGate()
        let provider = makeRangeProvider(
            handle: handle,
            content: content,
            contentLoadGate: loadGate,
            checksCancellationAfterGate: true
        )
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7, productAdmission: productAdmission.context)

        let survivingWaiter = Task {
            try await store.loadRangeObserved(
                handleId: handle.handleId,
                requestedGeneration: 7,
                startByte: 0,
                maximumBytes: 4,
                productAdmission: productAdmission.context
            )
        }
        await loadGate.waitForStartedLoadCount(1)
        let cancelledWaiter = Task {
            try await store.loadRangeObserved(
                handleId: handle.handleId,
                requestedGeneration: 7,
                startByte: 4,
                maximumBytes: 4,
                productAdmission: productAdmission.context
            )
        }
        await Task.yield()
        cancelledWaiter.cancel()
        await Task.yield()
        await loadGate.releaseAll()

        let survivingRange = try await survivingWaiter.value
        #expect(survivingRange.bytes == Data("coal".utf8))
        await expectObservedCancellation(cancelledWaiter)
        #expect(await provider.recordedContentRequestsCount() == 1)
        #expect(await provider.recordedObservedCancellationCount() == 0)
    }

    @Test("shared provider work cancels after the final range waiter leaves")
    func sharedProviderWorkCancelsAfterFinalRangeWaiterLeaves() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let content = "cancel-final-range"
        let handle = makeBridgeContentHandle(
            itemId: "item-range-cancel-final",
            role: .head,
            contentHash: bridgeSHA256ContentHash(content),
            sizeBytes: content.utf8.count
        )
        let loadGate = BridgeContentLoadGate()
        let provider = makeRangeProvider(
            handle: handle,
            content: content,
            contentLoadGate: loadGate,
            checksCancellationAfterGate: true
        )
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [handle], reviewGeneration: 7, productAdmission: productAdmission.context)

        let waiter = Task {
            try await store.loadRangeObserved(
                handleId: handle.handleId,
                requestedGeneration: 7,
                startByte: 0,
                maximumBytes: 4,
                productAdmission: productAdmission.context
            )
        }
        await loadGate.waitForStartedLoadCount(1)
        waiter.cancel()
        await Task.yield()
        await loadGate.releaseAll()

        await expectObservedCancellation(waiter)
        await provider.waitForFinishedContentLoadCount(1)
        #expect(await provider.recordedContentRequestsCount() == 1)
        #expect(await provider.recordedObservedCancellationCount() == 1)
    }

    @Test("range loads reject stale and deactivated content authority")
    func rangeLoadsRejectStaleAndDeactivatedAuthority() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let oldContent = "old"
        let oldHandle = makeBridgeContentHandle(
            itemId: "item-range-authority",
            role: .head,
            reviewGeneration: 7,
            contentHash: bridgeSHA256ContentHash(oldContent),
            sizeBytes: oldContent.utf8.count
        )
        let newHandle = makeBridgeContentHandle(
            itemId: "item-range-authority",
            role: .head,
            reviewGeneration: 8
        )
        let provider = makeRangeProvider(handle: oldHandle, content: oldContent)
        let store = BridgeContentStore(provider: provider)
        await store.activate(handles: [oldHandle], reviewGeneration: 7, productAdmission: productAdmission.context)
        _ = try await store.loadRangeObserved(
            handleId: oldHandle.handleId,
            requestedGeneration: 7,
            startByte: 0,
            maximumBytes: 1,
            productAdmission: productAdmission.context
        )

        await store.activate(handles: [newHandle], reviewGeneration: 8, productAdmission: productAdmission.context)
        await expectObservedProviderFailure(
            .staleReviewGeneration(storedGeneration: 8, requestedGeneration: 7)
        ) {
            try await store.loadRangeObserved(
                handleId: oldHandle.handleId,
                requestedGeneration: 7,
                startByte: 0,
                maximumBytes: 1,
                productAdmission: productAdmission.context
            )
        }

        await store.deactivate()
        await expectObservedProviderFailure(.missingContent(handleId: newHandle.handleId)) {
            try await store.loadRangeObserved(
                handleId: newHandle.handleId,
                requestedGeneration: 8,
                startByte: 0,
                maximumBytes: 1,
                productAdmission: productAdmission.context
            )
        }
    }

    @Test("closing admission during a provider range load prevents cache and range publication")
    func closeDuringProviderRangeLoadPreventsCacheAndRangePublication() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let content = "retired-range"
        let handle = makeBridgeContentHandle(
            itemId: "item-range-retired-admission",
            role: .head,
            contentHash: bridgeSHA256ContentHash(content),
            sizeBytes: content.utf8.count
        )
        let loadGate = BridgeContentLoadGate()
        let provider = makeRangeProvider(
            handle: handle,
            content: content,
            contentLoadGate: loadGate
        )
        let store = BridgeContentStore(provider: provider)
        #expect(
            await store.activate(
                handles: [handle],
                reviewGeneration: 7,
                productAdmission: productAdmission.context
            )
        )

        // Act
        let rangeLoad = Task {
            try await store.loadRangeObserved(
                handleId: handle.handleId,
                requestedGeneration: 7,
                startByte: 0,
                maximumBytes: 4,
                productAdmission: productAdmission.context
            )
        }
        await loadGate.waitForStartedLoadCount(1)
        productAdmission.close()
        await loadGate.releaseAll()

        // Assert
        do {
            _ = try await rangeLoad.value
            Issue.record("Expected retired product admission to reject the range")
        } catch let failure as BridgeContentLoadObservedFailure {
            #expect(
                failure.underlyingError as? BridgeContentStoreError
                    == .productAdmissionRejected
            )
        } catch {
            Issue.record("Expected BridgeContentLoadObservedFailure, got \(error)")
        }
        #expect(
            await store.diagnosticSnapshot
                == .init(
                    activeHandleCount: 1,
                    cachedContentCount: 0,
                    inFlightLoadCount: 0,
                    totalCachedBytes: 0
                )
        )
        await store.deactivate()
        #expect(
            await store.diagnosticSnapshot
                == .init(
                    activeHandleCount: 0,
                    cachedContentCount: 0,
                    inFlightLoadCount: 0,
                    totalCachedBytes: 0
                )
        )
    }
}

private func makeRangeProvider(
    handle: BridgeContentHandle,
    content: String,
    contentLoadGate: BridgeContentLoadGate? = nil,
    checksCancellationAfterGate: Bool = false
) -> BridgeReviewSourceProviderFake {
    BridgeReviewSourceProviderFake(
        comparison: BridgeEndpointComparison(
            baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
            headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
            changedFiles: []
        ),
        contentByHandleId: [handle.handleId: makeContentResult(handle: handle, data: content)],
        contentLoadGate: contentLoadGate,
        checksCancellationAfterGate: checksCancellationAfterGate
    )
}

private func rawSHA256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func expectRangeError(
    _ expectedError: BridgeContentRangeError,
    operation: () async throws -> BridgeContentRangeObservedResult
) async {
    do {
        _ = try await operation()
        Issue.record("Expected range error \(expectedError)")
    } catch let error as BridgeContentRangeError {
        #expect(error == expectedError)
    } catch {
        Issue.record("Expected BridgeContentRangeError, got \(error)")
    }
}

private func expectObservedCancellation(_ task: Task<BridgeContentRangeObservedResult, any Error>) async {
    do {
        _ = try await task.value
        Issue.record("Expected cancelled range load")
    } catch let failure as BridgeContentLoadObservedFailure {
        #expect(failure.underlyingError is CancellationError)
    } catch is CancellationError {
        // Cancellation before an in-flight observation exists is still a valid caller outcome.
    } catch {
        Issue.record("Expected cancellation, got \(error)")
    }
}

private func expectObservedProviderFailure(
    _ expectedFailure: BridgeProviderFailure,
    operation: () async throws -> BridgeContentRangeObservedResult
) async {
    do {
        _ = try await operation()
        Issue.record("Expected provider failure \(expectedFailure)")
    } catch let failure as BridgeContentLoadObservedFailure {
        #expect(failure.underlyingError as? BridgeProviderFailure == expectedFailure)
    } catch {
        Issue.record("Expected BridgeContentLoadObservedFailure, got \(error)")
    }
}
