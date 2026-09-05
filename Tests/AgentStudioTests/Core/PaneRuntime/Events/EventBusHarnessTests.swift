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

    // MARK: - Eventually-wait defaults

    /// Proof that `assertEventuallyMain`/`assertEventuallyAsync` run to their `timeout`
    /// wall-clock bound by default instead of stopping after a fixed MainActor yield count.
    /// Before this was fixed, both helpers defaulted `maxTurns` to 200, so a condition that
    /// only becomes true well past 200 polls (as happens when concurrent suites in the fast
    /// lane steal this suite's yields) timed out even though most of the 5-second `timeout`
    /// budget remained unused.
    @Test("assertEventuallyMain with default maxTurns runs well past 200 polls")
    @MainActor
    func assertEventuallyMainDefaultMaxTurnsRunsPastTwoHundredPolls() async {
        let counter = MainActorCallCounter()

        await assertEventuallyMain("condition true only on the 1000th poll") {
            counter.incrementAndCheck(threshold: 1000)
        }

        #expect(counter.callCount == 1000)
    }

    @Test("assertEventuallyAsync with default maxTurns runs well past 200 polls")
    func assertEventuallyAsyncDefaultMaxTurnsRunsPastTwoHundredPolls() async {
        let counter = CallCounter()

        await assertEventuallyAsync("condition true only on the 1000th poll") {
            await counter.incrementAndCheck(threshold: 1000)
        }

        #expect(await counter.callCount == 1000)
    }
}
