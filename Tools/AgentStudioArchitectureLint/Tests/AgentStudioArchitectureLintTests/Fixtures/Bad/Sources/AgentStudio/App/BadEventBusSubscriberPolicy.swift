import Foundation

struct BadEventBusSubscriberPolicy {
    let bus: EventBus<RuntimeEnvelope>

    func bareInjectedBusSubscribe() async {
        _ = await bus.subscribe()
    }

    func rawBufferingPolicySubscribe() async {
        _ = await bus.subscribe(bufferingPolicy: .bufferingNewest(1))
    }

    func barePaneRuntimeSharedSubscribe() async {
        _ = await PaneRuntimeEventBus.shared.subscribe()
    }

    func bareAppEventSharedSubscribe() async {
        _ = await AppEventBus.shared.subscribe()
    }

    func bareWaitForFirst() async {
        _ = await PaneRuntimeEventBus.shared.waitForFirst { _ in
            true
        }
    }

    func inferredSharedAliasSubscribe() async {
        let bus = PaneRuntimeEventBus.shared
        _ = await bus.subscribe()
    }

    func inferredSharedAliasWaitForFirst() async {
        let bus = AppEventBus.shared
        _ = await bus.waitForFirst { _ in
            true
        }
    }

    func subscribe(
        policy: BusSubscriberPolicy = .criticalUnbounded,
        subscriberName: String
    ) async {
        _ = await bus.subscribe(policy: policy, subscriberName: subscriberName)
    }

    func observeRuntimeEvents(
        eventPolicy: BusSubscriberPolicy = .criticalUnbounded
    ) async {
        _ = await bus.subscribe(policy: eventPolicy, subscriberName: "BadEventBusSubscriberPolicy")
    }

    func hiddenRuntimeEvents() async -> EventBusSubscription<RuntimeEnvelope> {
        await bus.subscribe(policy: .criticalUnbounded, subscriberName: "BadEventBusSubscriberPolicy")
    }
}
