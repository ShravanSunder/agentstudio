import Foundation
import Metrics
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioOTLPPerformanceMetricsTests {
    @Test
    func performanceRecordProjectsBoundedMetricsFromScrubbedAttributes() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 123,
            severityText: .info,
            body: "performance.git.status",
            traceID: nil,
            spanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(15.5),
                "agentstudio.performance.git.pending.count": .int(64),
                "agentstudio.performance.git.running.count": .int(4),
                "agentstudio.performance.git.has_git_internal_changes": .bool(true),
                "agentstudio.performance.git.root_path": .string("/Users/private/repo"),
                "agentstudio.trace.tag": .string("performance"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))

        #expect(metricEvent.eventName == "performance.git.status")
        #expect(metricEvent.elapsedMilliseconds == 15.5)
        #expect(
            metricEvent.samples == [
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.status",
                    label: "agentstudio_performance_git_has_git_internal_changes",
                    dimensions: [
                        AgentStudioOTLPPerformanceMetricDimension(
                            name: "event",
                            value: "performance.git.status"
                        )
                    ],
                    value: 1
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.status",
                    label: "agentstudio_performance_git_pending_count",
                    dimensions: [
                        AgentStudioOTLPPerformanceMetricDimension(
                            name: "event",
                            value: "performance.git.status"
                        )
                    ],
                    value: 64
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.status",
                    label: "agentstudio_performance_git_running_count",
                    dimensions: [
                        AgentStudioOTLPPerformanceMetricDimension(
                            name: "event",
                            value: "performance.git.status"
                        )
                    ],
                    value: 4
                ),
            ])
    }

    @Test
    func gitStatusUnavailableReasonBecomesMetricDimension() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 123,
            severityText: .info,
            body: "performance.git.status_unavailable",
            traceID: nil,
            spanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(21.5),
                "agentstudio.performance.git.status_unavailable.reason": .string("timeout"),
                "agentstudio.trace.tag": .string("performance"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))

        #expect(metricEvent.eventName == "performance.git.status_unavailable")
        #expect(
            metricEvent.dimensions == [
                AgentStudioOTLPPerformanceMetricDimension(
                    name: "event",
                    value: "performance.git.status_unavailable"
                ),
                AgentStudioOTLPPerformanceMetricDimension(name: "reason", value: "timeout"),
            ])
        #expect(metricEvent.elapsedMilliseconds == 21.5)
    }

    @Test
    func atomPerformanceRecordProjectsAtomCounters() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 456,
            severityText: .info,
            body: "performance.atom.read",
            traceID: nil,
            spanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.atom.kind": .string("entity_map"),
                "agentstudio.performance.atom.operation": .string("value"),
                "agentstudio.performance.atom.slot.count": .int(2),
                "agentstudio.performance.atom.cached_key.count": .int(1),
                "agentstudio.performance.atom.cache_hit": .bool(false),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))

        #expect(metricEvent.eventName == "performance.atom.read")
        let expectedDimensions = [
            AgentStudioOTLPPerformanceMetricDimension(
                name: "event",
                value: "performance.atom.read"
            )
        ]
        #expect(
            metricEvent.samples == [
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.atom.read",
                    label: "agentstudio_performance_atom_cache_hit",
                    dimensions: expectedDimensions,
                    value: 0
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.atom.read",
                    label: "agentstudio_performance_atom_cached_key_count",
                    dimensions: expectedDimensions,
                    value: 1
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.atom.read",
                    label: "agentstudio_performance_atom_slot_count",
                    dimensions: expectedDimensions,
                    value: 2
                ),
            ])
    }

    @Test
    func recorderEmitsCumulativeElapsedMaximumGaugeByReason() throws {
        let factory = RecordingMetricsFactory()
        let metrics = AgentStudioOTLPPerformanceMetrics(factory: factory)
        let dimensions = [
            ("event", "performance.git.status_unavailable"),
            ("reason", "timeout"),
        ]

        metrics.record(Self.gitStatusUnavailableRecord(elapsedMilliseconds: 900))
        metrics.record(Self.gitStatusUnavailableRecord(elapsedMilliseconds: 1200))
        metrics.record(Self.gitStatusUnavailableRecord(elapsedMilliseconds: 700))

        let counter = try #require(
            factory.counter(
                label: "agentstudio_performance_events_total",
                dimensions: dimensions
            )
        )
        let elapsedRecorder = try #require(
            factory.recorder(
                label: "agentstudio_performance_event_elapsed_ms",
                dimensions: dimensions
            )
        )
        let elapsedMaxGauge = try #require(
            factory.recorder(
                label: "agentstudio_performance_event_elapsed_ms_max",
                dimensions: dimensions
            )
        )

        #expect(counter.totalValue == 3)
        #expect(elapsedRecorder.values == [900, 1200, 700])
        #expect(elapsedMaxGauge.values == [900, 1200, 1200])
    }

    @Test
    func elapsedHistogramBucketsKeepTimeoutBoundaryReadable() {
        let buckets = AgentStudioOTLPPerformanceMetrics.elapsedHistogramBuckets
        let adjacentBuckets = zip(buckets, buckets.dropFirst())

        #expect(buckets.contains(1050))
        #expect(buckets.contains(1100))
        #expect(adjacentBuckets.allSatisfy { previous, next in previous < next })
    }

    @Test
    func nonPerformanceRecordsDoNotProducePerformanceMetrics() {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 123,
            severityText: .info,
            body: "persistence.operation.phase",
            traceID: nil,
            spanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.persistence", version: "0.1.0"),
            attributes: [
                "agentstudio.persistence.operation": .string("workspace.load")
            ]
        )

        #expect(AgentStudioOTLPPerformanceMetricEvent(record: record) == nil)
    }

    private static func gitStatusUnavailableRecord(elapsedMilliseconds: Double) -> AgentStudioOTLPProjectedLogRecord {
        AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 123,
            severityText: .info,
            body: "performance.git.status_unavailable",
            traceID: nil,
            spanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(elapsedMilliseconds),
                "agentstudio.performance.git.status_unavailable.reason": .string("timeout"),
                "agentstudio.trace.tag": .string("performance"),
            ]
        )
    }
}

