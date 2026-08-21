import Foundation
import Observation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

private final class PaneActivityStatusObservationCounter: @unchecked Sendable {
    private(set) var count = 0
    private(set) var didFire = false

    func record() {
        didFire = true
        count += 1
    }
}

@MainActor
private func observeStatus(
    for paneId: UUID,
    on atom: PaneActivityStatusAtom,
    counter: PaneActivityStatusObservationCounter
) {
    withObservationTracking {
        _ = atom.status(for: paneId)
    } onChange: {
        MainActor.assumeIsolated {
            counter.record()
            observeStatus(for: paneId, on: atom, counter: counter)
        }
    }
}

@MainActor
@Suite(.serialized)
struct PaneActivityStatusAtomTests {
    @Test("settled activity with a real line publishes the fact")
    func settledActivityWithRealLinePublishesFact() {
        let currentDate = Date(timeIntervalSince1970: 0)
        let atom = PaneActivityStatusAtom(now: { currentDate })
        let paneId = UUID()

        let didPublish = atom.recordSettledActivity(paneId: paneId, lastOutputLine: "seam-live-proof")

        #expect(didPublish)
        #expect(atom.status(for: paneId)?.lastOutputLine == "seam-live-proof")
        #expect(atom.status(for: paneId)?.observedAt == currentDate)
    }

    @Test("nil or empty last output line publishes nothing")
    func nilOrEmptyLastOutputLinePublishesNothing() {
        let atom = PaneActivityStatusAtom(now: { Date(timeIntervalSince1970: 0) })
        let paneId = UUID()

        #expect(!atom.recordSettledActivity(paneId: paneId, lastOutputLine: nil))
        #expect(!atom.recordSettledActivity(paneId: paneId, lastOutputLine: ""))
        #expect(atom.status(for: paneId) == nil)
    }

    @Test("a settle within the 10s window is dropped, not deferred")
    func settleWithinWindowIsDropped() {
        var currentDate = Date(timeIntervalSince1970: 1000)
        let atom = PaneActivityStatusAtom(
            minimumPublishInterval: .seconds(10),
            now: { currentDate }
        )
        let paneId = UUID()

        #expect(atom.recordSettledActivity(paneId: paneId, lastOutputLine: "first line"))
        currentDate = currentDate.addingTimeInterval(9.999)
        let didPublishWithinWindow = atom.recordSettledActivity(paneId: paneId, lastOutputLine: "second line")

        #expect(!didPublishWithinWindow)
        // The dropped update never lands: the fact still reads the first line, not the second.
        #expect(atom.status(for: paneId)?.lastOutputLine == "first line")
    }

    @Test("a settle at or after the 10s window publishes the latest line")
    func settleAfterWindowPublishes() {
        var currentDate = Date(timeIntervalSince1970: 1000)
        let atom = PaneActivityStatusAtom(
            minimumPublishInterval: .seconds(10),
            now: { currentDate }
        )
        let paneId = UUID()

        #expect(atom.recordSettledActivity(paneId: paneId, lastOutputLine: "first line"))
        currentDate = currentDate.addingTimeInterval(10)
        let didPublishAfterWindow = atom.recordSettledActivity(paneId: paneId, lastOutputLine: "second line")

        #expect(didPublishAfterWindow)
        #expect(atom.status(for: paneId)?.lastOutputLine == "second line")
    }

    @Test("the 10s cadence is scoped per pane, not global")
    func cadenceIsScopedPerPane() {
        let currentDate = Date(timeIntervalSince1970: 1000)
        let atom = PaneActivityStatusAtom(minimumPublishInterval: .seconds(10), now: { currentDate })
        let firstPaneId = UUID()
        let secondPaneId = UUID()

        #expect(atom.recordSettledActivity(paneId: firstPaneId, lastOutputLine: "pane one"))
        // A different pane, at the same instant, is not rate-limited by the first pane's publish.
        #expect(atom.recordSettledActivity(paneId: secondPaneId, lastOutputLine: "pane two"))
    }

    @Test("an unchanged line for the same pane is a no-op via AtomFamily's equal-write suppression")
    func unchangedLineIsEqualWriteSuppressed() {
        var currentDate = Date(timeIntervalSince1970: 1000)
        let atom = PaneActivityStatusAtom(minimumPublishInterval: .seconds(10), now: { currentDate })
        let paneId = UUID()
        let counter = PaneActivityStatusObservationCounter()

        #expect(atom.recordSettledActivity(paneId: paneId, lastOutputLine: "same line"))
        observeStatus(for: paneId, on: atom, counter: counter)

        currentDate = currentDate.addingTimeInterval(20)
        let didPublishRepeatedLine = atom.recordSettledActivity(paneId: paneId, lastOutputLine: "same line")

        #expect(!didPublishRepeatedLine)
        #expect(!counter.didFire)
    }

    @Test("keyed readers wake only for the touched pane")
    func keyedReadersWakeOnlyForTouchedPane() {
        let currentDate = Date(timeIntervalSince1970: 1000)
        let atom = PaneActivityStatusAtom(minimumPublishInterval: .seconds(10), now: { currentDate })
        let observedPaneId = UUID()
        let otherPaneId = UUID()
        let observedCounter = PaneActivityStatusObservationCounter()
        let otherCounter = PaneActivityStatusObservationCounter()

        observeStatus(for: observedPaneId, on: atom, counter: observedCounter)
        observeStatus(for: otherPaneId, on: atom, counter: otherCounter)

        atom.recordSettledActivity(paneId: observedPaneId, lastOutputLine: "only this pane changed")

        #expect(observedCounter.count == 1)
        #expect(!otherCounter.didFire)
    }
}
