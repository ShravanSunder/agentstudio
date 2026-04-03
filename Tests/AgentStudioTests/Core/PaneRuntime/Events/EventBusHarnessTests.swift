import Foundation
import Testing

@testable import AgentStudio

@Suite("EventBusHarness")
struct EventBusHarnessTests {
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
}
