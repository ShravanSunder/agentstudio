import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("EventReplayBuffer")
struct EventReplayBufferTests {
    @Test("evicts oldest entry when maxEvents exceeded")
    func evictsOldestByEventCount() {
        let buffer = EventReplayBuffer(config: .init(maxEvents: 2, maxBytes: 10_000, ttl: .seconds(300)))
        buffer.append(makeEnvelope(seq: 1, event: .terminal(.bellRang)))
        buffer.append(makeEnvelope(seq: 2, event: .terminal(.bellRang)))
        buffer.append(makeEnvelope(seq: 3, event: .terminal(.bellRang)))

        let events = buffer.events()
        #expect(buffer.count == 2)
        #expect(events.first?.seq == 2)
        #expect(events.last?.seq == 3)
    }

    @Test("evicts by byte budget")
    func evictsByByteBudget() {
        let buffer = EventReplayBuffer(config: .init(maxEvents: 10, maxBytes: 350, ttl: .seconds(300)))
        let payload = String(repeating: "x", count: 256)

        buffer.append(
            makeEnvelope(
                seq: 1,
                event: .browser(.consoleMessage(level: .info, message: payload))
            )
        )
        buffer.append(
            makeEnvelope(
                seq: 2,
                event: .browser(.consoleMessage(level: .info, message: payload))
            )
        )

        let events = buffer.events()
        #expect(events.count == 1)
        #expect(events.first?.seq == 2)
    }

    @Test("reports replay gap when requested seq is too old")
    func detectsReplayGap() {
        let buffer = EventReplayBuffer(config: .init(maxEvents: 2, maxBytes: 10_000, ttl: .seconds(300)))
        buffer.append(makeEnvelope(seq: 1, event: .terminal(.bellRang)))
        buffer.append(makeEnvelope(seq: 2, event: .terminal(.bellRang)))
        buffer.append(makeEnvelope(seq: 3, event: .terminal(.bellRang)))

        let replay = buffer.eventsSince(seq: 0)

        #expect(replay.gapDetected)
        #expect(replay.events.count == 2)
        #expect(replay.events.first?.seq == 2)
        #expect(replay.nextSeq == 3)
    }

    @Test("evicts stale events by ttl")
    func evictsStaleEvents() {
        let clock = ContinuousClock()
        let buffer = EventReplayBuffer(config: .init(maxEvents: 10, maxBytes: 10_000, ttl: .seconds(1)))

        let staleTimestamp = clock.now.advanced(by: .seconds(-10))
        buffer.append(makeEnvelope(seq: 1, timestamp: staleTimestamp, event: .terminal(.bellRang)))
        buffer.append(makeEnvelope(seq: 2, timestamp: clock.now, event: .terminal(.bellRang)))

        let events = buffer.events()
        #expect(events.count == 1)
        #expect(events.first?.seq == 2)
    }

    private func makeEnvelope(
        seq: UInt64,
        timestamp: ContinuousClock.Instant = ContinuousClock().now,
        event: PaneRuntimeEvent
    ) -> PaneEventEnvelope {
        PaneEventEnvelope(
            source: .pane(UUID()),
            paneKind: .terminal,
            seq: seq,
            commandId: nil,
            correlationId: nil,
            timestamp: timestamp,
            epoch: 0,
            event: event
        )
    }
}
