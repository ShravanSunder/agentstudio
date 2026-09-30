import Testing

@testable import AgentStudioCore

@Suite("EventBus delivery checkpoints")
struct EventBusDeliveryCheckpointTests {
    @Test("duplicate labels retain independent subscription checkpoints")
    func duplicateLabelsHaveIndependentCheckpoints() async {
        let bus = EventBus<Int>()
        let first = await bus.subscribe(policy: .criticalUnbounded, subscriberName: "same")
        _ = await bus.post(1)
        let second = await bus.subscribe(policy: .criticalUnbounded, subscriberName: "same")
        _ = await bus.post(2)

        #expect(first.deliveryCheckpoint() == EventBusDeliveryCheckpoint(enqueuedCount: 2, droppedCount: 0))
        #expect(second.deliveryCheckpoint() == EventBusDeliveryCheckpoint(enqueuedCount: 1, droppedCount: 0))
    }

    @Test("newest buffering reports eviction without inventing another enqueue slot")
    func newestBufferEvictionIsReported() async {
        let bus = EventBus<Int>()
        let subscription = await bus.subscribe(policy: .lossyNewest(1), subscriberName: "eviction")
        _ = await bus.post(1)
        _ = await bus.post(2)

        #expect(subscription.deliveryCheckpoint() == EventBusDeliveryCheckpoint(enqueuedCount: 1, droppedCount: 1))
        var iterator = subscription.makeAsyncIterator()
        #expect(await iterator.next() == 2)
    }
}
