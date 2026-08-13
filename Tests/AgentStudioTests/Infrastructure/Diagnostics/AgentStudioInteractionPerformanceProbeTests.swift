import Foundation
import Testing

@testable import AgentStudioInfrastructure

@Suite
struct AgentStudioInteractionPerformanceProbeTests {
    @Test("matching settlement records one duration")
    func matchingSettlementRecordsOneDuration() throws {
        let clock = InteractionProbeTestClock(nowNanoseconds: 1_000_000)
        let recorder = InteractionProbeTestRecorder()
        let probe = AgentStudioInteractionPerformanceProbe(
            nowNanoseconds: clock.now,
            recordDuration: recorder.record
        )
        let correlationId = UUIDv7.generate()

        #expect(
            probe.beginInteraction(.commandBarOpen, correlationId: correlationId) == .started)
        clock.nowNanoseconds = 4_000_000

        #expect(probe.settleInteraction(correlationId: correlationId))
        #expect(
            recorder.records == [
                InteractionProbeTestRecorder.Record(
                    kind: .commandBarOpen,
                    duration: .milliseconds(3)
                )
            ])
    }

    @Test("unknown and duplicate settlements record no duration")
    func unknownAndDuplicateSettlementsRecordNoDuration() {
        let clock = InteractionProbeTestClock(nowNanoseconds: 10)
        let recorder = InteractionProbeTestRecorder()
        let probe = AgentStudioInteractionPerformanceProbe(
            nowNanoseconds: clock.now,
            recordDuration: recorder.record
        )
        let correlationId = UUIDv7.generate()

        #expect(!probe.settleInteraction(correlationId: correlationId))
        #expect(probe.beginInteraction(.tabMove, correlationId: correlationId) == .started)
        clock.nowNanoseconds = 20
        #expect(probe.settleInteraction(correlationId: correlationId))
        #expect(!probe.settleInteraction(correlationId: correlationId))
        #expect(recorder.records.count == 1)
    }

    @Test("new interaction on the same surface supersedes without latency")
    func newInteractionOnSameSurfaceSupersedesWithoutLatency() throws {
        let clock = InteractionProbeTestClock(nowNanoseconds: 1000)
        let recorder = InteractionProbeTestRecorder()
        let probe = AgentStudioInteractionPerformanceProbe(
            nowNanoseconds: clock.now,
            recordDuration: recorder.record
        )
        let openCorrelationId = UUIDv7.generate()
        let closeCorrelationId = UUIDv7.generate()

        #expect(
            probe.beginInteraction(.commandBarOpen, correlationId: openCorrelationId) == .started)
        clock.nowNanoseconds = 2000
        #expect(
            probe.beginInteraction(.commandBarClose, correlationId: closeCorrelationId) == .superseded)
        clock.nowNanoseconds = 5000

        #expect(!probe.settleInteraction(correlationId: openCorrelationId))
        #expect(probe.settleInteraction(correlationId: closeCorrelationId))
        let record = try #require(recorder.records.first)
        #expect(recorder.records.count == 1)
        #expect(record.kind == .commandBarClose)
        #expect(record.duration == .nanoseconds(3000))
    }

    @Test("different surfaces settle independently")
    func differentSurfacesSettleIndependently() {
        let clock = InteractionProbeTestClock(nowNanoseconds: 100)
        let recorder = InteractionProbeTestRecorder()
        let probe = AgentStudioInteractionPerformanceProbe(
            nowNanoseconds: clock.now,
            recordDuration: recorder.record
        )
        let tabCorrelationId = UUIDv7.generate()
        let dividerCorrelationId = UUIDv7.generate()

        #expect(probe.beginInteraction(.tabMove, correlationId: tabCorrelationId) == .started)
        #expect(
            probe.beginInteraction(.dividerFrame, correlationId: dividerCorrelationId) == .started)
        clock.nowNanoseconds = 200

        #expect(probe.settleInteraction(correlationId: dividerCorrelationId))
        #expect(probe.settleInteraction(correlationId: tabCorrelationId))
        #expect(recorder.records.map(\.kind) == [.dividerFrame, .tabMove])
    }
}

private final class InteractionProbeTestClock: @unchecked Sendable {
    var nowNanoseconds: UInt64

    init(nowNanoseconds: UInt64) {
        self.nowNanoseconds = nowNanoseconds
    }

    func now() -> UInt64 {
        nowNanoseconds
    }
}

private final class InteractionProbeTestRecorder: @unchecked Sendable {
    struct Record: Equatable {
        let kind: AgentStudioInteractionKind
        let duration: Duration
    }

    private(set) var records: [Record] = []

    func record(kind: AgentStudioInteractionKind, duration: Duration) {
        records.append(Record(kind: kind, duration: duration))
    }
}
