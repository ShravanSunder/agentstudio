import AgentStudioCore
import AgentStudioTestHarness

/// A Core-aware adapter from one bus subscription to the generic fact recorder.
package enum EventBusFactSource {
    package static func attach<Envelope: Sendable, Scope: Hashable & Sendable, Fact: Sendable>(
        subscription: EventBusSubscription<Envelope>,
        vocabulary: FactVocabulary<Scope, Fact>,
        replayWasTruncated: @Sendable () -> Bool,
        classify: @escaping @Sendable (Envelope) -> (Scope, Fact)?
    ) -> FactRecorder<Scope, Fact> {
        // The test target has awaited subscribe and classified replay before
        // handing this ready subscription to the Core-free recorder adapter.
        let recorder = FactRecorder(vocabulary: vocabulary)
        let progress = BusFactCollectorProgress()
        if replayWasTruncated() {
            recorder.receive(.lost(description: "EventBus replay was possibly truncated"))
        }
        if subscription.deliveryCheckpoint().droppedCount > 0 {
            recorder.receive(.lost(description: "EventBus replay dropped facts"))
        }

        // The collector must not inherit a MainActor test caller's executor.
        // swiftlint:disable:next no_task_detached
        let collector = Task.detached {
            var deliveredSequence: UInt64 = 0
            for await envelope in subscription {
                if subscription.deliveryCheckpoint().droppedCount > 0 {
                    recorder.receive(.lost(description: "EventBus delivery dropped facts"))
                }
                deliveredSequence += 1
                if let (scope, fact) = classify(envelope) {
                    recorder.receive(.fact(scope: scope, fact: fact, sequence: deliveredSequence))
                }
                await progress.recordProcessed()
            }
            if subscription.deliveryCheckpoint().droppedCount > 0 {
                recorder.receive(.lost(description: "EventBus delivery dropped facts"))
            }
            recorder.receive(Task.isCancelled ? .cancelled : .ended)
            await progress.stop()
        }
        recorder.installSourceHandle(
            BusFactSourceHandle(
                subscription: subscription, recorder: recorder, progress: progress, collector: collector)
        )
        return recorder
    }
}

private final class BusFactSourceHandle<Envelope: Sendable, Scope: Hashable & Sendable, Fact: Sendable>:
    FactSourceHandle, Sendable
{
    private let subscription: EventBusSubscription<Envelope>
    private let recorder: FactRecorder<Scope, Fact>
    private let progress: BusFactCollectorProgress
    private let collector: Task<Void, Never>

    init(
        subscription: EventBusSubscription<Envelope>,
        recorder: FactRecorder<Scope, Fact>,
        progress: BusFactCollectorProgress,
        collector: Task<Void, Never>
    ) {
        self.subscription = subscription
        self.recorder = recorder
        self.progress = progress
        self.collector = collector
    }

    func settleEnqueued() async {
        let boundary = subscription.deliveryCheckpoint()
        if boundary.droppedCount > 0 {
            recorder.receive(.lost(description: "EventBus delivery dropped facts"))
        }
        let processedCount = await progress.waitUntilProcessed(boundary.enqueuedCount)
        if processedCount < boundary.enqueuedCount {
            recorder.receive(.cancelled)
        }
        if subscription.deliveryCheckpoint().droppedCount > 0 {
            recorder.receive(.lost(description: "EventBus delivery dropped facts"))
        }
    }

    func stop() async {
        collector.cancel()
        await collector.value
        if subscription.deliveryCheckpoint().droppedCount > 0 {
            recorder.receive(.lost(description: "EventBus delivery dropped facts"))
        }
        await progress.stop()
    }
}

/// Counts consumed envelopes, including ones the classifier ignores. Each
/// waiter has a finite checkpoint target; stop also releases every waiter.
private actor BusFactCollectorProgress {
    private struct Waiter {
        let target: UInt64
        let continuation: CheckedContinuation<UInt64, Never>
    }

    private var processedCount: UInt64 = 0
    private var stopped = false
    private var waiters: [Waiter] = []

    func recordProcessed() {
        processedCount += 1
        let ready = waiters.filter { processedCount >= $0.target }
        waiters.removeAll { processedCount >= $0.target }
        for waiter in ready { waiter.continuation.resume(returning: processedCount) }
    }

    func waitUntilProcessed(_ target: UInt64) async -> UInt64 {
        guard !stopped, processedCount < target else { return processedCount }
        return await withCheckedContinuation { continuation in
            if stopped || processedCount >= target {
                continuation.resume(returning: processedCount)
            } else {
                waiters.append(Waiter(target: target, continuation: continuation))
            }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.continuation.resume(returning: processedCount) }
    }
}
