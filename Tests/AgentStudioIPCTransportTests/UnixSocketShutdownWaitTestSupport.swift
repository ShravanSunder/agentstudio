import Foundation

final class UnixSocketShutdownWaitController: @unchecked Sendable {
    enum Mode: Sendable {
        case waitForFirstBarrier
        case timeOutFirstAndWaitForSecondBarrier
        case timeOutBothBarriers
    }

    private let firstEntry = DispatchSemaphore(value: 0)
    private let firstEntryOwnsEndpoint: @Sendable () -> Bool
    private let lock = NSLock()
    private let mode: Mode
    private let secondEntry = DispatchSemaphore(value: 0)
    private var storedBarriers: [DispatchSemaphore] = []
    private var storedFirstEntryOwnedEndpoint: Bool?

    init(
        mode: Mode,
        firstEntryOwnsEndpoint: @escaping @Sendable () -> Bool
    ) {
        self.mode = mode
        self.firstEntryOwnsEndpoint = firstEntryOwnsEndpoint
    }

    var firstEntryOwnedEndpoint: Bool? {
        lock.withLock { storedFirstEntryOwnedEndpoint }
    }

    var invocationCount: Int {
        lock.withLock { storedBarriers.count }
    }

    func wait(for barrier: DispatchSemaphore) -> DispatchTimeoutResult {
        let invocation = lock.withLock {
            storedBarriers.append(barrier)
            let invocation = storedBarriers.count
            if invocation == 1 {
                storedFirstEntryOwnedEndpoint = firstEntryOwnsEndpoint()
            }
            return invocation
        }

        switch (mode, invocation) {
        case (.waitForFirstBarrier, 1):
            firstEntry.signal()
            barrier.wait()
            return .success
        case (.timeOutFirstAndWaitForSecondBarrier, 1), (.timeOutBothBarriers, 1):
            firstEntry.signal()
            return .timedOut
        case (.timeOutFirstAndWaitForSecondBarrier, 2):
            secondEntry.signal()
            barrier.wait()
            return .success
        case (.timeOutBothBarriers, 2):
            secondEntry.signal()
            return .timedOut
        default:
            // Repeated stop and deinit are not part of the selected phase.
            // If they ever do enqueue another real barrier, drain it normally.
            barrier.wait()
            return .success
        }
    }

    func waitUntilFirstEntry() async -> DispatchTimeoutResult {
        await waitOnDedicatedThread(firstEntry)
    }

    func waitUntilSecondEntry() async -> DispatchTimeoutResult {
        await waitOnDedicatedThread(secondEntry)
    }

    func drainBarrier(at index: Int) async -> DispatchTimeoutResult? {
        let barrier = lock.withLock {
            storedBarriers.indices.contains(index) ? storedBarriers[index] : nil
        }
        guard let barrier else { return nil }
        return await waitOnDedicatedThread(barrier)
    }

    private func waitOnDedicatedThread(
        _ semaphore: DispatchSemaphore
    ) async -> DispatchTimeoutResult {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(
                    returning: semaphore.wait(timeout: .now() + .seconds(120))
                )
            }
        }
    }
}
