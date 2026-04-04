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

        await harness.post(1)
        await Task.yield()
        waitTask.cancel()

        let result = await waitTask.value
        #expect(result == nil)
    }

    @Test("extracts and returns typed value")
    func waitForFirstExtractsValue() async {
        let harness = EventBusHarness<String>()

        let waitTask = Task {
            await harness.bus.waitForFirst { value -> Int? in
                Int(value)
            }
        }

        await harness.post("hello")
        await harness.post("42")

        let result = await waitTask.value
        #expect(result == 42)
    }

    // MARK: - Timeout variant

    @Test("timeout returns nil when no match arrives")
    func waitForFirstTimeoutExpiresReturnsNil() async {
        let harness = EventBusHarness<Int>()

        let result = await harness.bus.waitForFirst(
            timeout: .milliseconds(50)
        ) { value -> String? in
            value == 999 ? "found" : nil
        }

        #expect(result == nil)
    }

    @Test("timeout returns match when it arrives before deadline")
    func waitForFirstTimeoutReturnsMatchBeforeDeadline() async {
        let harness = EventBusHarness<Int>()

        let waitTask = Task {
            await harness.bus.waitForFirst(
                timeout: .seconds(5)
            ) { value -> String? in
                value == 42 ? "found" : nil
            }
        }

        await harness.post(42)

        let result = await waitTask.value
        #expect(result == "found")
    }

    @Test("timeout with no events returns nil without blocking")
    func waitForFirstTimeoutNoEventsReturnsNil() async {
        let harness = EventBusHarness<Int>()

        let result = await harness.bus.waitForFirst(
            timeout: .milliseconds(50)
        ) { value -> String? in
            value == 42 ? "found" : nil
        }

        #expect(result == nil)
    }
}
