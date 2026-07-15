import Testing

@testable import AgentStudio

@Suite
struct MainActorResponsivenessHeartbeatTests {
    @MainActor
    @Test
    func injectedClockTracksGapOverdueResetAndMissingPulse() {
        let heartbeat = MainActorResponsivenessHeartbeat(
            expectedIntervalNanoseconds: 10,
            clock: ScriptedPerformanceClock([100, 108, 125, 145, 150])
        )

        #expect(heartbeat.observationWithoutPulse() == .missingPulse)
        #expect(heartbeat.pulse() == .firstPulse)
        #expect(
            heartbeat.pulse()
                == .observed(.init(gapNanoseconds: 8, overdue: .withinBudget)))
        #expect(
            heartbeat.pulse()
                == .observed(.init(gapNanoseconds: 17, overdue: .overdue(consecutiveCount: 1))))
        #expect(
            heartbeat.pulse()
                == .observed(.init(gapNanoseconds: 20, overdue: .overdue(consecutiveCount: 2))))

        heartbeat.reset()
        #expect(heartbeat.observationWithoutPulse() == .missingPulse)
        #expect(heartbeat.pulse() == .firstPulse)
    }
}