private final class RecordingMetricsFactory: MetricsFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var countersByKey: [RecordingMetricKey: RecordingCounterHandler] = [:]
    private var recordersByKey: [RecordingMetricKey: RecordingRecorderHandler] = [:]

    func makeCounter(label: String, dimensions: [(String, String)]) -> any CounterHandler {
        lock.withLock {
            let key = RecordingMetricKey(label: label, dimensions: dimensions)
            if let counter = countersByKey[key] {
                return counter
            }
            let counter = RecordingCounterHandler()
            countersByKey[key] = counter
            return counter
        }
    }

    func makeRecorder(
        label: String,
        dimensions: [(String, String)],
        aggregate: Bool
    ) -> any RecorderHandler {
        lock.withLock {
            let key = RecordingMetricKey(label: label, dimensions: dimensions)
            if let recorder = recordersByKey[key] {
                return recorder
            }
            let recorder = RecordingRecorderHandler()
            recordersByKey[key] = recorder
            return recorder
        }
    }

    func makeTimer(label: String, dimensions: [(String, String)]) -> any TimerHandler {
        RecordingTimerHandler()
    }

    func destroyCounter(_ handler: any CounterHandler) {}

    func destroyRecorder(_ handler: any RecorderHandler) {}

    func destroyTimer(_ handler: any TimerHandler) {}

    func counter(label: String, dimensions: [(String, String)]) -> RecordingCounterHandler? {
        lock.withLock {
            countersByKey[RecordingMetricKey(label: label, dimensions: dimensions)]
        }
    }

    func recorder(label: String, dimensions: [(String, String)]) -> RecordingRecorderHandler? {
        lock.withLock {
            recordersByKey[RecordingMetricKey(label: label, dimensions: dimensions)]
        }
    }
}

private struct RecordingMetricKey: Hashable {
    let label: String
    let dimensions: [(String, String)]

    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(Dictionary(uniqueKeysWithValues: dimensions))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.label == rhs.label
            && Dictionary(uniqueKeysWithValues: lhs.dimensions) == Dictionary(uniqueKeysWithValues: rhs.dimensions)
    }
}

private final class RecordingCounterHandler: CounterHandler, @unchecked Sendable {
    private let lock = NSLock()
    private var increments: [Int64] = []

    func increment(by amount: Int64) {
        lock.withLock {
            increments.append(amount)
        }
    }

    func reset() {
        lock.withLock {
            increments.removeAll()
        }
    }

    var totalValue: Int64 {
        lock.withLock {
            increments.reduce(0, +)
        }
    }
}

private final class RecordingRecorderHandler: RecorderHandler, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Double] = []

    func record(_ value: Int64) {
        record(Double(value))
    }

    func record(_ value: Double) {
        lock.withLock {
            recordedValues.append(value)
        }
    }

    var values: [Double] {
        lock.withLock {
            recordedValues
        }
    }
}

private final class RecordingTimerHandler: TimerHandler, @unchecked Sendable {
    func recordNanoseconds(_ duration: Int64) {}
}
