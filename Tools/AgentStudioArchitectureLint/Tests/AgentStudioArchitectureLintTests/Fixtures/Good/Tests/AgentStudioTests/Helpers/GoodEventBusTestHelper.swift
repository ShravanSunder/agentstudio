import Foundation

struct GoodEventBusTestHelper {
    let bus: EventBus<RuntimeEnvelope>

    func testHelperDefaultIsAllowed(
        policy: BusSubscriberPolicy = .criticalUnbounded
    ) async {
        _ = await bus.subscribe(policy: policy, subscriberName: "GoodEventBusTestHelper")
    }
}
