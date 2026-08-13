import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite
struct SplitViewResizePerformanceTests {
    @Test("nested split measurement settles only at layout publication")
    func nestedSplitSettlesAtLayoutPublication() {
        let recorder = SplitDividerInteractionTestRecorder()
        let probe = AgentStudioInteractionPerformanceProbe(
            nowNanoseconds: { recorder.nowNanoseconds },
            recordDuration: recorder.record
        )
        var measurement = DividerFrameMeasurementState()

        let sampleAdmitted = measurement.admitSample(using: probe)
        #expect(sampleAdmitted)
        recorder.nowNanoseconds = 5_000_000
        #expect(recorder.records.isEmpty)
        measurement.layoutDidPublish(using: probe)

        #expect(recorder.records.count == 1)
        #expect(recorder.records.first?.kind == .dividerFrame)
        #expect(recorder.records.first?.duration == .milliseconds(5))
    }
}

private final class SplitDividerInteractionTestRecorder: @unchecked Sendable {
    struct Record {
        let kind: AgentStudioInteractionKind
        let duration: Duration
    }

    var nowNanoseconds: UInt64 = 0
    private(set) var records: [Record] = []

    func record(kind: AgentStudioInteractionKind, duration: Duration) {
        records.append(.init(kind: kind, duration: duration))
    }
}
