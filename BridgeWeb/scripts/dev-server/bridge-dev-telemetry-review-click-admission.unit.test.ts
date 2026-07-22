import { describe, expect, test, vi } from 'vitest';

import type { BridgeTelemetryWorkerBatchRequest } from '../../src/core/telemetry-worker/bridge-telemetry-worker-contracts.js';
import type { BridgeTelemetrySample } from '../../src/foundation/telemetry/bridge-telemetry-event.js';
import { createBridgeDevTelemetrySink } from './bridge-dev-telemetry.js';

describe('Bridge dev telemetry Review click admission', () => {
	test('accepts prior Review click telemetry flushed by the next selection commit', async () => {
		const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 200 }));
		const sink = createBridgeDevTelemetrySink({
			fetchImpl,
			marker: 'vite-dev-proof-1',
			nowUnixNano: () => '1782218790000000000',
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});
		const priorClickBatch = makeTelemetryBatch([
			{
				scope: 'web',
				name: 'performance.bridge.web.frame_jank',
				durationMilliseconds: 48,
				traceContext: null,
				stringAttributes: {
					'agentstudio.bridge.frame_jank.kind': 'dropped_frame',
					'agentstudio.bridge.phase': 'frame_jank',
					'agentstudio.bridge.plane': 'control',
					'agentstudio.bridge.priority': 'hot',
					'agentstudio.bridge.result': 'success',
					'agentstudio.bridge.slice': 'frame_jank',
					'agentstudio.bridge.transport': 'local',
					'agentstudio.bridge.viewer': 'review',
				},
				numericAttributes: {
					'agentstudio.bridge.frame_jank.dropped_frame.count': 1,
					'agentstudio.bridge.frame_jank.dropped_frame.worst_gap_ms': 48,
					'agentstudio.bridge.frame_jank.long_task.count': 0,
					'agentstudio.bridge.frame_jank.long_task.max_ms': 0,
					'agentstudio.bridge.frame_jank.long_task.total_ms': 0,
				},
				booleanAttributes: {
					'agentstudio.bridge.viewer.active': true,
				},
			},
			{
				scope: 'web',
				name: 'performance.bridge.trees.click_to_row_highlight',
				durationMilliseconds: 4,
				traceContext: null,
				stringAttributes: {
					'agentstudio.bridge.input.source': 'mouse',
					'agentstudio.bridge.phase': 'click_to_row_highlight',
					'agentstudio.bridge.plane': 'data',
					'agentstudio.bridge.priority': 'hot',
					'agentstudio.bridge.result': 'success',
					'agentstudio.bridge.slice': 'tree_prepare_input',
					'agentstudio.bridge.transport': 'worker',
					'agentstudio.bridge.viewer': 'review',
				},
				numericAttributes: {
					'agentstudio.bridge.visible_item.count': 12,
				},
				booleanAttributes: {
					'agentstudio.bridge.already_selected': false,
					'agentstudio.bridge.scroll.active': false,
				},
			},
			{
				scope: 'web',
				name: 'performance.bridge.web.code_view_item_materialize',
				durationMilliseconds: 8,
				traceContext: null,
				stringAttributes: {
					'agentstudio.bridge.content_bytes_bucket': 'small',
					'agentstudio.bridge.item_count_bucket': 'medium',
					'agentstudio.bridge.language_class': 'typescript',
					'agentstudio.bridge.phase': 'code_view_item_materialize',
					'agentstudio.bridge.plane': 'data',
					'agentstudio.bridge.priority': 'hot',
					'agentstudio.bridge.result': 'added',
					'agentstudio.bridge.slice': 'code_view_item',
					'agentstudio.bridge.transport': 'worker',
					'agentstudio.bridge.viewer': 'review',
				},
				numericAttributes: {},
				booleanAttributes: {
					'agentstudio.bridge.selected': true,
				},
			},
			{
				scope: 'web',
				name: 'performance.bridge.web.selected_content_painted',
				durationMilliseconds: 16,
				traceContext: null,
				stringAttributes: {
					'agentstudio.bridge.phase': 'selected_content_painted',
					'agentstudio.bridge.plane': 'data',
					'agentstudio.bridge.priority': 'hot',
					'agentstudio.bridge.slice': 'code_view_item',
					'agentstudio.bridge.transport': 'worker',
					'agentstudio.bridge.viewer': 'review',
				},
				numericAttributes: {
					'agentstudio.bridge.selected_content.click_to_paint_ms': 16,
					'agentstudio.bridge.selected_content.frame_wait_ms': 4,
					'agentstudio.bridge.selected_content.materialize_ms': 8,
				},
				booleanAttributes: {},
			},
			{
				scope: 'web',
				name: 'performance.bridge.web.selection_commit',
				durationMilliseconds: null,
				traceContext: null,
				stringAttributes: {
					'agentstudio.bridge.phase': 'selection_commit',
					'agentstudio.bridge.plane': 'data',
					'agentstudio.bridge.priority': 'warm',
					'agentstudio.bridge.result': 'success',
					'agentstudio.bridge.result_reason': 'none',
					'agentstudio.bridge.slice': 'review_projection',
					'agentstudio.bridge.transport': 'local',
					'agentstudio.bridge.viewer': 'review',
				},
				numericAttributes: {},
				booleanAttributes: {},
			},
		]);

		await expect(sink.ingestWorkerBatch(priorClickBatch)).resolves.toMatchObject({
			type: 'accepted',
		});

		expect(fetchImpl).toHaveBeenCalledTimes(2);
		expect(sink.snapshot()).toMatchObject({
			acceptedBatchCount: 1,
			acceptedSampleCount: 5,
			failedBatchCount: 0,
			lastError: null,
		});
	});

	test('retains the earliest worker-task cohort for the proof-sized performance workload', async () => {
		const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 200 }));
		const sink = createBridgeDevTelemetrySink({
			fetchImpl,
			marker: 'vite-dev-proof-1',
			nowUnixNano: () => '1782218790000000000',
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});
		const earliestSelectedWorkerTask: BridgeTelemetrySample = {
			scope: 'web',
			name: 'performance.bridge.worker.task',
			durationMilliseconds: 4,
			traceContext: null,
			stringAttributes: {
				'agentstudio.bridge.phase': 'worker_task',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'hot',
				'agentstudio.bridge.result': 'success',
				'agentstudio.bridge.slice': 'worker_task',
				'agentstudio.bridge.transport': 'worker',
				'agentstudio.bridge.worker.action': 'applySelectedFact',
				'agentstudio.bridge.worker.command': 'select',
				'agentstudio.bridge.worker.lane': 'selected',
				'agentstudio.bridge.worker.payload_class': 'control',
				'agentstudio.bridge.worker.task_kind': 'message_handler',
				'agentstudio.bridge.worker.work_kind': 'command',
			},
			numericAttributes: {
				'agentstudio.bridge.worker.handler_duration_ms': 4,
				'agentstudio.bridge.worker.queue_wait_ms': 2,
			},
			booleanAttributes: {},
		};
		const laterPerformanceSamples = Array.from(
			{ length: 8_191 },
			(): BridgeTelemetrySample => makeSafePerformanceSample(),
		);

		await expect(
			sink.recordNativeObservation({
				source: 'server',
				scenario: 'authoritative-worktree-performance',
				samples: [earliestSelectedWorkerTask, ...laterPerformanceSamples],
			}),
		).resolves.toBe(true);

		expect(fetchImpl).toHaveBeenCalledTimes(2);
		expect(sink.snapshot().recentSamples).toHaveLength(8_192);
		expect(sink.snapshot().recentSamples[0]).toEqual(earliestSelectedWorkerTask);
	});
});

function makeSafePerformanceSample(): BridgeTelemetrySample {
	return {
		scope: 'web',
		name: 'performance.bridge.web.first_render',
		durationMilliseconds: 12,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'render',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.slice': 'diff_package_metadata',
			'agentstudio.bridge.transport': 'push',
		},
		numericAttributes: {},
		booleanAttributes: {},
	};
}

function makeTelemetryBatch(
	samples: readonly BridgeTelemetrySample[],
): BridgeTelemetryWorkerBatchRequest {
	return {
		type: 'telemetry.batch',
		schemaVersion: 2,
		telemetrySessionId: 'vite-dev-session-1',
		batchSequence: 1,
		samples: samples.map((sample, index) => ({
			producerId: 'main',
			producerSequence: index + 1,
			sample: {
				type: 'event.required',
				timestampMilliseconds: index + 1,
				sample,
			},
		})),
		lossSummaries: [],
	};
}
