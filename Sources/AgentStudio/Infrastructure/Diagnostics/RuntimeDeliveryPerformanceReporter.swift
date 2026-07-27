import Foundation
import Synchronization

struct RuntimeDeliveryChannelToken: Hashable, Sendable {
    let rawValue: UUID

    static func make() -> Self {
        Self(rawValue: UUIDv7.generate())
    }
}

struct RuntimeDeliveryPerformanceSnapshot: Equatable, Sendable {
    static let zero = Self(
        runtimeChannelOutboundPendingCount: 0,
        eventBusActiveDeliveryDebt: 0,
        runtimeChannelOutboundDroppedCount: 0,
        runtimeChannelRetiredUndeliveredCount: 0,
        eventBusLiveDroppedCount: 0,
        eventBusReplayDroppedCount: 0,
        eventBusRetiredUndeliveredCount: 0,
        eventBusActiveSubscriberCount: 0
    )

    let runtimeChannelOutboundPendingCount: UInt64
    let eventBusActiveDeliveryDebt: UInt64
    let runtimeChannelOutboundDroppedCount: UInt64
    let runtimeChannelRetiredUndeliveredCount: UInt64
    let eventBusLiveDroppedCount: UInt64
    let eventBusReplayDroppedCount: UInt64
    let eventBusRetiredUndeliveredCount: UInt64
    let eventBusActiveSubscriberCount: UInt64

    var totalPendingCount: UInt64 {
        runtimeChannelOutboundPendingCount.addingClamped(eventBusActiveDeliveryDebt)
    }

    var traceAttributes: [String: AgentStudioTraceValue] {
        [
            "agentstudio.performance.runtime_delivery.runtime_channel_outbound_pending.count":
                .int(Self.traceInteger(runtimeChannelOutboundPendingCount)),
            "agentstudio.performance.runtime_delivery.eventbus_active_delivery_debt.count":
                .int(Self.traceInteger(eventBusActiveDeliveryDebt)),
            "agentstudio.performance.runtime_delivery.total_pending.count":
                .int(Self.traceInteger(totalPendingCount)),
            "agentstudio.performance.runtime_delivery.runtime_channel_outbound_dropped.count":
                .int(Self.traceInteger(runtimeChannelOutboundDroppedCount)),
            "agentstudio.performance.runtime_delivery.runtime_channel_retired_undelivered.count":
                .int(Self.traceInteger(runtimeChannelRetiredUndeliveredCount)),
            "agentstudio.performance.runtime_delivery.eventbus_live_dropped.count":
                .int(Self.traceInteger(eventBusLiveDroppedCount)),
            "agentstudio.performance.runtime_delivery.eventbus_replay_dropped.count":
                .int(Self.traceInteger(eventBusReplayDroppedCount)),
            "agentstudio.performance.runtime_delivery.eventbus_retired_undelivered.count":
                .int(Self.traceInteger(eventBusRetiredUndeliveredCount)),
            "agentstudio.performance.runtime_delivery.eventbus_active_subscriber.count":
                .int(Self.traceInteger(eventBusActiveSubscriberCount)),
        ]
    }

    private static func traceInteger(_ value: UInt64) -> Int {
        value > UInt64(Int.max) ? Int.max : Int(value)
    }
}

final class RuntimeDeliveryPerformanceReporter: Sendable {
    private struct RuntimeChannelState: Sendable {
        var outboundPendingCount: UInt64 = 0
    }

    private struct State: Sendable {
        var isEnabled = false
        var runtimeChannels: [RuntimeDeliveryChannelToken: RuntimeChannelState] = [:]
        var eventBusActiveDeliveryDebt: UInt64 = 0
        var runtimeChannelOutboundDroppedCount: UInt64 = 0
        var runtimeChannelRetiredUndeliveredCount: UInt64 = 0
        var eventBusLiveDroppedCount: UInt64 = 0
        var eventBusReplayDroppedCount: UInt64 = 0
        var eventBusRetiredUndeliveredCount: UInt64 = 0
        var eventBusActiveSubscriberCount: UInt64 = 0

        var runtimeChannelOutboundPendingCount: UInt64 {
            runtimeChannels.values.reduce(into: UInt64(0)) { total, channel in
                total = total.addingClamped(channel.outboundPendingCount)
            }
        }

        var snapshot: RuntimeDeliveryPerformanceSnapshot {
            RuntimeDeliveryPerformanceSnapshot(
                runtimeChannelOutboundPendingCount: runtimeChannelOutboundPendingCount,
                eventBusActiveDeliveryDebt: eventBusActiveDeliveryDebt,
                runtimeChannelOutboundDroppedCount: runtimeChannelOutboundDroppedCount,
                runtimeChannelRetiredUndeliveredCount: runtimeChannelRetiredUndeliveredCount,
                eventBusLiveDroppedCount: eventBusLiveDroppedCount,
                eventBusReplayDroppedCount: eventBusReplayDroppedCount,
                eventBusRetiredUndeliveredCount: eventBusRetiredUndeliveredCount,
                eventBusActiveSubscriberCount: eventBusActiveSubscriberCount
            )
        }

