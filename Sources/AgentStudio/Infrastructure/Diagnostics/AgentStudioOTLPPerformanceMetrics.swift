import Foundation
import Metrics

final class AgentStudioOTLPPerformanceMetrics: @unchecked Sendable {
    static let elapsedMetricLabel = "agentstudio_performance_event_elapsed_ms"
    static let elapsedMaximumMetricLabel = "agentstudio_performance_event_elapsed_ms_max"
    static let elapsedHistogramBuckets: [Double] = [
        0, 0.25, 0.5, 1, 2, 5, 8, 10, 16, 20, 25, 50, 60, 75, 100, 150, 200, 250, 350, 500, 650, 750,
        900, 1000, 1050, 1100,
        1250, 1500, 2000, 2500, 5000, 7500, 10_000,
    ]

    private let factory: any MetricsFactory
    private let lock = NSLock()
    private var eventCounters: [MetricEventKey: Counter] = [:]
    private var elapsedRecorders: [MetricEventKey: Recorder] = [:]
    private var elapsedMaxGauges: [MetricEventKey: Gauge] = [:]
    private var elapsedMaxValues: [MetricEventKey: Double] = [:]
    private var numericGauges: [MetricGaugeKey: Gauge] = [:]
    private var numericCounters: [MetricGaugeKey: Counter] = [:]
    private var distributionRecorders: [MetricGaugeKey: Recorder] = [:]

    init(factory: any MetricsFactory) {
        self.factory = factory
    }

    func record(_ record: AgentStudioOTLPProjectedLogRecord) {
        guard let metricEvent = AgentStudioOTLPPerformanceMetricEvent(record: record) else { return }

        lock.withLock {
            counter(for: metricEvent).increment()

            for measurement in metricEvent.measurements {
                switch measurement {
                case .counter(let sample):
                    counter(for: sample).increment(by: Self.int64Clamped(sample.value))
                case .distribution(let sample):
                    distributionRecorder(for: sample).record(sample.value)
                    if sample.label == Self.elapsedMetricLabel {
                        recordElapsedMaximum(sample.value, for: metricEvent)
                    }
                case .gauge(let sample):
                    gauge(for: sample).record(sample.value)
                }
            }
        }
    }

    private func counter(for event: AgentStudioOTLPPerformanceMetricEvent) -> Counter {
        let key = MetricEventKey(eventName: event.eventName, dimensions: event.dimensions)
        if let counter = eventCounters[key] {
            return counter
        }

        let counter = Counter(
            label: "agentstudio_performance_events_total",
            dimensions: event.dimensionTuples,
            factory: factory
        )
        eventCounters[key] = counter
        return counter
    }

    private func recorder(for event: AgentStudioOTLPPerformanceMetricEvent) -> Recorder {
        let key = MetricEventKey(eventName: event.eventName, dimensions: event.dimensions)
        if let recorder = elapsedRecorders[key] {
            return recorder
        }

        let recorder = Recorder(
            label: Self.elapsedMetricLabel,
            dimensions: event.dimensionTuples,
            factory: factory
        )
        elapsedRecorders[key] = recorder
        return recorder
    }

    private func recordElapsedMaximum(_ elapsedMilliseconds: Double, for event: AgentStudioOTLPPerformanceMetricEvent) {
        let key = MetricEventKey(eventName: event.eventName, dimensions: event.dimensions)
        let maximumElapsedMilliseconds = max(elapsedMaxValues[key] ?? elapsedMilliseconds, elapsedMilliseconds)
        elapsedMaxValues[key] = maximumElapsedMilliseconds
        elapsedMaximumGauge(for: event).record(maximumElapsedMilliseconds)
    }

    private func elapsedMaximumGauge(for event: AgentStudioOTLPPerformanceMetricEvent) -> Gauge {
        let key = MetricEventKey(eventName: event.eventName, dimensions: event.dimensions)
        if let gauge = elapsedMaxGauges[key] {
            return gauge
        }

        let gauge = Gauge(
            label: Self.elapsedMaximumMetricLabel,
            dimensions: event.dimensionTuples,
            factory: factory
        )
        elapsedMaxGauges[key] = gauge
        return gauge
    }

    private func gauge(for sample: AgentStudioOTLPPerformanceMetricSample) -> Gauge {
        let key = MetricGaugeKey(eventName: sample.eventName, label: sample.label, dimensions: sample.dimensions)
        if let gauge = numericGauges[key] {
            return gauge
        }

        let gauge = Gauge(
            label: sample.label,
            dimensions: sample.dimensionTuples,
            factory: factory
        )
        numericGauges[key] = gauge
        return gauge
    }

