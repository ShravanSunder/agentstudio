import Foundation
import Testing

@Suite(.serialized)
struct PushBenchmarkSupportTests {

    @Test
    func test_modeParsing_isDeterministic() {
        #expect(PushBenchmarkMode.parse(rawValue: nil) == .off)
        #expect(PushBenchmarkMode.parse(rawValue: "benchmark") == .benchmark)
        #expect(PushBenchmarkMode.parse(rawValue: " BENCH ") == .benchmark)
        #expect(PushBenchmarkMode.parse(rawValue: "strict") == .benchmark)
        #expect(PushBenchmarkMode.parse(rawValue: "warn") == .benchmark)
        #expect(PushBenchmarkMode.parse(rawValue: "off") == .off)
        #expect(PushBenchmarkMode.parse(rawValue: "unknown-value") == .off)
    }

    @Test
    func test_stats_medianAndP95_areDeterministic() {
        let stats = PushBenchmarkStats(
            durations: [
                .nanoseconds(9),
                .nanoseconds(1),
                .nanoseconds(5),
                .nanoseconds(4)
            ],
            payloadBytes: [20, 10, 40, 30],
            initialPayloadBytes: 100
        )

        #expect(stats.count == 4)
        #expect(stats.min == .nanoseconds(1))
        #expect(stats.median == .nanoseconds(5))
        #expect(stats.p95 == .nanoseconds(9))
        #expect(stats.max == .nanoseconds(9))
        #expect(stats.average == .nanoseconds(4))
    }

    @Test
    func test_stats_summary_isStable() {
        let stats = PushBenchmarkStats(
            durations: [
                .milliseconds(3),
                .milliseconds(1),
                .milliseconds(2)
            ],
            payloadBytes: [110, 90, 105],
            initialPayloadBytes: 500
        )

        let summary = stats.summary(for: "single-file incremental")
        #expect(
            summary
                == "[PushBenchmark] single-file incremental count=3, initialPayload=500B, min=1.000ms, median=2.000ms, p95=3.000ms, max=3.000ms, avg=2.000ms, deltaMin=90B, deltaMax=110B"
        )
    }

    @Test
    func test_stats_emptySamples_areZeroed() {
        let stats = PushBenchmarkStats(
            durations: [],
            payloadBytes: [],
            initialPayloadBytes: 0
        )

        #expect(stats.count == 0)
        #expect(stats.min == .zero)
        #expect(stats.median == .zero)
        #expect(stats.p95 == .zero)
        #expect(stats.max == .zero)
        #expect(stats.average == .zero)
        #expect(
            stats.summary(for: "empty")
                == "[PushBenchmark] empty count=0, initialPayload=0B, min=0.000ms, median=0.000ms, p95=0.000ms, max=0.000ms, avg=0.000ms, deltaMin=0B, deltaMax=0B"
        )
    }
}
