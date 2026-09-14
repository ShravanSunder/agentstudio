import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@Suite("Repository retention scheduler")
struct RepositoryRetentionSchedulerTests {
    @Test("invalidations during validation retain only the latest pending deadline")
    func validationCoalescesPendingDeadlines() async {
        let clock = TestPushClock()
        let recorder = RetentionDeadlineRecorder(suspendFirst: true)
        let scheduler = RepositoryRetentionScheduler(clock: clock) { await recorder.record() }
        await scheduler.schedule(after: .seconds(1))
        await clock.waitForPendingSleepCount(exactly: 1)
        clock.advance(by: .seconds(1))
        await assertEventuallyAsync("first retention validation is suspended") { await recorder.isSuspended }

        await scheduler.schedule(after: .seconds(10))
        await scheduler.schedule(after: .seconds(20))
        #expect(clock.pendingSleepCount == 0)
        #expect(await recorder.fireCount == 1)
        await recorder.releaseValidation()
        await clock.waitForPendingSleepCount(exactly: 1)
        clock.advance(by: .seconds(19))
        #expect(await recorder.fireCount == 1)
        clock.advance(by: .seconds(1))
        await assertEventuallyAsync("latest pending deadline fires once") { await recorder.fireCount == 2 }

        await scheduler.shutdown()
        #expect(clock.pendingSleepCount == 0)
    }

    @Test("one deadline is replaced and cancellation leaves no sleeper")
    func replacementKeepsOneDeadlineAndShutdownJoinsIt() async {
        let clock = TestPushClock()
        let recorder = RetentionDeadlineRecorder()
        let scheduler = RepositoryRetentionScheduler(clock: clock) { await recorder.record() }
        await scheduler.schedule(after: .seconds(30))
        await clock.waitForPendingSleepCount(exactly: 1)
        await scheduler.schedule(after: .seconds(60))
        await clock.waitForPendingSleepCount(exactly: 1)
        clock.advance(by: .seconds(30))
        #expect(await recorder.fireCount == 0)
        clock.advance(by: .seconds(30))
        await recorder.waitForFirstFire()
        #expect(await recorder.fireCount == 1)
        await scheduler.shutdown()
        #expect(clock.pendingSleepCount == 0)
    }
}

private actor RetentionDeadlineRecorder {
    private let suspendFirst: Bool
    private var validationContinuation: CheckedContinuation<Void, Never>?
    private(set) var isSuspended = false
    private(set) var fireCount = 0
    private var waiter: CheckedContinuation<Void, Never>?
    init(suspendFirst: Bool = false) { self.suspendFirst = suspendFirst }
    func record() async {
        fireCount += 1
        waiter?.resume()
        waiter = nil
        if suspendFirst && fireCount == 1 {
            await withCheckedContinuation {
                validationContinuation = $0
                isSuspended = true
            }
        }
    }
    func releaseValidation() {
        validationContinuation?.resume()
        validationContinuation = nil
        isSuspended = false
    }
    func waitForFirstFire() async {
        guard fireCount == 0 else { return }
        await withCheckedContinuation { waiter = $0 }
    }
}