    private func counter(for sample: AgentStudioOTLPPerformanceMetricSample) -> Counter {
        let key = MetricGaugeKey(eventName: sample.eventName, label: sample.label, dimensions: sample.dimensions)
        if let counter = numericCounters[key] {
            return counter
        }
        let counter = Counter(label: sample.label, dimensions: sample.dimensionTuples, factory: factory)
        numericCounters[key] = counter
        return counter
    }

    private func distributionRecorder(for sample: AgentStudioOTLPPerformanceMetricSample) -> Recorder {
        if sample.label == Self.elapsedMetricLabel {
            return recorder(
                for: AgentStudioOTLPPerformanceMetricEvent(
                    eventName: sample.eventName,
                    dimensions: sample.dimensions,
                    elapsedMilliseconds: sample.value,
                    samples: [],
                    measurements: []
                ))
        }
        let key = MetricGaugeKey(eventName: sample.eventName, label: sample.label, dimensions: sample.dimensions)
        if let recorder = distributionRecorders[key] {
            return recorder
        }
        let recorder = Recorder(label: sample.label, dimensions: sample.dimensionTuples, factory: factory)
        distributionRecorders[key] = recorder
        return recorder
    }

    private static func int64Clamped(_ value: Double) -> Int64 {
        if value >= Double(Int64.max) { return Int64.max }
        if value <= Double(Int64.min) { return Int64.min }
        return Int64(value)
    }
}

struct AgentStudioOTLPPerformanceMetricEvent: Equatable, Sendable {
    let eventName: String
    let dimensions: [AgentStudioOTLPPerformanceMetricDimension]
    let elapsedMilliseconds: Double?
    let samples: [AgentStudioOTLPPerformanceMetricSample]
    let measurements: [AgentStudioOTLPPerformanceMeasurement]

    var dimensionTuples: [(String, String)] {
        dimensions.map(\.tuple)
    }

    init?(record: AgentStudioOTLPProjectedLogRecord) {
        guard record.body.hasPrefix("performance.") else { return nil }
        if record.body.hasPrefix("performance.bridge.") {
            guard Self.hasCompleteBridgeMetricTaxonomy(record) else { return nil }
        }

        let dimensions = Self.dimensions(for: record)
        self.eventName = record.body
        self.dimensions = dimensions
        self.elapsedMilliseconds = Self.doubleValue(
            record.attributes["agentstudio.performance.elapsed_ms"]
        )
        let samples: [AgentStudioOTLPPerformanceMetricSample] = record.attributes.compactMap { element in
            let (key, value) = element
            guard key != "agentstudio.performance.elapsed_ms" else { return nil }
            guard let numericValue = Self.doubleValue(value) else { return nil }
            guard let metricLabel = Self.metricLabel(for: key) else { return nil }
            return AgentStudioOTLPPerformanceMetricSample(
                eventName: record.body,
                label: metricLabel,
                dimensions: dimensions,
                value: numericValue
            )
        }
        .sorted { left, right in
            if left.label == right.label {
                return left.eventName < right.eventName
            }
            return left.label < right.label
        }
        self.samples = samples
        var measurements: [AgentStudioOTLPPerformanceMeasurement] = samples.compactMap { sample in
            Self.measurement(for: sample)
        }
        if let elapsedMilliseconds {
            measurements.append(
                .distribution(
                    AgentStudioOTLPPerformanceMetricSample(
                        eventName: record.body,
                        label: AgentStudioOTLPPerformanceMetrics.elapsedMetricLabel,
                        dimensions: dimensions,
                        value: elapsedMilliseconds
                    )))
        }
        self.measurements = measurements.sorted { $0.sortKey < $1.sortKey }
    }

    fileprivate init(
        eventName: String,
        dimensions: [AgentStudioOTLPPerformanceMetricDimension],
        elapsedMilliseconds: Double?,
        samples: [AgentStudioOTLPPerformanceMetricSample],
        measurements: [AgentStudioOTLPPerformanceMeasurement]
    ) {
        self.eventName = eventName
        self.dimensions = dimensions
        self.elapsedMilliseconds = elapsedMilliseconds
        self.samples = samples
        self.measurements = measurements
    }

