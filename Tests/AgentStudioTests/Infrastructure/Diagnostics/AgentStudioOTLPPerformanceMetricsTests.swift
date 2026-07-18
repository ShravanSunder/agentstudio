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
            parentSpanID: nil,
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
        let expectedDimensions = [
            AgentStudioOTLPPerformanceMetricDimension(name: "event", value: "performance.git.status")
        ]
        #expect(
            metricEvent.samples == [
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.status",
                    label: "agentstudio_performance_git_has_git_internal_changes",
                    dimensions: expectedDimensions,
                    value: 1
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.status",
                    label: "agentstudio_performance_git_pending_count",
                    dimensions: expectedDimensions,
                    value: 64
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.status",
                    label: "agentstudio_performance_git_running_count",
                    dimensions: expectedDimensions,
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
            parentSpanID: nil,
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
            parentSpanID: nil,
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
            AgentStudioOTLPPerformanceMetricDimension(name: "event", value: "performance.atom.read")
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
    func processMallocRecordProjectsPairedMemoryGauges() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 457,
            severityText: .info,
            body: "performance.process.malloc_zone",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.process.malloc.blocks_in_use": .int(7),
                "agentstudio.performance.process.malloc.size_in_use_bytes": .int(11),
                "agentstudio.performance.process.malloc.maximum_size_in_use_bytes": .int(13),
                "agentstudio.performance.process.malloc.size_allocated_bytes": .int(17),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))

        #expect(metricEvent.eventName == "performance.process.malloc_zone")
        #expect(
            metricEvent.samples.map(\.label) == [
                "agentstudio_performance_process_malloc_blocks_in_use",
                "agentstudio_performance_process_malloc_maximum_size_in_use_bytes",
                "agentstudio_performance_process_malloc_size_allocated_bytes",
                "agentstudio_performance_process_malloc_size_in_use_bytes",
            ])
        #expect(
            metricEvent.measurements.allSatisfy { measurement in
                if case .gauge = measurement { return true }
                return false
            })
    }

    @Test
    func bridgeRefreshOccurrenceCountsAreCountersAndElapsedTimeIsDistributed() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 458,
            severityText: .info,
            body: "performance.bridge.refresh",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.swift", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.phase": .string("final_commit"),
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("warm"),
                "agentstudio.bridge.slice": .string("diff_package_delta"),
                "agentstudio.performance.bridge.active_refresh.count": .int(1),
                "agentstudio.performance.bridge.final_commit.count": .int(1),
                "agentstudio.performance.elapsed_ms": .double(2.5),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))

        #expect(metricEvent.measurements.count == 3)
        #expect(
            metricEvent.measurements.filter { measurement in
                if case .counter = measurement { return true }
                return false
            }.count == 2)
        #expect(
            metricEvent.measurements.contains { measurement in
                if case .distribution(let sample) = measurement {
                    return sample.label == AgentStudioOTLPPerformanceMetrics.elapsedMetricLabel
                }
                return false
            })
    }

    @Test
    func bridgePerformanceRecordProjectsOnlySafeBridgeMetrics() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 124,
            severityText: .info,
            body: "performance.bridge.webkit.package_push",
            traceID: "11111111111111111111111111111111",
            spanID: "2222222222222222",
            parentSpanID: "3333333333333333",
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.webkit", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.content.byte_size_bucket": .int(100_000),
                "agentstudio.bridge.content.line_count_bucket": .int(500),
                "agentstudio.bridge.item_id": .string("private-item-id"),
                "agentstudio.bridge.phase": .string("transport"),
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("cold"),
                "agentstudio.bridge.slice": .string("diff_package_metadata"),
                "agentstudio.performance.elapsed_ms": .double(8.5),
                "agentstudio.trace.tag": .string("bridge.performance.webkit"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))
        let expectedDimensions = [
            AgentStudioOTLPPerformanceMetricDimension(
                name: "event",
                value: "performance.bridge.webkit.package_push"
            ),
            AgentStudioOTLPPerformanceMetricDimension(name: "phase", value: "transport"),
            AgentStudioOTLPPerformanceMetricDimension(name: "plane", value: "data"),
            AgentStudioOTLPPerformanceMetricDimension(name: "priority", value: "cold"),
            AgentStudioOTLPPerformanceMetricDimension(name: "slice", value: "diff_package_metadata"),
        ]

        #expect(metricEvent.eventName == "performance.bridge.webkit.package_push")
        #expect(metricEvent.elapsedMilliseconds == 8.5)
        #expect(metricEvent.dimensions == expectedDimensions)
        #expect(
            metricEvent.samples == [
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.bridge.webkit.package_push",
                    label: "agentstudio_bridge_content_byte_size_bucket",
                    dimensions: expectedDimensions,
                    value: 100_000
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.bridge.webkit.package_push",
                    label: "agentstudio_bridge_content_line_count_bucket",
                    dimensions: expectedDimensions,
                    value: 500
                ),
            ])
    }

    @Test
    func bridgePerformanceRecordRequiresCompleteFiniteTaxonomy() {
        let missingPhase = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 124,
            severityText: .info,
            body: "performance.bridge.webkit.package_push",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.webkit", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("cold"),
                "agentstudio.bridge.slice": .string("diff_package_metadata"),
            ]
        )
        let invalidSlice = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 125,
            severityText: .info,
            body: "performance.bridge.webkit.package_push",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.webkit", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.phase": .string("transport"),
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("cold"),
                "agentstudio.bridge.slice": .string("not_a_slice"),
            ]
        )

        #expect(AgentStudioOTLPPerformanceMetricEvent(record: missingPhase) == nil)
        #expect(AgentStudioOTLPPerformanceMetricEvent(record: invalidSlice) == nil)
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
            parentSpanID: nil,
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
            parentSpanID: nil,
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
