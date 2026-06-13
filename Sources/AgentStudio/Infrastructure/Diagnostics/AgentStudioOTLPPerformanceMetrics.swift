import Foundation
import Metrics

final class AgentStudioOTLPPerformanceMetrics: @unchecked Sendable {
    private let factory: any MetricsFactory
    private let lock = NSLock()
    private var eventCounters: [String: Counter] = [:]
    private var elapsedRecorders: [String: Recorder] = [:]
    private var numericGauges: [MetricGaugeKey: Gauge] = [:]

    init(factory: any MetricsFactory) {
        self.factory = factory
    }

    func record(_ record: AgentStudioOTLPProjectedLogRecord) {
        guard let metricEvent = AgentStudioOTLPPerformanceMetricEvent(record: record) else { return }

        lock.withLock {
            counter(for: metricEvent.eventName).increment()

            if let elapsedMilliseconds = metricEvent.elapsedMilliseconds {
                recorder(for: metricEvent.eventName).record(elapsedMilliseconds)
            }

            for sample in metricEvent.samples {
                gauge(for: sample).record(sample.value)
            }
        }
    }

    private func counter(for eventName: String) -> Counter {
        if let counter = eventCounters[eventName] {
            return counter
        }

        let counter = Counter(
            label: "agentstudio_performance_events_total",
            dimensions: [("event", eventName)],
            factory: factory
        )
        eventCounters[eventName] = counter
        return counter
    }

    private func recorder(for eventName: String) -> Recorder {
        if let recorder = elapsedRecorders[eventName] {
            return recorder
        }

        let recorder = Recorder(
            label: "agentstudio_performance_event_elapsed_ms",
            dimensions: [("event", eventName)],
            factory: factory
        )
        elapsedRecorders[eventName] = recorder
        return recorder
    }

    private func gauge(for sample: AgentStudioOTLPPerformanceMetricSample) -> Gauge {
        let key = MetricGaugeKey(eventName: sample.eventName, label: sample.label)
        if let gauge = numericGauges[key] {
            return gauge
        }

        let gauge = Gauge(
            label: sample.label,
            dimensions: [("event", sample.eventName)],
            factory: factory
        )
        numericGauges[key] = gauge
        return gauge
    }
}

struct AgentStudioOTLPPerformanceMetricEvent: Equatable, Sendable {
    let eventName: String
    let elapsedMilliseconds: Double?
    let samples: [AgentStudioOTLPPerformanceMetricSample]

    init?(record: AgentStudioOTLPProjectedLogRecord) {
        guard record.body.hasPrefix("performance.") else { return nil }

        self.eventName = record.body
        self.elapsedMilliseconds = Self.doubleValue(
            record.attributes["agentstudio.performance.elapsed_ms"]
        )
        self.samples = record.attributes.compactMap { key, value in
            guard key != "agentstudio.performance.elapsed_ms" else { return nil }
            guard let numericValue = Self.doubleValue(value) else { return nil }
            guard let metricLabel = Self.metricLabel(for: key) else { return nil }
            return AgentStudioOTLPPerformanceMetricSample(
                eventName: record.body,
                label: metricLabel,
                value: numericValue
            )
        }
        .sorted { left, right in
            if left.label == right.label {
                return left.eventName < right.eventName
            }
            return left.label < right.label
        }
    }

    private static func doubleValue(_ value: AgentStudioTraceValue?) -> Double? {
        switch value {
        case .double(let doubleValue):
            guard doubleValue.isFinite else { return nil }
            return doubleValue
        case .int(let intValue):
            return Double(intValue)
        case .bool(let boolValue):
            return boolValue ? 1 : 0
        case .string, .stringArray, .none:
            return nil
        }
    }

    private static func metricLabel(for attributeKey: String) -> String? {
        guard attributeKey.hasPrefix("agentstudio.performance.") else { return nil }

        let suffix = String(attributeKey.dropFirst("agentstudio.performance.".count))
        guard !suffix.isEmpty else { return nil }

        let sanitized = suffix.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "_"
        }
        .reduce(into: "") { partialResult, character in
            if character == "_", partialResult.last == "_" {
                return
            }
            partialResult.append(character)
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        guard !sanitized.isEmpty else { return nil }
        return "agentstudio_performance_\(sanitized)"
    }
}

struct AgentStudioOTLPPerformanceMetricSample: Equatable, Sendable {
    let eventName: String
    let label: String
    let value: Double
}

private struct MetricGaugeKey: Hashable {
    let eventName: String
    let label: String
}
