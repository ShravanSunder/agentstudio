import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioProcessMemorySamplerTests {
    @Test
    func sampleNowRecordsTypedMallocStatistics() {
        let expectedSnapshot = AgentStudioProcessMemorySnapshot(
            blocksInUse: 7,
            sizeInUseBytes: 11,
            maximumSizeInUseBytes: 13,
            sizeAllocatedBytes: 17
        )
        let recordedSnapshots = LockedMemorySnapshots()
        let sampler = AgentStudioProcessMemorySampler(
            snapshotProvider: { expectedSnapshot },
            waitForNextSample: { false },
            recordSnapshot: { recordedSnapshots.append($0) }
        )

        sampler.sampleNow()

        #expect(recordedSnapshots.values == [expectedSnapshot])
    }

    @Test
    func stoppedSamplerRejectsLaterSamples() async {
        let recordedSnapshots = LockedMemorySnapshots()
        let sampler = AgentStudioProcessMemorySampler(
            snapshotProvider: {
                AgentStudioProcessMemorySnapshot(
                    blocksInUse: 1,
                    sizeInUseBytes: 2,
                    maximumSizeInUseBytes: 3,
                    sizeAllocatedBytes: 4
                )
            },
            waitForNextSample: { false },
            recordSnapshot: { recordedSnapshots.append($0) }
        )

        sampler.sampleNow()
        await sampler.stop()
        sampler.sampleNow()

        #expect(recordedSnapshots.values.count == 1)
    }

    @Test
    func stopCancelsAndJoinsRunningSamplerBeforeReturning() async {
        let expectedSnapshot = AgentStudioProcessMemorySnapshot(
            blocksInUse: 1,
            sizeInUseBytes: 2,
            maximumSizeInUseBytes: 3,
            sizeAllocatedBytes: 4
        )
        let recordedSnapshots = LockedMemorySnapshots()
        let controlledWait = ControlledSampleWait()
        let sampler = AgentStudioProcessMemorySampler(
            snapshotProvider: { expectedSnapshot },
            waitForNextSample: { await controlledWait.wait() },
            recordSnapshot: { recordedSnapshots.append($0) }
        )

        sampler.start()
        await controlledWait.waitUntilEntered()
        await sampler.stop()
        controlledWait.release()

        #expect(recordedSnapshots.values == [expectedSnapshot])
    }

    @Test
    func traceAttributesClampUnsignedValuesToTraceIntegers() {
        let attributes = AgentStudioProcessMemorySnapshot(
            blocksInUse: UInt64.max,
            sizeInUseBytes: UInt64.max,
            maximumSizeInUseBytes: UInt64.max,
            sizeAllocatedBytes: UInt64.max
        ).traceAttributes

        #expect(attributes["agentstudio.performance.process.malloc.blocks_in_use"] == .int(Int.max))
        #expect(attributes["agentstudio.performance.process.malloc.size_in_use_bytes"] == .int(Int.max))
        #expect(attributes["agentstudio.performance.process.malloc.maximum_size_in_use_bytes"] == .int(Int.max))
        #expect(attributes["agentstudio.performance.process.malloc.size_allocated_bytes"] == .int(Int.max))
    }
}

private final class LockedMemorySnapshots: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [AgentStudioProcessMemorySnapshot] = []

    var values: [AgentStudioProcessMemorySnapshot] {
        lock.withLock { storedValues }
    }

    func append(_ snapshot: AgentStudioProcessMemorySnapshot) {
        lock.withLock {
            storedValues.append(snapshot)
        }
    }
}

private final class ControlledSampleWait: @unchecked Sendable {
    private let enteredStream: AsyncStream<Void>
    private let enteredContinuation: AsyncStream<Void>.Continuation
    private let releaseStream: AsyncStream<Void>
    private let releaseContinuation: AsyncStream<Void>.Continuation

    init() {
        (enteredStream, enteredContinuation) = AsyncStream.makeStream(of: Void.self)
        (releaseStream, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func wait() async -> Bool {
        enteredContinuation.yield(())
        return await withTaskCancellationHandler {
            var iterator = releaseStream.makeAsyncIterator()
            return await iterator.next() != nil && !Task.isCancelled
        } onCancel: {
            releaseContinuation.finish()
        }
    }

    func waitUntilEntered() async {
        var iterator = enteredStream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release() {
        releaseContinuation.yield(())
        releaseContinuation.finish()
        enteredContinuation.finish()
    }
}
