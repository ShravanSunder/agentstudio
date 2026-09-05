import Foundation
import Testing

/// Proof that `assertEventuallyMain`/`assertEventuallyAsync` run to their `timeout` wall-clock
/// bound by default instead of stopping after a fixed MainActor yield count. Before the fix, both
/// helpers defaulted `maxTurns` to 200, so a condition that only becomes true well past 200 polls
/// (as happens when concurrent suites in the fast lane steal this suite's yields) timed out even
/// though most of the 5-second `timeout` budget remained unused.
@Suite("EventBusHarness eventually-wait defaults")
struct EventBusHarnessEventuallyWaitTests {
    @MainActor
    private final class MainActorCallCounter {
        private(set) var callCount = 0

        func incrementAndCheck(threshold: Int) -> Bool {
            callCount += 1
            return callCount >= threshold
        }
    }

    private actor CallCounter {
        private(set) var callCount = 0

        func incrementAndCheck(threshold: Int) -> Bool {
            callCount += 1
            return callCount >= threshold
        }
    }

    @Test("assertEventuallyMain with default maxTurns runs well past 200 polls")
    @MainActor
    func assertEventuallyMainDefaultMaxTurnsRunsPastTwoHundredPolls() async {
        let counter = MainActorCallCounter()

        await assertEventuallyMain("condition true only on the 1000th poll") {
            counter.incrementAndCheck(threshold: 1000)
        }

        #expect(counter.callCount == 1000)
    }

    @Test("assertEventuallyAsync with default maxTurns runs well past 200 polls")
    func assertEventuallyAsyncDefaultMaxTurnsRunsPastTwoHundredPolls() async {
        let counter = CallCounter()

        await assertEventuallyAsync("condition true only on the 1000th poll") {
            await counter.incrementAndCheck(threshold: 1000)
        }

        #expect(await counter.callCount == 1000)
    }
}
