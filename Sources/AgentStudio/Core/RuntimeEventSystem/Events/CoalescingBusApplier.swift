import Foundation

/// Coalesces high-volume bus facts off the main actor, then applies one keyed batch on MainActor.
final class CoalescingBusApplier<Key: Hashable & Sendable, Pending: Sendable, Envelope: Sendable>:
    @unchecked Sendable
{
    typealias PendingBatch = [Key: Pending]
    typealias Accumulate = @Sendable (inout PendingBatch, Envelope) -> Void
    typealias Apply = @MainActor @Sendable (PendingBatch) async -> Void

    private struct State: Sendable {
        var pendingBatch: PendingBatch = [:]
        var isFlushScheduled = false
        var isClosed = false
    }

    private let lock = NSLock()
    private var state = State()
    private let flushInterval: Duration
    private let delay: AsyncDelay
    private let accumulateEnvelope: Accumulate
    private let applyBatch: Apply
    private let flushStream: AsyncStream<Void>
    private let flushContinuation: AsyncStream<Void>.Continuation

    init(
        flushInterval: Duration,
        delay: AsyncDelay = .taskSleep,
        accumulate: @escaping Accumulate,
        apply: @escaping Apply
    ) {
        self.flushInterval = flushInterval
        self.delay = delay
        self.accumulateEnvelope = accumulate
        self.applyBatch = apply
        let (flushStream, flushContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.flushStream = flushStream
        self.flushContinuation = flushContinuation
    }

    deinit {
        flushContinuation.finish()
    }

    func accumulate(_ envelope: Envelope) {
        var shouldScheduleFlush = false
        lock.lock()
        if !state.isClosed {
            let wasEmpty = state.pendingBatch.isEmpty
            accumulateEnvelope(&state.pendingBatch, envelope)
            if wasEmpty == false || !state.pendingBatch.isEmpty {
                shouldScheduleFlush = !state.isFlushScheduled
                state.isFlushScheduled = true
            }
        }
        lock.unlock()

        if shouldScheduleFlush {
            flushContinuation.yield(())
        }
    }

    func run(_ stream: AsyncStream<Envelope>) async {
        let flushTask = startFlushTask()
        for await envelope in stream {
            if Task.isCancelled { break }
            accumulate(envelope)
        }
        await finish(flushTask: flushTask)
    }

    func run(_ subscription: EventBusSubscription<Envelope>) async {
        let flushTask = startFlushTask()
        for await envelope in subscription {
            if Task.isCancelled { break }
            accumulate(envelope)
        }
        await finish(flushTask: flushTask)
    }

    func startFlushTask() -> Task<Void, Never> {
        Task { await runFlushLoop() }
    }

    func flushPending() async {
        guard let batch = takePendingBatch() else { return }
        await applyBatch(batch)
    }

    func finish() async {
        markClosed()
        flushContinuation.finish()
        await flushPending()
    }

    func finish(flushTask: Task<Void, Never>) async {
        markClosed()
        flushContinuation.finish()
        flushTask.cancel()
        await flushTask.value
        await flushPending()
    }

    private func runFlushLoop() async {
        for await _ in flushStream {
            if Task.isCancelled { break }
            if flushInterval > .zero {
                do {
                    try await delay.wait(flushInterval)
                } catch is CancellationError {
                    break
                } catch {
                    continue
                }
            } else {
                await Task.yield()
            }
            if Task.isCancelled { break }
            await flushPending()
        }
    }

    private func takePendingBatch() -> PendingBatch? {
        lock.lock()
        defer { lock.unlock() }
        guard !state.pendingBatch.isEmpty else {
            state.isFlushScheduled = false
            return nil
        }
        let batch = state.pendingBatch
        state.pendingBatch.removeAll(keepingCapacity: true)
        state.isFlushScheduled = false
        return batch
    }

    private func markClosed() {
        lock.lock()
        state.isClosed = true
        lock.unlock()
    }
}
