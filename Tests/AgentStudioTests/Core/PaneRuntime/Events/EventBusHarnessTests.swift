import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("EventBusHarness")
struct EventBusHarnessTests {
    @MainActor
    private final class MainActorCallCounter {
        private(set) var callCount = 0

        func incrementAndCheck(threshold: Int) -> Bool {
            callCount += 1
            return callCount >= threshold
        }
    }

    private actor CallCounter {
        private(set) var callCount = 0

        func incrementAndCheck(threshold: Int) -> Bool {
            callCount += 1
            return callCount >= threshold
        }
    }

    @Test("one post fan-outs to multiple recording subscribers")
    func onePostFanOutsToMultipleSubscribers() async {
        let harness = EventBusHarness<Int>()
        let subscriberA = await harness.makeSubscriber()
        let subscriberB = await harness.makeSubscriber()

        _ = await harness.post(42)

        await assertEventuallyAsync("subscriber A should receive one event") {
            await subscriberA.snapshot() == [42]
        }
        await assertEventuallyAsync("subscriber B should receive one event") {
            await subscriberB.snapshot() == [42]
        }

        await subscriberA.shutdown()
        await subscriberB.shutdown()
        await assertBusDrained(harness.bus)
    }

    @Test("recording subscriber preserves event order")
    func recordingSubscriberPreservesOrder() async {
        let harness = EventBusHarness<String>()
        let subscriber = await harness.makeSubscriber()

        _ = await harness.postAll(["a", "b", "c"])

        await assertEventuallyAsync("subscriber should receive all events in order") {
            await subscriber.snapshot() == ["a", "b", "c"]
        }

        await subscriber.shutdown()
        await assertBusDrained(harness.bus)
    }

    @Test("subscriber count helper observes registration")
    func subscriberCountHelperObservesRegistration() async {
        let harness = EventBusHarness<Int>()
        let subscriber = await harness.makeSubscriber()

        await waitForBusSubscriberCount(harness.bus, atLeast: 1)

        await subscriber.shutdown()
        await assertBusDrained(harness.bus)
    }

    @Test("subscriber registration helper acknowledges the named registration event")
    func subscriberRegistrationHelperAcknowledgesNamedRegistration() async {
        let harness = EventBusHarness<Int>()
        let registration = Task {
            await waitForBusSubscriberRegistration(
                harness.bus,
                subscriberName: "target subscriber"
            )
        }

        let subscriber = await harness.makeSubscriber(subscriberName: "target subscriber")
        await registration.value

        await subscriber.shutdown()
        await assertBusDrained(harness.bus)
    }

    @Test("subscriber registration helper observes an existing named subscriber")
    func subscriberRegistrationHelperObservesExistingNamedSubscriber() async {
        let harness = EventBusHarness<Int>()
        let subscriber = await harness.makeSubscriber(subscriberName: "existing subscriber")

        await waitForBusSubscriberRegistration(
            harness.bus,
            subscriberName: "existing subscriber"
        )

        await subscriber.shutdown()
        await assertBusDrained(harness.bus)
    }

    // MARK: - Eventually-wait dual turn/time budget

    /// Proof that `assertEventuallyMain`/`assertEventuallyAsync` keep polling as long as EITHER
    /// budget remains, giving up only once BOTH are exhausted. A pure time bound fails under
    /// MainActor contention (another suite can hold the actor for seconds at a time, so only a
    /// couple of turns land inside a short wall-clock window); a pure turn bound fails under
    /// cooperative-pool contention (a legitimately slow condition can need far more than a fixed
    /// turn count). Here `timeout: .zero` forces the time budget to expire immediately, so the
    /// wait must survive purely on the `minimumTurns` floor; a green result proves the floor was
    /// honored regardless of the (exhausted) clock.
    @Test("time budget exhausted still honors the turn floor (MainActor)")
    @MainActor
    func mainActorTimeBudgetExhaustedStillHonorsTurnFloor() async {
        let counter = MainActorCallCounter()

        await assertEventuallyMain(
            "condition true only on the 150th poll",
            timeout: .zero
        ) {
            counter.incrementAndCheck(threshold: 150)
        }

        #expect(counter.callCount == 150)
    }

    /// See `mainActorTimeBudgetExhaustedStillHonorsTurnFloor` above: the async variant.
    @Test("time budget exhausted still honors the turn floor (async)")
    func asyncTimeBudgetExhaustedStillHonorsTurnFloor() async {
        let counter = CallCounter()

        await assertEventuallyAsync(
            "condition true only on the 150th poll",
            timeout: .zero
        ) {
            await counter.incrementAndCheck(threshold: 150)
        }

        #expect(await counter.callCount == 150)
    }

    /// The mirror case: `minimumTurns: 1` lets the turn floor exhaust on the very first poll, so
    /// the wait must survive purely on the `timeout` wall-clock budget. The condition only
    /// becomes true once real time has actually elapsed, which no amount of extra turns can
    /// substitute for; a green result proves the time budget was honored regardless of the
    /// (immediately exhausted) turn floor.
    @Test("turn floor exhausted still honors the time budget (MainActor)")
    @MainActor
    func mainActorTurnFloorExhaustedStillHonorsTimeBudget() async {
        let clock = ContinuousClock()
        let start = clock.now

        await assertEventuallyMain(
            "elapsed time reaches 50ms",
            minimumTurns: 1,
            timeout: .seconds(5)
        ) {
            clock.now - start >= .milliseconds(50)
        }
    }

    /// See `mainActorTurnFloorExhaustedStillHonorsTimeBudget` above: the async variant.
    @Test("turn floor exhausted still honors the time budget (async)")
    func asyncTurnFloorExhaustedStillHonorsTimeBudget() async {
        let clock = ContinuousClock()
        let start = clock.now

        await assertEventuallyAsync(
            "elapsed time reaches 50ms",
            minimumTurns: 1,
            timeout: .seconds(5)
        ) {
            clock.now - start >= .milliseconds(50)
        }
    }
}