        mutating func clearCounts(keepingEnabled: Bool) {
            self = Self(isEnabled: keepingEnabled)
        }
    }

    private let enabled = Atomic<Bool>(false)
    private let state = Mutex(State())

    func enable() {
        state.withLock { state in
            guard !state.isEnabled else { return }
            state.clearCounts(keepingEnabled: true)
            enabled.store(true, ordering: .relaxed)
        }
    }

    func disable() {
        enabled.store(false, ordering: .relaxed)
        state.withLock { state in
            state.clearCounts(keepingEnabled: false)
        }
    }

    func reset() {
        guard enabled.load(ordering: .relaxed) else { return }
        state.withLock { state in
            guard state.isEnabled else { return }
            state.clearCounts(keepingEnabled: true)
        }
    }

    func snapshot() -> RuntimeDeliveryPerformanceSnapshot {
        guard enabled.load(ordering: .relaxed) else { return .zero }
        return state.withLock { state in
            guard state.isEnabled else { return .zero }
            return state.snapshot
        }
    }

    func registerRuntimeChannel(_ token: RuntimeDeliveryChannelToken) {
        withEnabledState { state in
            state.runtimeChannels[token, default: RuntimeChannelState()] = RuntimeChannelState()
        }
    }

    func recordRuntimeChannelOutboundEnqueued(_ token: RuntimeDeliveryChannelToken) {
        withEnabledState { state in
            var channel = state.runtimeChannels[token, default: RuntimeChannelState()]
            channel.outboundPendingCount = channel.outboundPendingCount.addingClamped(1)
            state.runtimeChannels[token] = channel
        }
    }

    func recordRuntimeChannelOutboundDropped() {
        withEnabledState { state in
            state.runtimeChannelOutboundDroppedCount =
                state.runtimeChannelOutboundDroppedCount.addingClamped(1)
        }
    }

    func recordRuntimeChannelOutboundPosted(_ token: RuntimeDeliveryChannelToken) {
        withEnabledState { state in
            guard var channel = state.runtimeChannels[token], channel.outboundPendingCount > 0 else { return }
            channel.outboundPendingCount -= 1
            state.runtimeChannels[token] = channel
        }
    }

    func retireRuntimeChannel(_ token: RuntimeDeliveryChannelToken) {
        withEnabledState { state in
            guard let channel = state.runtimeChannels.removeValue(forKey: token) else { return }
            state.runtimeChannelRetiredUndeliveredCount =
                state.runtimeChannelRetiredUndeliveredCount.addingClamped(channel.outboundPendingCount)
        }
    }

    func recordEventBusSubscriberAdded() {
        withEnabledState { state in
            state.eventBusActiveSubscriberCount = state.eventBusActiveSubscriberCount.addingClamped(1)
        }
    }

    func recordEventBusDeliveryEnqueued() {
        withEnabledState { state in
            state.eventBusActiveDeliveryDebt = state.eventBusActiveDeliveryDebt.addingClamped(1)
        }
    }

    func recordEventBusDeliveryConsumed() {
        withEnabledState { state in
            guard state.eventBusActiveDeliveryDebt > 0 else { return }
            state.eventBusActiveDeliveryDebt -= 1
        }
    }

    func recordEventBusLiveDrop() {
        withEnabledState { state in
            state.eventBusLiveDroppedCount = state.eventBusLiveDroppedCount.addingClamped(1)
        }
    }

    func recordEventBusReplayDrop() {
        withEnabledState { state in
            state.eventBusReplayDroppedCount = state.eventBusReplayDroppedCount.addingClamped(1)
        }
    }

    func recordEventBusSubscriberRemoved(pendingDeliveryCount: UInt64) {
        withEnabledState { state in
            if state.eventBusActiveSubscriberCount > 0 {
                state.eventBusActiveSubscriberCount -= 1
            }
            state.eventBusActiveDeliveryDebt =
                state.eventBusActiveDeliveryDebt.subtractingClamped(pendingDeliveryCount)
            state.eventBusRetiredUndeliveredCount =
                state.eventBusRetiredUndeliveredCount.addingClamped(pendingDeliveryCount)
        }
    }

    private func withEnabledState(_ update: (inout State) -> Void) {
        guard enabled.load(ordering: .relaxed) else { return }
        state.withLock { state in
            guard state.isEnabled else { return }
            update(&state)
        }
    }
}

extension UInt64 {
    fileprivate func addingClamped(_ other: UInt64) -> UInt64 {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? .max : sum
    }

    fileprivate func subtractingClamped(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}
