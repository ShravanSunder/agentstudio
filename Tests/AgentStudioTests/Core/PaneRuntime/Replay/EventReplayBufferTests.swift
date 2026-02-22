import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("EventReplayBuffer")
struct EventReplayBufferTests {
    @Test("evicts oldest entry when capacity exceeded")
    func evictsOldest() {
        let buffer = EventReplayBuffer(capacity: 2)
        buffer.append(makeEnvelope(seq: 1))
        buffer.append(makeEnvelope(seq: 2))
        buffer.append(makeEnvelope(seq: 3))

        let events = buffer.events()
        #expect(buffer.count == 2)
        #expect(events.first?.seq == 2)
        #expect(events.last?.seq == 3)
    }

    private func makeEnvelope(seq: UInt64) -> PaneEventEnvelope {
        let clock = ContinuousClock()
        return PaneEventEnvelope(
            source: .pane(UUID()),
            paneKind: .terminal,
            seq: seq,
            commandId: nil,
            correlationId: nil,
            timestamp: clock.now,
            epoch: 0,
            event: .terminal(.bellRang)
        )
    }
}
