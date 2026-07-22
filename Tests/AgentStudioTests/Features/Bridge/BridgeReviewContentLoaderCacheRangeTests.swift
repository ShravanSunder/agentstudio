import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge Review content loader cache ranges")
struct BridgeReviewContentLoaderCacheRangeTests {
    @Test("disjoint ranges share one validated whole-content provider load")
    func disjointRangesShareValidatedWholeContent() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let content = "0123456789"
        let handle = makeRangeHandle(content: content)
        let provider = makeRangeProvider(handle: handle, content: content)
        let cache = BridgeReviewContentLoaderCache(provider: provider)

        let first = try await cache.loadRangeObserved(
            handle: handle,
            startByte: 0,
            maximumBytes: 4,
            productAdmission: admission.context
        )
        let second = try await cache.loadRangeObserved(
            handle: handle,
            startByte: 4,
            maximumBytes: 3,
            productAdmission: admission.context
        )

        #expect(first.bytes == Data("0123".utf8))
        #expect(first.observation.cacheResult == .providerLoad)
        #expect(second.bytes == Data("456".utf8))
        #expect(second.observation.cacheResult == .cacheHit)
        #expect(await provider.recordedContentRequestsCount() == 1)
    }

    @Test("ranges preserve exact raw half-open bytes")
    func rangesPreserveExactRawHalfOpenBytes() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let content = "aé\nb"
        let handle = makeRangeHandle(content: content)
        let cache = BridgeReviewContentLoaderCache(
            provider: makeRangeProvider(handle: handle, content: content)
        )

        let range = try await cache.loadRangeObserved(
            handle: handle,
            startByte: 2,
            maximumBytes: 2,
            productAdmission: admission.context
        )

        let expectedBytes = Data([0xa9, 0x0a])
        #expect(range.bytes == expectedBytes)
        #expect(range.startByte == 2)
        #expect(range.wholeByteLength == 5)
        #expect(range.sha256 == rangeSHA256(expectedBytes))
        #expect(!range.isFinalRange)
        #expect(range.handle == handle)
    }

    @Test("range finality includes truncated and empty terminal ranges")
    func rangeFinalityIncludesTruncatedAndEmptyTerminalRanges() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let content = "abcdef"
        let handle = makeRangeHandle(content: content)
        let cache = BridgeReviewContentLoaderCache(
            provider: makeRangeProvider(handle: handle, content: content)
        )

        let middle = try await cache.loadRangeObserved(
            handle: handle,
            startByte: 1,
            maximumBytes: 2,
            productAdmission: admission.context
        )
        let truncatedFinal = try await cache.loadRangeObserved(
            handle: handle,
            startByte: 3,
            maximumBytes: 10,
            productAdmission: admission.context
        )
        let emptyFinal = try await cache.loadRangeObserved(
            handle: handle,
            startByte: 6,
            maximumBytes: 3,
            productAdmission: admission.context
        )

        #expect(middle.bytes == Data("bc".utf8))
        #expect(!middle.isFinalRange)
        #expect(truncatedFinal.bytes == Data("def".utf8))
        #expect(truncatedFinal.isFinalRange)
        #expect(emptyFinal.bytes.isEmpty)
        #expect(emptyFinal.sha256 == rangeSHA256(Data()))
        #expect(emptyFinal.isFinalRange)
    }

    @Test("range bounds reject invalid offsets lengths overflow and beyond-content starts")
    func rangeBoundsRejectInvalidInputs() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let content = "abc"
        let handle = makeRangeHandle(content: content)
        let cache = BridgeReviewContentLoaderCache(
            provider: makeRangeProvider(handle: handle, content: content)
        )

        await expectRangeError(.invalidStartByte(-1)) {
            try await cache.loadRangeObserved(
                handle: handle,
                startByte: -1,
                maximumBytes: 1,
                productAdmission: admission.context
            )
        }
        await expectRangeError(.invalidMaximumBytes(0)) {
            try await cache.loadRangeObserved(
                handle: handle,
                startByte: 0,
                maximumBytes: 0,
                productAdmission: admission.context
            )
        }
        await expectRangeError(.rangeOverflow(startByte: Int.max, maximumBytes: 1)) {
            try await cache.loadRangeObserved(
                handle: handle,
                startByte: Int.max,
                maximumBytes: 1,
                productAdmission: admission.context
            )
        }
        await expectRangeError(.startByteBeyondContent(startByte: 4, wholeByteLength: 3)) {
            try await cache.loadRangeObserved(
                handle: handle,
                startByte: 4,
                maximumBytes: 1,
                productAdmission: admission.context
            )
        }
    }

    @Test("cancelling one coalesced range waiter preserves shared provider work")
    func cancellingOneRangeWaiterPreservesSharedProviderWork() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let content = "coalesced-range"
        let handle = makeRangeHandle(content: content)
        let gate = BridgeContentLoadGate()
        let provider = makeRangeProvider(
            handle: handle,
            content: content,
            gate: gate,
            checksCancellationAfterGate: true
        )
        let cache = BridgeReviewContentLoaderCache(provider: provider)

        let survivingWaiter = Task {
            try await cache.loadRangeObserved(
                handle: handle,
                startByte: 0,
                maximumBytes: 4,
                productAdmission: admission.context
            )
        }
        await gate.waitForStartedLoadCount(1)
        let cancelledWaiter = Task {
            try await cache.loadRangeObserved(
                handle: handle,
                startByte: 4,
                maximumBytes: 4,
                productAdmission: admission.context
            )
        }
        await Task.yield()

        cancelledWaiter.cancel()
        await Task.yield()
        await gate.releaseAll()

        let survivingRange = try await survivingWaiter.value
        #expect(survivingRange.bytes == Data("coal".utf8))
        await expectRangeLoadCancellation(cancelledWaiter)
        #expect(await provider.recordedContentRequestsCount() == 1)
        #expect(await provider.recordedObservedCancellationCount() == 0)
        #expect((await cache.diagnosticSnapshot).inFlightLoadCount == 0)
    }

    @Test("shared provider work cancels after the final range waiter leaves")
    func sharedProviderWorkCancelsAfterFinalRangeWaiterLeaves() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let content = "cancel-final-range"
        let handle = makeRangeHandle(content: content)
        let gate = BridgeContentLoadGate()
        let provider = makeRangeProvider(
            handle: handle,
            content: content,
            gate: gate,
            checksCancellationAfterGate: true
        )
        let cache = BridgeReviewContentLoaderCache(provider: provider)
        let waiter = Task {
            try await cache.loadRangeObserved(
                handle: handle,
                startByte: 0,
                maximumBytes: 4,
                productAdmission: admission.context
            )
        }
        await gate.waitForStartedLoadCount(1)

        waiter.cancel()
        await Task.yield()
        await expectRangeLoadCancellation(waiter)

        await gate.releaseAll()
        await provider.waitForFinishedContentLoadCount(1)
        #expect(await provider.recordedContentRequestsCount() == 1)
        #expect(await provider.recordedObservedCancellationCount() == 1)
        #expect((await cache.diagnosticSnapshot).inFlightLoadCount == 0)
    }

    @Test("closing admission during a range load prevents late range publication")
    func admissionClosePreventsLateRangePublication() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let content = "late-range"
        let handle = makeRangeHandle(content: content)
        let gate = BridgeContentLoadGate()
        let cache = BridgeReviewContentLoaderCache(
            provider: makeRangeProvider(handle: handle, content: content, gate: gate)
        )
        let load = Task {
            try await cache.loadRangeObserved(
                handle: handle,
                startByte: 0,
                maximumBytes: 4,
                productAdmission: admission.context
            )
        }
        await gate.waitForStartedLoadCount(1)

        admission.close()
        await gate.releaseAll()

        await #expect(throws: BridgeContentLoadObservedFailure.self) {
            _ = try await load.value
        }
        #expect((await cache.diagnosticSnapshot).cachedContentCount == 0)
    }
}

