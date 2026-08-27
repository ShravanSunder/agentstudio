import Testing

@testable import AgentStudioCore

@Suite("Darwin FSEvent ingress performance attribution")
struct DarwinFSEventIngressPerformanceAccumulatorTests {
    @Test("snapshot atomically returns and resets every fixed attribution counter")
    func snapshotReturnsAndResetsFixedCounters() {
        let accumulator = DarwinFSEventIngressPerformanceAccumulator()

        accumulator.recordLocalRawCallback(eventCount: 3)
        accumulator.recordSharedRawCallback(eventCount: 5)
        accumulator.recordSharedFanout(
            exactSubscriberCount: 7,
            uncertaintySubscriberCount: 11,
            fullRefreshEmissionCount: 13
        )
        accumulator.recordIngress(source: .local, disposition: .accepted, pathCount: 17)
        accumulator.recordIngress(source: .sharedExact, disposition: .dropped, pathCount: 19)
        accumulator.recordIngress(source: .sharedUncertainty, disposition: .terminated, pathCount: 23)
        accumulator.recordOverflowDrain(
            recoveryCount: 29,
            retainedPathCount: 31,
            coarseRecoveryCount: 37
        )

        let snapshot = accumulator.snapshotAndReset()

        #expect(snapshot.localRawCallbackBatchCount == 1)
        #expect(snapshot.localRawCallbackEventCount == 3)
        #expect(snapshot.sharedRawCallbackBatchCount == 1)
        #expect(snapshot.sharedRawCallbackEventCount == 5)
        #expect(snapshot.sharedExactSubscriberCount == 7)
        #expect(snapshot.sharedUncertaintySubscriberCount == 11)
        #expect(snapshot.sharedFullRefreshEmissionCount == 13)
        #expect(snapshot.localIngress.acceptedBatchCount == 1)
        #expect(snapshot.localIngress.acceptedPathCount == 17)
        #expect(snapshot.sharedExactIngress.droppedBatchCount == 1)
        #expect(snapshot.sharedExactIngress.droppedPathCount == 19)
        #expect(snapshot.sharedUncertaintyIngress.terminatedBatchCount == 1)
        #expect(snapshot.sharedUncertaintyIngress.terminatedPathCount == 23)
        #expect(snapshot.overflowDrainCount == 1)
        #expect(snapshot.overflowRecoveryCount == 29)
        #expect(snapshot.overflowRetainedPathCount == 31)
        #expect(snapshot.overflowCoarseRecoveryCount == 37)
        #expect(accumulator.snapshotAndReset() == .zero)
    }

    @Test("trace projection contains only the fixed numeric attribution allowlist")
    func traceProjectionContainsOnlyFixedNumericAttributes() {
        let accumulator = DarwinFSEventIngressPerformanceAccumulator()
        accumulator.recordLocalRawCallback(eventCount: 2)
        accumulator.recordIngress(source: .local, disposition: .accepted, pathCount: 2)

        let attributes = accumulator.snapshotAndReset().traceAttributes

        #expect(attributes["agentstudio.performance.filesystem.ingress.local_raw_callback.batch.count"] == .int(1))
        #expect(attributes["agentstudio.performance.filesystem.ingress.local_raw_callback.event.count"] == .int(2))
        #expect(attributes["agentstudio.performance.filesystem.ingress.local.accepted.batch.count"] == .int(1))
        #expect(attributes["agentstudio.performance.filesystem.ingress.local.accepted.path.count"] == .int(2))
        #expect(attributes.keys.allSatisfy { $0.hasPrefix("agentstudio.performance.filesystem.ingress.") })
        #expect(
            attributes.values.allSatisfy { value in
                if case .int = value { return true }
                return false
            })
    }
}
