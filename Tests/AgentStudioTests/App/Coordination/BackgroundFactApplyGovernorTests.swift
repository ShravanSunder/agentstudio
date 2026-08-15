import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioInfrastructure
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
        #expect(await acknowledgements[0].result() == .applied)
        #expect(await acknowledgements[1].result() == .applied)
        #expect(appliedKeys == [1, 2])

        await clock.waitForPendingSleepCount(exactly: 1)
        clock.advance(by: .milliseconds(10))
        #expect(await acknowledgements[2].result() == .applied)
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

    @Test("drain telemetry separates awaited preparation from MainActor-held commit")
    func drainTelemetrySeparatesAwaitedAndMainActorHeldTime() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory.appending(
            path: "apply-governor-decomposition-\(UUIDv7.generate().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: traceDirectory) }
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "apply-governor-decomposition",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 938,
            timeUnixNano: { 938 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: traceRuntime)
        let clock = TestPushClock()
        var appliedFacts: [String] = []
        let governor = BackgroundFactApplyGovernor<Int, String>(
            tickCadence: .zero,
            drainBudget: .milliseconds(20),
            clock: clock,
            performanceTraceRecorder: recorder,
            prepareApply: { _, fact in
                try? await clock.sleep(for: .milliseconds(10))
                return { @MainActor in
                    appliedFacts.append(fact)
                    clock.advance(by: .milliseconds(2))
                }
            }
        )
        governor.start()
        let acknowledgement = governor.enqueue("pending", for: 1)

        await clock.waitForPendingSleepCount(exactly: 1)
        clock.advance(by: .milliseconds(10))
        #expect(await acknowledgement.result() == .applied)
        await governor.shutdown()
        try await recorder.drain()

        #expect(appliedFacts == ["pending"])
        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"agentstudio.performance.apply_governor.awaited_ms\":10"))
        #expect(contents.contains("\"agentstudio.performance.apply_governor.mainactor_held_ms\":2"))
        #expect(contents.contains("\"agentstudio.performance.apply_governor.max_single_fact_ms\":12"))
    }
}
