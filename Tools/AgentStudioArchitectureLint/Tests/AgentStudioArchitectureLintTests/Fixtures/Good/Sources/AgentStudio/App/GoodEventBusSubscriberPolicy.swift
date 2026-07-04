import Foundation

struct GoodEventBusSubscriberPolicy {
    let bus: EventBus<RuntimeEnvelope>
    let runtime: PaneRuntime
    let channel: PaneRuntimeEventChannel
    let bridge: WindowRestoreBridge
    let traceQueue: AgentStudioTraceEventQueue

    func explicitInjectedBusSubscribe() async {
        _ = await bus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "GoodEventBusSubscriberPolicy"
        )
    }

    func explicitAppEventSubscribe() async {
        _ = await AppEventBus.shared.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "GoodEventBusSubscriberPolicy"
        )
    }

    func explicitWaitForFirst() async {
        _ = await PaneRuntimeEventBus.shared.waitForFirst(
            policy: .lossyNewest(BusSubscriberPolicy.standardLossyBufferLimit),
            subscriberName: "GoodEventBusSubscriberPolicy"
        ) { _ in
            true
        }
    }

    func falseFriendsAreAllowed() {
        _ = runtime.subscribe()
        _ = channel.subscribe(isTerminated: false)
        _ = bridge
        _ = traceQueue
        let stream = AsyncStream<Int>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.yield(1)
            continuation.finish()
        }
        _ = stream
    }
}
