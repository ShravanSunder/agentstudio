import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("EventBus.waitForFirst")
struct EventBusWaitForFirstTests {
    private enum TestFact: Equatable, Sendable, EventBusFactTopicProviding {
        case unrelated
        case matching

        var eventBusFactTopic: EventBusFactTopic {
            switch self {
            case .unrelated: EventBusFactTopic("test.unrelated")
            case .matching: EventBusFactTopic("test.matching")
            }
        }
    }

    @Test("fact interest filters before waitForFirst extraction")
    func waitForFirstForwardsFactInterest() async {
        let harness = EventBusHarness<TestFact>()
        let waitTask = Task {
            await harness.bus.waitForFirst(
                policy: .criticalUnbounded,
                subscriberName: "waitForFirstForwardsFactInterest",
                factInterest: .matching([EventBusFactTopic("test.matching")])
            ) { fact -> Bool? in
                fact == .matching ? true : nil
            }
        }

        await waitForBusSubscriberCount(harness.bus, atLeast: 1)
        await harness.post(.unrelated)
        let diagnosticsBeforeMatch = await harness.bus.diagnosticsSnapshot()
        #expect(diagnosticsBeforeMatch.activeSubscribers.first?.yieldedCount == 0)
        await harness.post(.matching)

        #expect(await waitTask.value == true)
    }

    // MARK: - Non-timeout variant

    @Test("returns first matching envelope")
    func waitForFirstReturnsMatch() async {
        let harness = EventBusHarness<Int>()

        let waitTask = Task {
            await harness.bus.waitForFirst(
                policy: .lossyNewest(BusSubscriberPolicy.standardLossyBufferLimit),
                subscriberName: "waitForFirstReturnsMatch"
            ) { value -> String? in
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
            await harness.bus.waitForFirst(
                policy: .lossyNewest(BusSubscriberPolicy.standardLossyBufferLimit),
                subscriberName: "waitForFirstReturnsNilOnCancellation"
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
        await assertBusDrained(harness.bus)
    }

    @Test("extracts and returns typed value")
    func waitForFirstExtractsValue() async {
        let harness = EventBusHarness<Int>()

        let waitTask = Task {
            await harness.bus.waitForFirst(
                policy: .lossyNewest(BusSubscriberPolicy.standardLossyBufferLimit),
                subscriberName: "waitForFirstExtractsValue"
            ) { value -> Int? in
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
                policy: .lossyNewest(BusSubscriberPolicy.standardLossyBufferLimit),
                subscriberName: "waitForFirstTimeoutReturnsMatchBeforeDeadline",
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
                policy: .lossyNewest(BusSubscriberPolicy.standardLossyBufferLimit),
                subscriberName: "waitForFirstTimeoutCancellationReturnsNil",
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
        await assertBusDrained(harness.bus)
    }
}