    private static func dimensions(for record: AgentStudioOTLPProjectedLogRecord)
        -> [AgentStudioOTLPPerformanceMetricDimension]
    {
        var dimensions = [
            AgentStudioOTLPPerformanceMetricDimension(name: "event", value: record.body)
        ]
        if record.body == "performance.git.status_unavailable",
            case .string(let reason) = record.attributes["agentstudio.performance.git.status_unavailable.reason"],
            isSafeDimensionValue(reason)
        {
            dimensions.append(AgentStudioOTLPPerformanceMetricDimension(name: "reason", value: reason))
        }
        if record.body == "performance.terminal.accumulator_drain",
            case .string(let drainClass) = record.attributes[
                "agentstudio.performance.terminal.accumulator.drain.class"
            ],
            isSafeDimensionValue(drainClass)
        {
            dimensions.append(
                AgentStudioOTLPPerformanceMetricDimension(name: "drain_class", value: drainClass)
            )
        }
        if record.body.hasPrefix("performance.bridge.") {
            appendBridgeDimension(
                name: "phase",
                attributeKey: "agentstudio.bridge.phase",
                record: record,
                dimensions: &dimensions
            )
            appendBridgeDimension(
                name: "plane",
                attributeKey: "agentstudio.bridge.plane",
                record: record,
                dimensions: &dimensions
            )
            appendBridgeDimension(
                name: "priority",
                attributeKey: "agentstudio.bridge.priority",
                record: record,
                dimensions: &dimensions
            )
            appendBridgeDimension(
                name: "slice",
                attributeKey: "agentstudio.bridge.slice",
                record: record,
                dimensions: &dimensions
            )
        }
        return dimensions
    }

    private static func measurement(
        for sample: AgentStudioOTLPPerformanceMetricSample
    ) -> AgentStudioOTLPPerformanceMeasurement? {
        if counterMetricLabels.contains(sample.label) {
            guard sample.value >= 0 else { return nil }
            return .counter(sample)
        }
        return .gauge(sample)
    }

    private static let counterMetricLabels: Set<String> = [
        "agentstudio_performance_filesystem_affected_key_request_count",
        "agentstudio_performance_filesystem_full_reconciliation_request_count",
        "agentstudio_performance_terminal_accumulator_equal_suppressed_count",
        "agentstudio_performance_terminal_accumulator_follow_up_drain_count",
        "agentstudio_performance_terminal_accumulator_mainactor_task_count",
        "agentstudio_performance_terminal_accumulator_offered_count",
        "agentstudio_performance_terminal_accumulator_replaced_count",
        "agentstudio_performance_terminal_accumulator_scheduled_drain_count",
        "agentstudio_performance_terminal_activity_aggregate_count",
        "agentstudio_performance_terminal_equal_write_suppressed_count",
        "agentstudio_performance_trace_identity_coalesced_request_count",
        "agentstudio_performance_trace_identity_equal_snapshot_suppressed_count",
        "agentstudio_performance_trace_identity_fleet_capture_count",
        "agentstudio_performance_trace_identity_refresh_request_count",
    ]

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

    private static func appendBridgeDimension(
        name: String,
        attributeKey: String,
        record: AgentStudioOTLPProjectedLogRecord,
        dimensions: inout [AgentStudioOTLPPerformanceMetricDimension]
    ) {
        guard case .string(let value) = record.attributes[attributeKey] else { return }
        dimensions.append(AgentStudioOTLPPerformanceMetricDimension(name: name, value: value))
    }

    private static func isSafeDimensionValue(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "_"
                || scalar == "-"
                || scalar == "."
        }
    }
}

enum AgentStudioOTLPPerformanceMeasurement: Equatable, Sendable {
    case counter(AgentStudioOTLPPerformanceMetricSample)
    case distribution(AgentStudioOTLPPerformanceMetricSample)
    case gauge(AgentStudioOTLPPerformanceMetricSample)

    fileprivate var sortKey: String {
        switch self {
        case .counter(let sample):
            "counter:\(sample.label)"
        case .distribution(let sample):
            "distribution:\(sample.label)"
        case .gauge(let sample):
            "gauge:\(sample.label)"
        }
    }
}

struct AgentStudioOTLPPerformanceMetricSample: Equatable, Sendable {
    let eventName: String
    let label: String
    let dimensions: [AgentStudioOTLPPerformanceMetricDimension]
    let value: Double

    var dimensionTuples: [(String, String)] {
        dimensions.map(\.tuple)
    }
}

struct AgentStudioOTLPPerformanceMetricDimension: Equatable, Hashable, Sendable {
    let name: String
    let value: String

    var tuple: (String, String) {
        (name, value)
    }
}

private struct MetricEventKey: Hashable {
    let eventName: String
    let dimensions: [AgentStudioOTLPPerformanceMetricDimension]
}

private struct MetricGaugeKey: Hashable {
    let eventName: String
    let label: String
    let dimensions: [AgentStudioOTLPPerformanceMetricDimension]
}
