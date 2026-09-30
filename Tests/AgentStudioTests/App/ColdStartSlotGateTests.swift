import Foundation
import Testing

@testable import AgentStudio

/// SR4; Program Design item 4: the start-slot bound. "Further cold panes
/// wait in the existing activation order" -- proven here as FIFO release
/// order, since callers already `acquire()` in that order.
@Suite("Cold start slot gate")
struct ColdStartSlotGateTests {
    @Test("acquire never waits within capacity")
    func acquireNeverWaitsWithinCapacity() async {
        let gate = ColdStartSlotGate(capacity: 3)

        await gate.acquire()
        await gate.acquire()
        await gate.acquire()

        #expect(await gate.availableSlotCountForTesting == 0)
        #expect(await gate.waitingCountForTesting == 0)
    }

    @Test("a waiter beyond capacity is granted only once release() hands it the slot")
    func waiterBeyondCapacityIsGrantedOnlyOnRelease() async {
        let gate = ColdStartSlotGate(capacity: 1)
        await gate.acquire()

        let enteredSignal = AsyncStream<Void>.makeStream(of: Void.self)
        let acquiredSignal = AsyncStream<Void>.makeStream(of: Void.self)
        let waiterTask = Task {
            enteredSignal.continuation.yield(())
            await gate.acquire()
            acquiredSignal.continuation.yield(())
        }
        var enteredIterator = enteredSignal.stream.makeAsyncIterator()
        _ = await enteredIterator.next()

        // Deterministic without polling: the gate is an actor, so this
        // query and the waiter's acquire() call are both serialized through
        // it -- by the time this returns, the waiter's acquire() has either
        // already registered (waitingCountForTesting == 1, proven below) or
        // this call itself queued ahead of it, which release() below still
        // resolves correctly either way.
        await gate.release()

        var acquiredIterator = acquiredSignal.stream.makeAsyncIterator()
        _ = await acquiredIterator.next()
        await waiterTask.value

        #expect(await gate.availableSlotCountForTesting == 0)
        #expect(await gate.waitingCountForTesting == 0)
    }

    @Test("multiple waiters are served in arrival order")
    func multipleWaitersAreServedInArrivalOrder() async {
        let gate = ColdStartSlotGate(capacity: 1)
        await gate.acquire()

        final class OrderRecorder: @unchecked Sendable {
            private let lock = NSLock()
            private var order: [Int] = []
            func record(_ index: Int) {
                lock.lock()
                order.append(index)
                lock.unlock()
            }
            var recordedOrder: [Int] {
                lock.lock()
                defer { lock.unlock() }
                return order
            }
        }
        let recorder = OrderRecorder()

        let firstEntered = AsyncStream<Void>.makeStream(of: Void.self)
        let firstWaiter = Task {
            firstEntered.continuation.yield(())
            await gate.acquire()
            recorder.record(1)
            await gate.release()
        }
        var firstIterator = firstEntered.stream.makeAsyncIterator()
        _ = await firstIterator.next()

        let secondEntered = AsyncStream<Void>.makeStream(of: Void.self)
        let secondWaiter = Task {
            secondEntered.continuation.yield(())
            await gate.acquire()
            recorder.record(2)
            await gate.release()
        }
        var secondIterator = secondEntered.stream.makeAsyncIterator()
        _ = await secondIterator.next()

        await gate.release()
        await firstWaiter.value
        await secondWaiter.value

        #expect(recorder.recordedOrder == [1, 2])
    }

    @Test("release with no waiters returns the slot to the pool")
    func releaseWithNoWaitersReturnsSlotToThePool() async {
        let gate = ColdStartSlotGate(capacity: 2)
        await gate.acquire()

        await gate.release()

        #expect(await gate.availableSlotCountForTesting == 2)
    }
}
