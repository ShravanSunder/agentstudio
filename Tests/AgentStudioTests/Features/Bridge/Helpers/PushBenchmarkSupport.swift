import Foundation
import Testing

enum PushBenchmarkMode: String, Sendable {
    case off
    case benchmark

    static let environmentKey = "AGENT_STUDIO_BENCHMARK_MODE"

    static func parse(rawValue: String?) -> Self {
        guard let rawValue else {
            return .off
        }

        let normalizedMode = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedMode.isEmpty else {
            return .off
        }
        switch normalizedMode {
        case "benchmark":
            return .benchmark
        case "off":
            return .off
        default:
            return .off
        }
    }

    static var current: Self {
        parse(rawValue: ProcessInfo.processInfo.environment[environmentKey])
    }
}

struct PushBenchmarkStats: Sendable {
    let durations: [Duration]
    let payloadBytes: [Int]
    let initialPayloadBytes: Int

    private var sortedDurationsNanoseconds: [Int64] {
        durations.map(\.benchmarkNanoseconds).sorted()
    }

    var count: Int { durations.count }

    var min: Duration {
        Duration.nanoseconds(sortedDurationsNanoseconds.first ?? 0)
    }

    var max: Duration {
        Duration.nanoseconds(sortedDurationsNanoseconds.last ?? 0)
    }

    var median: Duration {
        guard !sortedDurationsNanoseconds.isEmpty else {
            return .zero
        }
        let medianIndex = sortedDurationsNanoseconds.count / 2
        return Duration.nanoseconds(sortedDurationsNanoseconds[medianIndex])
    }

    var p95: Duration {
        guard !sortedDurationsNanoseconds.isEmpty else {
            return .zero
        }
        let p95Index = Int((Double(sortedDurationsNanoseconds.count - 1) * 0.95).rounded(.up))
        let clampedIndex = Swift.min(Swift.max(p95Index, 0), sortedDurationsNanoseconds.count - 1)
        return Duration.nanoseconds(sortedDurationsNanoseconds[clampedIndex])
    }

    var average: Duration {
        guard !sortedDurationsNanoseconds.isEmpty else {
            return .zero
        }
        let total = sortedDurationsNanoseconds.reduce(0, +)
        return Duration.nanoseconds(total / Int64(sortedDurationsNanoseconds.count))
    }

    func summary(for benchmarkName: String) -> String {
        """
        [PushBenchmark] \(benchmarkName) count=\(count), initialPayload=\(initialPayloadBytes)B, \
        min=\(min.formattedBenchmarkMilliseconds), median=\(median.formattedBenchmarkMilliseconds), \
        p95=\(p95.formattedBenchmarkMilliseconds), max=\(max.formattedBenchmarkMilliseconds), avg=\(average.formattedBenchmarkMilliseconds), \
        deltaMin=\(payloadBytes.min() ?? 0)B, deltaMax=\(payloadBytes.max() ?? 0)B
        """
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func assertPushBenchmarkThreshold(
    mode: PushBenchmarkMode,
    benchmarkName: String,
    measured: Duration,
    threshold: Duration
) {
    let measuredMilliseconds = measured.formattedBenchmarkMilliseconds
    let thresholdMilliseconds = threshold.formattedBenchmarkMilliseconds
    switch mode {
    case .benchmark:
        let status = measured <= threshold ? "OK" : "WARN"
        print(
            "[PushBenchmark] \(status) \(benchmarkName) measured=\(measuredMilliseconds), threshold=\(thresholdMilliseconds) (non-failing)"
        )
    case .off:
        break
    }
}

extension Duration {
    var benchmarkNanoseconds: Int64 {
        let components = components
        let wholeSeconds = Int64(components.seconds)
        let subsecondNanoseconds = Int64(components.attoseconds / 1_000_000_000)
        let secondsAsNanoseconds = wholeSeconds.multipliedReportingOverflow(by: 1_000_000_000)
        if secondsAsNanoseconds.overflow {
            return subsecondNanoseconds
        }
        return secondsAsNanoseconds.partialValue + subsecondNanoseconds
    }

    var formattedBenchmarkMilliseconds: String {
        let nanoseconds = benchmarkNanoseconds
        return String(format: "%.3fms", Double(nanoseconds) / 1_000_000.0)
    }
}
