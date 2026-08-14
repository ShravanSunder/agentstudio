import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioTestSupport

@MainActor
@Suite("Background fact apply governor", .serialized)
struct BackgroundFactApplyGovernorTests {
    @Test("newer same-key fact supersedes pending work and acknowledges both facts")
    func newerSameKeyFactSupersedesPendingWork() async {
        let clock = TestPushClock()
        var appliedFacts: [(Int, String)] = []
        let governor = BackgroundFactApplyGovernor<Int, String>(
            tickCadence: .milliseconds(10),
            drainBudget: .milliseconds(4),
            clock: clock
        ) { key, fact in
            appliedFacts.append((key, fact))
        }
        governor.start()
        let firstAcknowledgement = governor.enqueue("first", for: 7)
        let secondAcknowledgement = governor.enqueue("second", for: 7)

        #expect(await firstAcknowledgement.result() == .superseded)
        await clock.waitForPendingSleepCount(exactly: 1)
        clock.advance(by: .milliseconds(10))
        #expect(await secondAcknowledgement.result() == .applied)
        await governor.shutdown()

        #expect(appliedFacts.map(\.0) == [7])
        #expect(appliedFacts.map(\.1) == ["second"])
    }

    @Test("drain budget carries remaining facts into the next injected-clock tick")
    func drainBudgetCarriesRemainingFacts() async {
        let clock = TestPushClock()
        var appliedKeys: [Int] = []
        let governor = BackgroundFactApplyGovernor<Int, Int>(
            tickCadence: .milliseconds(10),
            drainBudget: .milliseconds(4),
            clock: clock
        ) { key, _ in
            appliedKeys.append(key)
            clock.advance(by: .milliseconds(3))
        }
        governor.start()
        let acknowledgements = (1...3).map { key in
            governor.enqueue(key, for: key)
        }

        await clock.waitForPendingSleepCount(exactly: 1)
        clock.advance(by: .milliseconds(10))
        await eventually("first budgeted drain") {
            appliedKeys.count == 2
        }
        #expect(appliedKeys == [1, 2])

        await clock.waitForPendingSleepCount(exactly: 1)
        clock.advance(by: .milliseconds(10))
        for acknowledgement in acknowledgements {
            #expect(await acknowledgement.result() == .applied)
        }
        await governor.shutdown()

        #expect(appliedKeys == [1, 2, 3])
    }

    @Test("shutdown synchronously flushes pending facts without waiting for a tick")
    func shutdownFlushesPendingFacts() async {
        let clock = TestPushClock()
        var appliedFacts: [String] = []
        let governor = BackgroundFactApplyGovernor<Int, String>(
            tickCadence: .seconds(1),
            drainBudget: .milliseconds(4),
            clock: clock
        ) { _, fact in
            appliedFacts.append(fact)
        }
        governor.start()
        let acknowledgement = governor.enqueue("pending", for: 1)

        await governor.shutdown()

        #expect(await acknowledgement.result() == .applied)
        #expect(appliedFacts == ["pending"])
        #expect(clock.pendingSleepCount == 0)
    }
}
