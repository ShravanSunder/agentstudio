import Testing

@testable import AgentStudio

@Suite
struct PerformanceProbeSinkTests {
    @Test
    func offersSynchronouslyWithFIFOBoundsExactLossAndShutdown() {
        let sink = PerformanceProbeSink(capacity: 2)
        let first = PerformanceProbeRecord.contraction(stage: .source, count: 10)
        let second = PerformanceProbeRecord.contraction(stage: .admitted, count: 4)

        #expect(UUIDv7.isV7(sink.sinkID.rawValue))

        #expect(sink.offer(first) == .accepted)
        #expect(sink.offer(second) == .accepted)
        #expect(sink.offer(.contraction(stage: .fact, count: 1)) == .lost(.capacity))

        let drainToken = PerformanceProbeDrainToken.make(sinkID: sink.sinkID)
        #expect(UUIDv7.isV7(drainToken.operationID))
        #expect(sink.beginDrain(using: drainToken) == .began(drainToken))
        let partial = sink.drain(maximumCount: 1, using: drainToken)
        #expect(partial.records == [first])
        #expect(partial.token == drainToken)
        #expect(partial.acceptedTotal == 2)
        #expect(partial.lostTotal == 1)
        #expect(partial.remainingCount == 1)

        #expect(sink.offer(.contraction(stage: .rendered, count: 1)) == .lost(.shutdown))
        let final = sink.drain(maximumCount: 10, using: drainToken)
        #expect(final.records == [second])
        #expect(final.lostTotal == 2)
        #expect(final.remainingCount == 0)
    }
}