private func makeRangeHandle(content: String) -> BridgeContentHandle {
    makeBridgeContentHandle(
        itemId: "range-item",
        role: .head,
        reviewGeneration: 7,
        contentHash: bridgeSHA256ContentHash(content),
        sizeBytes: content.utf8.count
    )
}

private func makeRangeProvider(
    handle: BridgeContentHandle,
    content: String,
    gate: BridgeContentLoadGate? = nil,
    checksCancellationAfterGate: Bool = false
) -> BridgeReviewSourceProviderFake {
    BridgeReviewSourceProviderFake(
        comparison: BridgeEndpointComparison(
            baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
            headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
            changedFiles: []
        ),
        contentByHandleId: [
            handle.handleId: makeContentResult(handle: handle, data: content)
        ],
        contentLoadGate: gate,
        checksCancellationAfterGate: checksCancellationAfterGate
    )
}

private func expectRangeLoadCancellation(
    _ task: Task<BridgeContentRangeObservedResult, any Error>
) async {
    do {
        _ = try await task.value
        Issue.record("Expected cancelled range load")
    } catch let failure as BridgeContentLoadObservedFailure {
        #expect(failure.underlyingError is CancellationError)
    } catch is CancellationError {
        // Cancellation before an in-flight observation exists is a valid caller outcome.
    } catch {
        Issue.record("Expected cancellation, got \(error)")
    }
}

private func expectRangeError(
    _ expected: BridgeContentRangeError,
    operation: () async throws -> BridgeContentRangeObservedResult
) async {
    do {
        _ = try await operation()
        Issue.record("Expected range error \(expected)")
    } catch let error as BridgeContentRangeError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected BridgeContentRangeError, got \(error)")
    }
}

private func rangeSHA256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
