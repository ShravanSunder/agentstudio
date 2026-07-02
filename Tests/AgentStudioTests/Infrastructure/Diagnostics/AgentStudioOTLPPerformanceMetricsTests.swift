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
    func bridgePerformanceRecordProjectsOnlySafeBridgeMetrics() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 124,
            severityText: .info,
            body: "performance.bridge.webkit.push_envelope",
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
                "agentstudio.bridge.slice": .string("review_metadata"),
                "agentstudio.performance.elapsed_ms": .double(8.5),
                "agentstudio.trace.tag": .string("bridge.performance.webkit"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))
        let expectedDimensions = [
            AgentStudioOTLPPerformanceMetricDimension(
                name: "event",
                value: "performance.bridge.webkit.push_envelope"
            ),
            AgentStudioOTLPPerformanceMetricDimension(name: "phase", value: "transport"),
            AgentStudioOTLPPerformanceMetricDimension(name: "plane", value: "data"),
            AgentStudioOTLPPerformanceMetricDimension(name: "priority", value: "cold"),
            AgentStudioOTLPPerformanceMetricDimension(name: "slice", value: "review_metadata"),
        ]

        #expect(metricEvent.eventName == "performance.bridge.webkit.push_envelope")
        #expect(metricEvent.elapsedMilliseconds == 8.5)
        #expect(metricEvent.dimensions == expectedDimensions)
        #expect(
            metricEvent.samples == [
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.bridge.webkit.push_envelope",
                    label: "agentstudio_bridge_content_byte_size_bucket",
                    dimensions: expectedDimensions,
                    value: 100_000
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.bridge.webkit.push_envelope",
                    label: "agentstudio_bridge_content_line_count_bucket",
                    dimensions: expectedDimensions,
                    value: 500
                ),
            ])
    }

    @Test
    func bridgeDemandQueueWaitProjectsLaneDimensionAndSchedulerGauges() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 125,
            severityText: .info,
            body: "performance.bridge.swift.metadata_scheduler_queue_wait",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.swift", version: "0.1.0"),
            attributes: [
                "agent.proof.marker": .string("bridge-headless-manifest-proof"),
                "agentstudio.bridge.demand.lane": .string("foreground"),
                "agentstudio.bridge.demand.queue_depth": .double(7),
                "agentstudio.bridge.demand.scheduler_queue_wait_ms": .double(12.5),
                "agentstudio.bridge.phase": .string("demand_queue_wait"),
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("hot"),
                "agentstudio.bridge.slice": .string("tree_prepare_input"),
                "agentstudio.performance.elapsed_ms": .double(12.5),
                "agentstudio.trace.tag": .string("bridge.performance.swift"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))
        let expectedDimensions = [
            AgentStudioOTLPPerformanceMetricDimension(
                name: "event",
                value: "performance.bridge.swift.metadata_scheduler_queue_wait"
            ),
            AgentStudioOTLPPerformanceMetricDimension(
                name: "agent.proof.marker",
                value: "bridge-headless-manifest-proof"
            ),
            AgentStudioOTLPPerformanceMetricDimension(name: "phase", value: "demand_queue_wait"),
            AgentStudioOTLPPerformanceMetricDimension(name: "plane", value: "data"),
            AgentStudioOTLPPerformanceMetricDimension(name: "priority", value: "hot"),
            AgentStudioOTLPPerformanceMetricDimension(name: "slice", value: "tree_prepare_input"),
            AgentStudioOTLPPerformanceMetricDimension(name: "lane", value: "foreground"),
        ]

        #expect(metricEvent.dimensions == expectedDimensions)
        #expect(metricEvent.elapsedMilliseconds == 12.5)
        #expect(
            metricEvent.samples == [
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.bridge.swift.metadata_scheduler_queue_wait",
                    label: "agentstudio_bridge_demand_queue_depth",
                    dimensions: expectedDimensions,
                    value: 7
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.bridge.swift.metadata_scheduler_queue_wait",
                    label: "agentstudio_bridge_demand_scheduler_queue_wait_ms",
                    dimensions: expectedDimensions,
                    value: 12.5
                ),
            ])
    }

    @Test
    func bridgeTimeToFirstInteractionProjectsVariantDimension() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 126,
            severityText: .info,
            body: "performance.bridge.viewer.time_to_first_interaction",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.web", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.phase": .string("time_to_first_interaction"),
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("hot"),
                "agentstudio.bridge.slice": .string("content_fetch"),
                "agentstudio.bridge.viewer": .string("file"),
                "agentstudio.bridge.viewer.ttfi_variant": .string("cold"),
                "agentstudio.performance.elapsed_ms": .double(1429),
                "agentstudio.trace.tag": .string("bridge.performance.web"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))
        let expectedDimensions = [
            AgentStudioOTLPPerformanceMetricDimension(
                name: "event",
                value: "performance.bridge.viewer.time_to_first_interaction"
            ),
            AgentStudioOTLPPerformanceMetricDimension(name: "phase", value: "time_to_first_interaction"),
            AgentStudioOTLPPerformanceMetricDimension(name: "plane", value: "data"),
            AgentStudioOTLPPerformanceMetricDimension(name: "priority", value: "hot"),
            AgentStudioOTLPPerformanceMetricDimension(name: "slice", value: "content_fetch"),
            AgentStudioOTLPPerformanceMetricDimension(name: "variant", value: "cold"),
        ]

        #expect(metricEvent.dimensions == expectedDimensions)
        #expect(metricEvent.elapsedMilliseconds == 1429)
    }

    @Test
    func bridgePerformanceRecordRequiresCompleteFiniteTaxonomy() {
        let missingPhase = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 124,
            severityText: .info,
            body: "performance.bridge.webkit.push_envelope",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.bridge.performance.webkit", version: "0.1.0"),
            attributes: [
                "agentstudio.bridge.plane": .string("data"),
                "agentstudio.bridge.priority": .string("cold"),
                "agentstudio.bridge.slice": .string("review_metadata"),
            ]
        )
        let invalidSlice = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 125,
            severityText: .info,
            body: "performance.bridge.webkit.push_envelope",
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
