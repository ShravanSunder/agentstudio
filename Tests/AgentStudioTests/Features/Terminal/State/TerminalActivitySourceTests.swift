import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Synchronization
import Testing

@testable import AgentStudioTerminal

@MainActor
private final class ActivityViewportReader {
    var text: String?
    private(set) var readCount = 0

    init(text: String?) {
        self.text = text
    }

    func read() -> TerminalViewportTextReadResult {
        readCount += 1
        guard let text else { return .empty }
        return .value(text)
    }
}

@MainActor
@Suite("Terminal activity source", .serialized)
struct TerminalActivitySourceTests {
    @Test("attended changed output reaches the activity source without a notification settle")
    func attendedChangedOutputCounts() async {
        let pushClock = TestPushClock()
        let output = MutableRawViewportTextBox("baseline line")
        let submitted = Mutex<[PaneActivityOccurrence]>([])
        let outcomeRecorder = OutcomeRecorder()
        let admittedInstant = ContinuousClock.now
        let admittedWallTime = Date(timeIntervalSince1970: 1000)
        let projector = TerminalActivityProjector(
            unseenQuietDuration: .seconds(1),
            clock: pushClock,
            continuousNow: { admittedInstant },
            wallNow: { admittedWallTime },
            activitySink: { occurrence in
                submitted.withLock { $0.append(occurrence) }
            }
        )
        await projector.configure(
            lastOutputLineReader: { _ in .value(output.read() ?? "") },
            outcomeSink: { outcomes in outcomeRecorder.record(outcomes) }
        )
        let paneId = UUIDv7.generate()
        let surfaceId = UUIDv7.generate()

        await projector.commandFinished(surfaceID: surfaceId, paneID: paneId)
        output.set("changed line")
        await projector.ingest(
            surfaceID: surfaceId,
            paneID: paneId,
            aggregate: aggregate(firstTotal: 100, latestTotal: 120),
            latestState: ScrollbarState(top: 110, bottom: 120, total: 120),
            context: .init(isAttended: true, isAgentClassified: false, outputBurstThreshold: 30)
        )
        await pushClock.waitForPendingSleepCount(exactly: 1)
        pushClock.advance(by: .seconds(1))
        await projector.activitySettled()

        #expect(submitted.withLock { $0.count } == 1)
        #expect(submitted.withLock { $0.first?.paneId } == paneId)
        #expect(submitted.withLock { $0.first?.orderingInstant } == admittedInstant)
        #expect(submitted.withLock { $0.first?.wallTime } == admittedWallTime)
        let notificationSettles = outcomeRecorder.outcomes.filter { outcome in
            if case .unseenActivitySettled = outcome { return true }
            return false
        }
        #expect(notificationSettles.count == 1)
        await projector.reset()
    }

    @Test("repeated or unreadable lines do not count; each attached surface gets its own baseline")
    func baselineAndNonActivityDispositions() async {
        let pushClock = TestPushClock()
        let reader = ActivityViewportReader(text: "first line")
        let submitted = Mutex<[PaneActivityOccurrence]>([])
        let outcomes = OutcomeRecorder()
        let projector = TerminalActivityProjector(
            unseenQuietDuration: .seconds(1),
            clock: pushClock,
            activitySink: { occurrence in submitted.withLock { $0.append(occurrence) } }
        )
        await projector.configure(
            lastOutputLineReader: { _ in reader.read() },
            outcomeSink: { batch in outcomes.record(batch) }
        )
        let paneId = UUIDv7.generate()
        let firstSurfaceId = UUIDv7.generate()

        await projector.commandFinished(surfaceID: firstSurfaceId, paneID: paneId)
        await projector.ingest(
            surfaceID: firstSurfaceId,
            paneID: paneId,
            aggregate: aggregate(firstTotal: 100, latestTotal: 120),
            latestState: ScrollbarState(top: 110, bottom: 120, total: 120),
            context: .init(isAttended: true, isAgentClassified: false, outputBurstThreshold: 30)
        )
        await pushClock.waitForPendingSleepCount(exactly: 1)
        pushClock.advance(by: .seconds(1))
        await projector.activitySettled()
        #expect(submitted.withLock { $0.isEmpty })

        reader.text = nil
        await projector.ingest(
            surfaceID: firstSurfaceId,
            paneID: paneId,
            aggregate: aggregate(firstTotal: 120, latestTotal: 140),
            latestState: ScrollbarState(top: 130, bottom: 140, total: 140),
            context: .init(isAttended: true, isAgentClassified: false, outputBurstThreshold: 30)
        )
        await pushClock.waitForPendingSleepCount(exactly: 1)
        pushClock.advance(by: .seconds(1))
        await projector.activitySettled()
        #expect(submitted.withLock { $0.isEmpty })

        let replacementSurfaceId = UUIDv7.generate()
        reader.text = "replacement baseline"
        await projector.commandFinished(surfaceID: replacementSurfaceId, paneID: paneId)
        #expect(submitted.withLock { $0.isEmpty })
        reader.text = "replacement changed"
        await projector.commandFinished(surfaceID: replacementSurfaceId, paneID: paneId)
        #expect(submitted.withLock { $0.count } == 1)
        let lastCommandSettle = outcomes.outcomes.compactMap { outcome -> TerminalSettledActivity? in
            guard case .unseenActivitySettled(_, _, let activity) = outcome else { return nil }
            return activity
        }.last
        #expect(lastCommandSettle?.rowsAdded == 0)
        await projector.reset()
    }

