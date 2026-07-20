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
    func gitStatusScopeBecomesMetricDimension() throws {
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
                "agentstudio.performance.elapsed_ms": .double(12.0),
                "agentstudio.performance.git.status_scope": .string("pathspec"),
                "agentstudio.performance.git.pathspec.count": .int(3),
                "agentstudio.trace.tag": .string("performance"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))

        #expect(metricEvent.eventName == "performance.git.status")
        let expectedDimensions = [
            AgentStudioOTLPPerformanceMetricDimension(name: "event", value: "performance.git.status"),
            AgentStudioOTLPPerformanceMetricDimension(name: "scope", value: "pathspec"),
        ]
        #expect(metricEvent.dimensions == expectedDimensions)
        #expect(
            metricEvent.samples == [
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.status",
                    label: "agentstudio_performance_git_pathspec_count",
                    dimensions: expectedDimensions,
                    value: 3
                )
            ])
        #expect(metricEvent.elapsedMilliseconds == 12.0)
    }

    @Test
    func gitBackoffProjectsBoundedMetricsWithReasonDimension() throws {
        let record = AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 123,
            severityText: .info,
            body: "performance.git.backoff",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: [
                "agentstudio.performance.git.backoff_open": .bool(true),
                "agentstudio.performance.git.backoff_ms": .double(500),
                "agentstudio.performance.git.backoff_attempt.count": .int(3),
                "agentstudio.performance.git.backoff.reason": .string("timeout"),
                "agentstudio.performance.git.pending.count": .int(2),
                "agentstudio.trace.tag": .string("performance"),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))

        #expect(metricEvent.eventName == "performance.git.backoff")
        let expectedDimensions = [
            AgentStudioOTLPPerformanceMetricDimension(name: "event", value: "performance.git.backoff"),
            AgentStudioOTLPPerformanceMetricDimension(name: "reason", value: "timeout"),
        ]
        #expect(metricEvent.dimensions == expectedDimensions)
        #expect(
            metricEvent.samples == [
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.backoff",
                    label: "agentstudio_performance_git_backoff_attempt_count",
                    dimensions: expectedDimensions,
                    value: 3
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.backoff",
                    label: "agentstudio_performance_git_backoff_ms",
                    dimensions: expectedDimensions,
                    value: 500
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.backoff",
                    label: "agentstudio_performance_git_backoff_open",
                    dimensions: expectedDimensions,
                    value: 1
                ),
                AgentStudioOTLPPerformanceMetricSample(
                    eventName: "performance.git.backoff",
                    label: "agentstudio_performance_git_pending_count",
                    dimensions: expectedDimensions,
                    value: 2
                ),
            ])
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
    func runtimePressureAggregateDeltasAreCountersWhileRetainedValuesStayGauges() throws {
        let factory = RecordingMetricsFactory()
        let metrics = AgentStudioOTLPPerformanceMetrics(factory: factory)
        let dimensions = [
            ("drain_class", "immediate"),
            ("event", "performance.terminal.accumulator_drain"),
        ]
        let firstRecord = Self.projectedPerformanceRecord(
            body: "performance.terminal.accumulator_drain",
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(3),
                "agentstudio.performance.terminal.accumulator.drain.class": .string("immediate"),
                "agentstudio.performance.terminal.accumulator.offered.count": .int(10),
                "agentstudio.performance.terminal.accumulator.replaced.count": .int(8),
                "agentstudio.performance.terminal.accumulator.retained_entry.count": .int(4),
                "agentstudio.performance.terminal.accumulator.retained_size_bytes": .int(256),
            ]
        )
        let secondRecord = Self.projectedPerformanceRecord(
            body: "performance.terminal.accumulator_drain",
            attributes: [
                "agentstudio.performance.elapsed_ms": .double(1),
                "agentstudio.performance.terminal.accumulator.drain.class": .string("immediate"),
                "agentstudio.performance.terminal.accumulator.offered.count": .int(5),
                "agentstudio.performance.terminal.accumulator.replaced.count": .int(3),
                "agentstudio.performance.terminal.accumulator.retained_entry.count": .int(2),
                "agentstudio.performance.terminal.accumulator.retained_size_bytes": .int(128),
            ]
        )

        let metricEvent = try #require(AgentStudioOTLPPerformanceMetricEvent(record: firstRecord))
        metrics.record(firstRecord)
        metrics.record(secondRecord)

        #expect(
            metricEvent.dimensions.contains(
                AgentStudioOTLPPerformanceMetricDimension(name: "drain_class", value: "immediate")
            )
        )
        #expect(
            metricEvent.measurements.contains { measurement in
                if case .counter(let sample) = measurement {
                    return sample.label == "agentstudio_performance_terminal_accumulator_offered_count"
                }
                return false
            })
        #expect(
            metricEvent.measurements.contains { measurement in
                if case .gauge(let sample) = measurement {
                    return sample.label == "agentstudio_performance_terminal_accumulator_retained_entry_count"
                }
                return false
            })
        #expect(
            factory.counter(
                label: "agentstudio_performance_terminal_accumulator_offered_count",
                dimensions: dimensions
            )?.totalValue == 15)
        #expect(
            factory.counter(
                label: "agentstudio_performance_terminal_accumulator_replaced_count",
                dimensions: dimensions
            )?.totalValue == 11)
        #expect(
            factory.recorder(
                label: "agentstudio_performance_terminal_accumulator_retained_entry_count",
                dimensions: dimensions
            )?.values == [4, 2])
        #expect(
            factory.recorder(
                label: "agentstudio_performance_terminal_accumulator_retained_size_bytes",
                dimensions: dimensions
            )?.values == [256, 128])
        #expect(
            factory.recorder(
                label: AgentStudioOTLPPerformanceMetrics.elapsedMetricLabel,
                dimensions: dimensions
            )?.values == [3, 1])
    }

    @Test
    func commonQuiescenceRecordsProjectExactAggregateGaugeSeries() throws {
        let records = [
            Self.projectedPerformanceRecord(
                body: "performance.filesystem.logical_debt",
                attributes: [
                    "agentstudio.performance.filesystem.pending_worktree.count": .int(9),
                    "agentstudio.performance.filesystem.drain_task.count": .int(8),
                    "agentstudio.performance.filesystem.watched_folder.ready.count": .int(7),
                    "agentstudio.performance.filesystem.watched_folder.active.count": .int(6),
                    "agentstudio.performance.filesystem.watched_folder.dirty_follow_up.count": .int(2),
                    "agentstudio.performance.filesystem.logical_debt.count": .int(1),
                ]
            ),
            Self.projectedPerformanceRecord(
                body: "performance.git.logical_debt",
                attributes: [
                    "agentstudio.performance.git.logical_pending.count": .int(4),
                    "agentstudio.performance.git.retry_pending.count": .int(3),
                    "agentstudio.performance.git.logical_running.count": .int(2),
                    "agentstudio.performance.git.logical_debt.count": .int(1),
                ]
            ),
            Self.projectedPerformanceRecord(
                body: "performance.runtime_delivery.snapshot",
                attributes: [
                    "agentstudio.performance.runtime_delivery.runtime_channel_outbound_pending.count": .int(8),
                    "agentstudio.performance.runtime_delivery.eventbus_active_delivery_debt.count": .int(7),
                    "agentstudio.performance.runtime_delivery.total_pending.count": .int(6),
                    "agentstudio.performance.runtime_delivery.runtime_channel_outbound_dropped.count": .int(5),
                    "agentstudio.performance.runtime_delivery.runtime_channel_retired_undelivered.count": .int(4),
                    "agentstudio.performance.runtime_delivery.eventbus_live_dropped.count": .int(3),
                    "agentstudio.performance.runtime_delivery.eventbus_replay_dropped.count": .int(2),
                    "agentstudio.performance.runtime_delivery.eventbus_retired_undelivered.count": .int(1),
                    "agentstudio.performance.runtime_delivery.eventbus_active_subscriber.count": .int(4),
                ]
            ),
        ]

        let metricEvents = try records.map { record in
            try #require(AgentStudioOTLPPerformanceMetricEvent(record: record))
        }

        #expect(
            metricEvents[0].samples.map(\.label) == [
                "agentstudio_performance_filesystem_drain_task_count",
                "agentstudio_performance_filesystem_logical_debt_count",
                "agentstudio_performance_filesystem_pending_worktree_count",
                "agentstudio_performance_filesystem_watched_folder_active_count",
                "agentstudio_performance_filesystem_watched_folder_dirty_follow_up_count",
                "agentstudio_performance_filesystem_watched_folder_ready_count",
            ])
        #expect(
            metricEvents[1].samples.map(\.label) == [
                "agentstudio_performance_git_logical_debt_count",
                "agentstudio_performance_git_logical_pending_count",
                "agentstudio_performance_git_logical_running_count",
                "agentstudio_performance_git_retry_pending_count",
            ])
        #expect(
            metricEvents[2].samples.map(\.label) == [
                "agentstudio_performance_runtime_delivery_eventbus_active_delivery_debt_count",
                "agentstudio_performance_runtime_delivery_eventbus_active_subscriber_count",
                "agentstudio_performance_runtime_delivery_eventbus_live_dropped_count",
                "agentstudio_performance_runtime_delivery_eventbus_replay_dropped_count",
                "agentstudio_performance_runtime_delivery_eventbus_retired_undelivered_count",
                "agentstudio_performance_runtime_delivery_runtime_channel_outbound_dropped_count",
                "agentstudio_performance_runtime_delivery_runtime_channel_outbound_pending_count",
                "agentstudio_performance_runtime_delivery_runtime_channel_retired_undelivered_count",
                "agentstudio_performance_runtime_delivery_total_pending_count",
            ])
        #expect(
            metricEvents.flatMap(\.measurements).allSatisfy { measurement in
                if case .gauge = measurement { return true }
                return false
            })
    }

    @Test
    func commonQuiescenceGaugeRecordsNonzeroThenZero() throws {
        let factory = RecordingMetricsFactory()
        let metrics = AgentStudioOTLPPerformanceMetrics(factory: factory)
        let dimensions = [("event", "performance.runtime_delivery.snapshot")]

        metrics.record(
            Self.projectedPerformanceRecord(
                body: "performance.runtime_delivery.snapshot",
                attributes: [
                    "agentstudio.performance.runtime_delivery.total_pending.count": .int(6)
                ]
            ))
        metrics.record(
            Self.projectedPerformanceRecord(
                body: "performance.runtime_delivery.snapshot",
                attributes: [
                    "agentstudio.performance.runtime_delivery.total_pending.count": .int(0)
                ]
            ))

        let gauge = try #require(
            factory.recorder(
                label: "agentstudio_performance_runtime_delivery_total_pending_count",
                dimensions: dimensions
            )
        )
        #expect(gauge.values == [6, 0])
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

    private static func projectedPerformanceRecord(
        body: String,
        attributes: [String: AgentStudioTraceValue]
    ) -> AgentStudioOTLPProjectedLogRecord {
        AgentStudioOTLPProjectedLogRecord(
            timeUnixNano: 458,
            severityText: .info,
            body: body,
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: ["service.name": "AgentStudio"],
            scope: .init(name: "agentstudio.performance", version: "0.1.0"),
            attributes: attributes
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
