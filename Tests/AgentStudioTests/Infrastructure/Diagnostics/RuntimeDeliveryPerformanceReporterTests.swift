import Testing

@testable import AgentStudio

@Suite("Runtime delivery performance reporter")
struct RuntimeDeliveryPerformanceReporterTests {
    @Test("disabled reporter ignores updates and returns zero")
    func disabledReporterIgnoresUpdates() {
        let reporter = RuntimeDeliveryPerformanceReporter()
        let channelToken = RuntimeDeliveryChannelToken.make()

        reporter.registerRuntimeChannel(channelToken)
        reporter.recordRuntimeChannelOutboundEnqueued(channelToken)
        reporter.recordRuntimeChannelOutboundDropped()
        reporter.recordEventBusSubscriberAdded()
        reporter.recordEventBusDeliveryEnqueued()
        reporter.recordEventBusLiveDrop()
        reporter.recordEventBusReplayDrop()

        #expect(reporter.snapshot() == .zero)
    }

    @Test("enable reset and disable have explicit zero-state semantics")
    func lifecycleControlsClearCountsExactly() {
        let reporter = RuntimeDeliveryPerformanceReporter()
        let channelToken = RuntimeDeliveryChannelToken.make()
        #expect(UUIDv7.isV7(channelToken.rawValue))

        reporter.enable()
        reporter.registerRuntimeChannel(channelToken)
        reporter.recordRuntimeChannelOutboundEnqueued(channelToken)
        reporter.recordEventBusSubscriberAdded()
        reporter.recordEventBusDeliveryEnqueued()
        #expect(reporter.snapshot().totalPendingCount == 2)

        reporter.reset()
        #expect(reporter.snapshot() == .zero)
        reporter.recordEventBusDeliveryEnqueued()
        #expect(reporter.snapshot().eventBusActiveDeliveryDebt == 1)

        reporter.disable()
        #expect(reporter.snapshot() == .zero)
        reporter.recordEventBusDeliveryEnqueued()
        #expect(reporter.snapshot() == .zero)
    }

    @Test("channel retirement and late completion cannot underflow")
    func retiredChannelIgnoresLateCompletion() {
        let reporter = RuntimeDeliveryPerformanceReporter()
        let channelToken = RuntimeDeliveryChannelToken.make()
        reporter.enable()
        reporter.registerRuntimeChannel(channelToken)
        reporter.recordRuntimeChannelOutboundEnqueued(channelToken)

        reporter.retireRuntimeChannel(channelToken)
        reporter.recordRuntimeChannelOutboundPosted(channelToken)

        let snapshot = reporter.snapshot()
        #expect(snapshot.runtimeChannelOutboundPendingCount == 0)
        #expect(snapshot.runtimeChannelRetiredUndeliveredCount == 1)
    }

    @Test("snapshot exposes only aggregate numeric trace attributes")
    func snapshotTraceAttributesAreAggregateIntegers() {
        let reporter = RuntimeDeliveryPerformanceReporter()
        reporter.enable()
        reporter.recordEventBusSubscriberAdded()
        reporter.recordEventBusDeliveryEnqueued()
        reporter.recordEventBusLiveDrop()

        let attributes = reporter.snapshot().traceAttributes

        #expect(attributes.count == 9)
        #expect(
            attributes["agentstudio.performance.runtime_delivery.eventbus_active_delivery_debt.count"]
                == .int(1)
        )
        #expect(
            attributes["agentstudio.performance.runtime_delivery.total_pending.count"]
                == .int(1)
        )
        #expect(
            attributes["agentstudio.performance.runtime_delivery.eventbus_live_dropped.count"]
                == .int(1)
        )
    }
}
