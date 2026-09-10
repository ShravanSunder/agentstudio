import Testing

@testable import AgentStudioCore

@Suite("Darwin FSEvent stream lifecycle gate")
struct DarwinFSEventStreamLifecycleGateTests {
    @Test("retirement waits for in-flight flush and tears down exactly once")
    func retirementDefersUntilLastFlushFinishes() {
        let gate = DarwinFSEventStreamLifecycleGate()

        #expect(gate.beginFlush())
        #expect(!gate.requestRetirement())

        let completion = gate.finishFlush()
        #expect(completion.shouldTeardown)
        #expect(!completion.isCurrent)
        #expect(!gate.beginFlush())
        #expect(!gate.requestRetirement())
    }

    @Test("active flush remains current and retirement without a flush tears down immediately")
    func activeFlushAndImmediateRetirementHaveSingleOwners() {
        let activeGate = DarwinFSEventStreamLifecycleGate()
        #expect(activeGate.beginFlush())
        let activeCompletion = activeGate.finishFlush()
        #expect(!activeCompletion.shouldTeardown)
        #expect(activeCompletion.isCurrent)

        let retiringGate = DarwinFSEventStreamLifecycleGate()
        #expect(retiringGate.requestRetirement())
        #expect(!retiringGate.requestRetirement())
        #expect(!retiringGate.beginFlush())
    }
}
