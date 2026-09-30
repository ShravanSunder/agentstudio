import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Synchronization
import Testing

@testable import AgentStudioRepoExplorer

@Suite("Repo Explorer projection deadline worker")
struct RepoExplorerProjectionDeadlineTests {
    @Test("Panes deadlines use the captured continuous reference after a wall step")
    func paneDeadlineIgnoresWallClockStep() async {
        let pushClock = TestPushClock()
        let requestedDurations = AsyncStream.makeStream(of: Duration.self)
        let referenceInstant = ContinuousClock.now
        let worker = RepoExplorerProjectionWorker(
            deadlineDelay: AsyncDelay { duration in
                requestedDurations.continuation.yield(duration)
                try await pushClock.sleep(for: duration)
            },
            deadlineNow: { Date(timeIntervalSince1970: 900) },
            continuousNow: { referenceInstant.advanced(by: .seconds(5)) }
        )
        let deadline = RepoExplorerPreparedPresentationDeadline(
            deadline: Date(timeIntervalSince1970: 1010),
            paneIDs: [UUIDv7.generate()],
            repositoryIDs: [],
            referenceInstant: referenceInstant,
            referenceDate: Date(timeIntervalSince1970: 1000)
        )

        await worker.updatePresentationDeadline(deadline, demanded: true, generation: 1)
        var iterator = requestedDurations.stream.makeAsyncIterator()
        #expect(await iterator.next() == .seconds(5))
        await pushClock.waitForPendingSleepCount(exactly: 1)
        await worker.updatePresentationDeadline(nil, demanded: false, generation: 2)
        await pushClock.waitForPendingSleepCount(exactly: 0)
        requestedDurations.continuation.finish()
    }

    @Test("demand removal cancels the wait; one current deadline fires; stale generations are ignored")
    func demandAndGenerationOwnOneDeadline() async {
        let pushClock = TestPushClock()
        let firedGenerations = Mutex<[Int]>([])
        let fireEvents = AsyncStream.makeStream(of: Int.self)
        let deadline = RepoExplorerPreparedPresentationDeadline(
            deadline: Date(timeIntervalSince1970: 1010),
            paneIDs: [UUIDv7.generate()],
            repositoryIDs: []
        )
        let worker = RepoExplorerProjectionWorker(
            deadlineDelay: .clock(pushClock),
            deadlineNow: { Date(timeIntervalSince1970: 1000) },
            onDeadline: { generation, _ in
                firedGenerations.withLock { $0.append(generation) }
                fireEvents.continuation.yield(generation)
            }
        )

        await worker.updatePresentationDeadline(deadline, demanded: true, generation: 1)
        await pushClock.waitForPendingSleepCount(exactly: 1)
        await worker.updatePresentationDeadline(nil, demanded: false, generation: 2)
        await pushClock.waitForPendingSleepCount(exactly: 0)
        pushClock.advance(by: .seconds(10))
        #expect(firedGenerations.withLock { $0.isEmpty })

        await worker.updatePresentationDeadline(deadline, demanded: true, generation: 3)
        await pushClock.waitForPendingSleepCount(exactly: 1)
        var iterator = fireEvents.stream.makeAsyncIterator()
        pushClock.advance(by: .seconds(10))
        #expect(await iterator.next() == 3)
        #expect(firedGenerations.withLock { $0 } == [3])
        #expect(await worker.hasPendingPresentationDeadline() == false)

        await worker.updatePresentationDeadline(deadline, demanded: true, generation: 2)
        #expect(await worker.hasPendingPresentationDeadline() == false)
        fireEvents.continuation.finish()
    }
}
