import Foundation
import Metrics

final class AgentStudioOTLPPerformanceMetrics: @unchecked Sendable {
    private let factory: any MetricsFactory
    private let lock = NSLock()
    private var eventCounters: [MetricInstrumentKey: Counter] = [:]
    private var elapsedRecorders: [MetricInstrumentKey: Recorder] = [:]
    private var numericGauges: [MetricGaugeKey: Gauge] = [:]

    init(factory: any MetricsFactory) {
        self.factory = factory
    }

    func record(_ record: AgentStudioOTLPProjectedLogRecord) {
        guard let metricEvent = AgentStudioOTLPPerformanceMetricEvent(record: record) else { return }

        lock.withLock {
            counter(for: metricEvent).increment()

            if let elapsedMilliseconds = metricEvent.elapsedMilliseconds {
                recorder(for: metricEvent).record(elapsedMilliseconds)
            }

            for sample in metricEvent.samples {
                gauge(for: sample).record(sample.value)
            }
        }
    }

    private func counter(for event: AgentStudioOTLPPerformanceMetricEvent) -> Counter {
        let key = MetricInstrumentKey(eventName: event.eventName, dimensions: event.dimensions)
        if let counter = eventCounters[key] {
            return counter
        }

        let counter = Counter(
            label: "agentstudio_performance_events_total",
            dimensions: event.metricsDimensions,
            factory: factory
        )
        eventCounters[key] = counter
        return counter
    }

    private func recorder(for event: AgentStudioOTLPPerformanceMetricEvent) -> Recorder {
        let key = MetricInstrumentKey(eventName: event.eventName, dimensions: event.dimensions)
        if let recorder = elapsedRecorders[key] {
            return recorder
        }

        let recorder = Recorder(
            label: "agentstudio_performance_event_elapsed_ms",
            dimensions: event.metricsDimensions,
            factory: factory
        )
        elapsedRecorders[key] = recorder
        return recorder
    }

    private func gauge(for sample: AgentStudioOTLPPerformanceMetricSample) -> Gauge {
        let key = MetricGaugeKey(
            eventName: sample.eventName,
            dimensions: sample.dimensions,
            label: sample.label
        )
        if let gauge = numericGauges[key] {
            return gauge
        }

        let gauge = Gauge(
            label: sample.label,
            dimensions: sample.metricsDimensions,
            factory: factory
        )
        numericGauges[key] = gauge
        return gauge
    }
}

struct AgentStudioOTLPPerformanceMetricEvent: Equatable, Sendable {
    let eventName: String
    let dimensions: [AgentStudioOTLPMetricDimension]
    let elapsedMilliseconds: Double?
    let samples: [AgentStudioOTLPPerformanceMetricSample]

    var metricsDimensions: [(String, String)] {
        dimensions.map { ($0.name, $0.value) }
    }

    init?(record: AgentStudioOTLPProjectedLogRecord) {
        guard record.body.hasPrefix("performance.") else { return nil }
        if record.body.hasPrefix("performance.bridge.") {
            guard Self.hasCompleteBridgeMetricTaxonomy(record) else { return nil }
        }

        let dimensions = Self.metricDimensions(for: record)
        self.eventName = record.body
        self.dimensions = dimensions
        self.elapsedMilliseconds = Self.doubleValue(
            record.attributes["agentstudio.performance.elapsed_ms"]
        )
        self.samples = record.attributes.compactMap { key, value in
            guard key != "agentstudio.performance.elapsed_ms" else { return nil }
            guard let numericValue = Self.doubleValue(value) else { return nil }
            guard let metricLabel = Self.metricLabel(for: key) else { return nil }
            return AgentStudioOTLPPerformanceMetricSample(
                eventName: record.body,
                dimensions: dimensions,
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
        if attributeKey.hasPrefix("agentstudio.performance.") {
            let suffix = String(attributeKey.dropFirst("agentstudio.performance.".count))
            return metricLabel(prefix: "agentstudio_performance", suffix: suffix)
        }

        guard allowedBridgeMetricAttributeKeys.contains(attributeKey) else { return nil }
        let suffix = String(attributeKey.dropFirst("agentstudio.bridge.".count))
        return metricLabel(prefix: "agentstudio_bridge", suffix: suffix)
    }

    private static func metricLabel(prefix: String, suffix: String) -> String? {
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
        return "\(prefix)_\(sanitized)"
    }

    private static let allowedBridgeMetricAttributeKeys: Set<String> = [
        "agentstudio.bridge.batch.sample_count",
        "agentstudio.bridge.content.byte_size_bucket",
        "agentstudio.bridge.content.line_count_bucket",
        "agentstudio.bridge.telemetry.dropped_count",
    ]

    private static func metricDimensions(for record: AgentStudioOTLPProjectedLogRecord)
        -> [AgentStudioOTLPMetricDimension]
    {
        guard record.body.hasPrefix("performance.bridge.") else {
            return [AgentStudioOTLPMetricDimension(name: "event", value: record.body)]
        }

        var dimensions = [AgentStudioOTLPMetricDimension(name: "event", value: record.body)]
        appendStringAttributeDimension(
            name: "phase",
            attributeKey: "agentstudio.bridge.phase",
            record: record,
            dimensions: &dimensions
        )
        appendStringAttributeDimension(
            name: "plane",
            attributeKey: "agentstudio.bridge.plane",
            record: record,
            dimensions: &dimensions
        )
        appendStringAttributeDimension(
            name: "priority",
            attributeKey: "agentstudio.bridge.priority",
            record: record,
            dimensions: &dimensions
        )
        appendStringAttributeDimension(
            name: "slice",
            attributeKey: "agentstudio.bridge.slice",
            record: record,
            dimensions: &dimensions
        )
        return dimensions
    }

    private static func hasCompleteBridgeMetricTaxonomy(_ record: AgentStudioOTLPProjectedLogRecord) -> Bool {
        stringAttribute(record, "agentstudio.bridge.phase") != nil
            && BridgeTelemetryPlane(rawValue: stringAttribute(record, "agentstudio.bridge.plane") ?? "") != nil
            && BridgeTelemetryPriority(rawValue: stringAttribute(record, "agentstudio.bridge.priority") ?? "") != nil
            && BridgeTelemetrySlice(rawValue: stringAttribute(record, "agentstudio.bridge.slice") ?? "") != nil
    }

    private static func stringAttribute(_ record: AgentStudioOTLPProjectedLogRecord, _ key: String) -> String? {
        guard case .string(let value) = record.attributes[key] else { return nil }
        return value
    }

    private static func appendStringAttributeDimension(
        name: String,
        attributeKey: String,
        record: AgentStudioOTLPProjectedLogRecord,
        dimensions: inout [AgentStudioOTLPMetricDimension]
    ) {
        guard case .string(let value) = record.attributes[attributeKey] else { return }
        dimensions.append(AgentStudioOTLPMetricDimension(name: name, value: value))
    }
}

struct AgentStudioOTLPMetricDimension: Equatable, Hashable, Sendable {
    let name: String
    let value: String
}

struct AgentStudioOTLPPerformanceMetricSample: Equatable, Sendable {
    let eventName: String
    let dimensions: [AgentStudioOTLPMetricDimension]
    let label: String
    let value: Double

    var metricsDimensions: [(String, String)] {
        dimensions.map { ($0.name, $0.value) }
    }
}

private struct MetricInstrumentKey: Hashable {
    let eventName: String
    let dimensions: [AgentStudioOTLPMetricDimension]
}

private struct MetricGaugeKey: Hashable {
    let eventName: String
    let dimensions: [AgentStudioOTLPMetricDimension]
    let label: String
}
