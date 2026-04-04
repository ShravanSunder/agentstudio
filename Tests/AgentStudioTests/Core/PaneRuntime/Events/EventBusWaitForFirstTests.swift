import Foundation
import Testing

@testable import AgentStudio

@Suite("EventBus.waitForFirst")
struct EventBusWaitForFirstTests {

    // MARK: - Non-timeout variant

    @Test("returns first matching envelope")
    func waitForFirstReturnsMatch() async {
        let harness = EventBusHarness<Int>()

        let waitTask = Task {
            await harness.bus.waitForFirst { value -> String? in
                value == 42 ? "found" : nil
            }
        }

        await assertEventuallyAsync("subscriber registered", maxTurns: 50) {
            await harness.bus.subscriberCount > 0
        }

        await harness.post(1)
        await harness.post(2)
        await harness.post(42)

        let result = await waitTask.value
        #expect(result == "found")
    }

    @Test("returns nil when task is cancelled")
    func waitForFirstReturnsNilOnCancellation() async {
        let harness = EventBusHarness<Int>()

        let waitTask = Task {
            await harness.bus.waitForFirst { value -> String? in
                value == 999 ? "found" : nil
            }
        }

        await assertEventuallyAsync("subscriber registered", maxTurns: 50) {
            await harness.bus.subscriberCount > 0
        }

        waitTask.cancel()

        let result = await waitTask.value
        #expect(result == nil)
    }

    @Test("extracts and returns typed value")
    func waitForFirstExtractsValue() async {
        let harness = EventBusHarness<Int>()

        let waitTask = Task {
            await harness.bus.waitForFirst { value -> Int? in
                value > 10 ? value * 2 : nil
            }
        }

        await assertEventuallyAsync("subscriber registered", maxTurns: 50) {
            await harness.bus.subscriberCount > 0
        }

        await harness.post(5)
        await harness.post(20)

        let result = await waitTask.value
        #expect(result == 40)
    }

    // MARK: - Timeout variant

    @Test("timeout returns match when it arrives before deadline")
    func waitForFirstTimeoutReturnsMatchBeforeDeadline() async {
        let harness = EventBusHarness<Int>()

        let waitTask = Task {
            await harness.bus.waitForFirst(
                timeout: .seconds(10)
            ) { value -> String? in
                value == 42 ? "found" : nil
            }
        }

        await assertEventuallyAsync("subscriber registered", maxTurns: 50) {
            await harness.bus.subscriberCount > 0
        }

        await harness.post(42)

        let result = await waitTask.value
        #expect(result == "found")
    }

    @Test("timeout cancellation returns nil")
    func waitForFirstTimeoutCancellationReturnsNil() async {
        let harness = EventBusHarness<Int>()

        let waitTask = Task {
            await harness.bus.waitForFirst(
                timeout: .seconds(10)
            ) { value -> String? in
                value == 999 ? "found" : nil
            }
        }

        await assertEventuallyAsync("subscriber registered", maxTurns: 50) {
            await harness.bus.subscriberCount > 0
        }

        waitTask.cancel()

        let result = await waitTask.value
        #expect(result == nil)
    }
}
