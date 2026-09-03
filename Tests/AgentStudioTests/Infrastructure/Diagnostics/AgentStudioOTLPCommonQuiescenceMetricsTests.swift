import Testing

@testable import AgentStudioInfrastructure

@Suite
struct AgentStudioOTLPCommonQuiescenceMetricsTests {
    @Test
    func commonQuiescenceRecordsProjectExactAggregateGaugeSeries() throws {
        let records = [
            projectedPerformanceRecord(
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
            projectedPerformanceRecord(
                body: "performance.git.logical_debt",
                attributes: [
                    "agentstudio.performance.git.logical_pending.count": .int(4),
                    "agentstudio.performance.git.retry_pending.count": .int(3),
                    "agentstudio.performance.git.logical_running.count": .int(2),
                    "agentstudio.performance.git.logical_debt.count": .int(1),
                    "agentstudio.performance.git.future_automatic.count": .int(86),
                    "agentstudio.performance.git.future_failure.count": .int(1),
                    "agentstudio.performance.git.ready_pending.count": .int(0),
                    "agentstudio.performance.git.capacity_pending.count": .int(0),
                    "agentstudio.performance.git.active_follow_up.count": .int(1),
                    "agentstudio.performance.git.unclassified_pending.count": .int(0),
                    "agentstudio.performance.git.overdue_deadline.count": .int(0),
                    "agentstudio.performance.git.oldest_preparation_ms": .double(120),
                    "agentstudio.performance.git.next_deadline_ms": .double(1000),
                ]
            ),
            projectedPerformanceRecord(
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
                "agentstudio_performance_git_active_follow_up_count",
                "agentstudio_performance_git_capacity_pending_count",
                "agentstudio_performance_git_future_automatic_count",
                "agentstudio_performance_git_future_failure_count",
                "agentstudio_performance_git_logical_debt_count",
                "agentstudio_performance_git_logical_pending_count",
                "agentstudio_performance_git_logical_running_count",
                "agentstudio_performance_git_next_deadline_ms",
                "agentstudio_performance_git_oldest_preparation_ms",
                "agentstudio_performance_git_overdue_deadline_count",
                "agentstudio_performance_git_ready_pending_count",
                "agentstudio_performance_git_retry_pending_count",
                "agentstudio_performance_git_unclassified_pending_count",
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

    private func projectedPerformanceRecord(
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