    @Test("the first quiet-settled readable line after each surface attach is a baseline")
    func quietSettlesEstablishEachSurfaceBaseline() async {
        let pushClock = TestPushClock()
        let reader = ActivityViewportReader(text: "first surface baseline")
        let submitted = Mutex<[PaneActivityOccurrence]>([])
        let projector = TerminalActivityProjector(
            unseenQuietDuration: .seconds(1),
            clock: pushClock,
            activitySink: { occurrence in submitted.withLock { $0.append(occurrence) } }
        )
        await projector.configure(lastOutputLineReader: { _ in reader.read() }, outcomeSink: { _ in })
        let paneId = UUIDv7.generate()
        let firstSurfaceId = UUIDv7.generate()

        await settleAttendedBurst(
            projector: projector,
            clock: pushClock,
            paneId: paneId,
            surfaceId: firstSurfaceId,
            firstTotal: 100,
            latestTotal: 120
        )
        #expect(submitted.withLock { $0.isEmpty })

        reader.text = "first surface changed"
        await settleAttendedBurst(
            projector: projector,
            clock: pushClock,
            paneId: paneId,
            surfaceId: firstSurfaceId,
            firstTotal: 120,
            latestTotal: 140
        )
        #expect(submitted.withLock { $0.count } == 1)

        reader.text = "replacement baseline"
        await settleAttendedBurst(
            projector: projector,
            clock: pushClock,
            paneId: paneId,
            surfaceId: UUIDv7.generate(),
            firstTotal: 140,
            latestTotal: 160
        )
        #expect(submitted.withLock { $0.count } == 1)
        await projector.reset()
    }

    @Test("an unattended burst shares one viewport read with its existing notification settle")
    func unattendedBurstReadsOnce() async {
        let pushClock = TestPushClock()
        let reader = ActivityViewportReader(text: "baseline")
        let closeReadMeasurements = Mutex<Int>(0)
        let submitted = Mutex<[PaneActivityOccurrence]>([])
        let outcomes = OutcomeRecorder()
        let projector = TerminalActivityProjector(
            unseenQuietDuration: .seconds(1),
            clock: pushClock,
            activitySink: { occurrence in submitted.withLock { $0.append(occurrence) } },
            closeReadDurationSink: { _ in closeReadMeasurements.withLock { $0 += 1 } }
        )
        await projector.configure(
            lastOutputLineReader: { _ in reader.read() },
            outcomeSink: { batch in outcomes.record(batch) }
        )
        let paneId = UUIDv7.generate()
        let surfaceId = UUIDv7.generate()
        await projector.commandFinished(surfaceID: surfaceId, paneID: paneId)
        #expect(reader.readCount == 1)

        reader.text = "unattended changed"
        await projector.ingest(
            surfaceID: surfaceId,
            paneID: paneId,
            aggregate: aggregate(firstTotal: 100, latestTotal: 120),
            latestState: ScrollbarState(top: 110, bottom: 120, total: 120),
            context: .init(isAttended: false, isAgentClassified: false, outputBurstThreshold: 30)
        )
        await pushClock.waitForPendingSleepCount(exactly: 1)
        pushClock.advance(by: .seconds(1))
        await projector.activitySettled()

        #expect(reader.readCount == 2)
        #expect(closeReadMeasurements.withLock { $0 } == 1)
        #expect(submitted.withLock { $0.count } == 1)
        let notificationSettles = outcomes.outcomes.compactMap { outcome -> TerminalSettledActivity? in
            guard case .unseenActivitySettled(_, _, let activity) = outcome else { return nil }
            return activity
        }
        #expect(notificationSettles.count == 2)
        #expect(notificationSettles[1].lastOutputLine == "unattended changed")
        await projector.reset()
    }

    private func aggregate(firstTotal: Int, latestTotal: Int) -> TerminalScrollbarActivityAggregate {
        var aggregate = TerminalScrollbarActivityAggregate(
            state: ScrollbarState(top: firstTotal - 10, bottom: firstTotal, total: firstTotal),
            observedAtMilliseconds: 1000
        )
        aggregate.merge(
            state: ScrollbarState(top: latestTotal - 10, bottom: latestTotal, total: latestTotal),
            observedAtMilliseconds: 1100
        )
        return aggregate
    }

    private func settleAttendedBurst(
        projector: TerminalActivityProjector,
        clock: TestPushClock,
        paneId: UUID,
        surfaceId: UUID,
        firstTotal: Int,
        latestTotal: Int
    ) async {
        await projector.ingest(
            surfaceID: surfaceId,
            paneID: paneId,
            aggregate: aggregate(firstTotal: firstTotal, latestTotal: latestTotal),
            latestState: ScrollbarState(top: latestTotal - 10, bottom: latestTotal, total: latestTotal),
            context: .init(isAttended: true, isAgentClassified: false, outputBurstThreshold: 30)
        )
        await clock.waitForPendingSleepCount(exactly: 1)
        clock.advance(by: .seconds(1))
        await projector.activitySettled()
    }
}
