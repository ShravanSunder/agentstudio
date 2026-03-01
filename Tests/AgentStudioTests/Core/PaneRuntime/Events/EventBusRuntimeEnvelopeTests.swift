import Foundation
import Testing

@testable import AgentStudio

@Suite("EventBus RuntimeEnvelope replay")
struct EventBusRuntimeEnvelopeTests {
    @Test("replay keeps at most 256 envelopes per source")
    func replayBoundPerSource() async {
        let bus = EventBus<RuntimeEnvelope>(
            replayConfiguration: .init(
                capacityPerSource: 256,
                sourceKey: { envelope in
                    envelope.source.description
                }
            )
        )
        let paneA = PaneId()
        let paneB = PaneId()

        for seq in 1...300 {
            _ = await bus.post(makePaneEnvelope(paneId: paneA, seq: UInt64(seq)))
            _ = await bus.post(makePaneEnvelope(paneId: paneB, seq: UInt64(seq)))
        }

        let stream = await bus.subscribe()
        var iterator = stream.makeAsyncIterator()
        var replayed: [RuntimeEnvelope] = []
        for _ in 0..<(256 * 2) {
            guard let envelope = await iterator.next() else {
                Issue.record("Expected replay payload for all retained runtime envelopes")
                return
            }
            replayed.append(envelope)
        }

        let paneASeqs = replayed.filter { $0.source == .pane(paneA) }.map(\.seq)
        let paneBSeqs = replayed.filter { $0.source == .pane(paneB) }.map(\.seq)
        #expect(paneASeqs.count == 256)
        #expect(paneBSeqs.count == 256)
        #expect(paneASeqs.first == 45)
        #expect(paneASeqs.last == 300)
        #expect(paneBSeqs.first == 45)
        #expect(paneBSeqs.last == 300)
    }

    @Test("replay bound is isolated per source")
    func replayBoundIsolationPerSource() async {
        let bus = EventBus<RuntimeEnvelope>(
            replayConfiguration: .init(
                capacityPerSource: 256,
                sourceKey: { envelope in
                    envelope.source.description
                }
            )
        )
        let hotPane = PaneId()
        let coolPane = PaneId()

        for seq in 1...400 {
            _ = await bus.post(makePaneEnvelope(paneId: hotPane, seq: UInt64(seq)))
        }
        for seq in 1...3 {
            _ = await bus.post(makePaneEnvelope(paneId: coolPane, seq: UInt64(seq)))
        }

        let stream = await bus.subscribe()
        var iterator = stream.makeAsyncIterator()
        var replayed: [RuntimeEnvelope] = []
        for _ in 0..<(256 + 3) {
            guard let envelope = await iterator.next() else {
                Issue.record("Expected replay payload for bounded + sparse sources")
                return
            }
            replayed.append(envelope)
        }

        let hotSeqs = replayed.filter { $0.source == .pane(hotPane) }.map(\.seq)
        let coolSeqs = replayed.filter { $0.source == .pane(coolPane) }.map(\.seq)
        #expect(hotSeqs.count == 256)
        #expect(hotSeqs.first == 145)
        #expect(hotSeqs.last == 400)
        #expect(coolSeqs == [1, 2, 3])
    }

    private func makePaneEnvelope(paneId: PaneId, seq: UInt64) -> RuntimeEnvelope {
        .pane(
            PaneEnvelope.test(
                event: .terminal(.bellRang),
                paneId: paneId,
                paneKind: .terminal,
                source: .pane(paneId),
                seq: seq
            )
        )
    }
}
