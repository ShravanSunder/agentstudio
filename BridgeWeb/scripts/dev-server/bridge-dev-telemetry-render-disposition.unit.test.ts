import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../src/foundation/telemetry/bridge-telemetry-event.js';
import { bridgeDevTelemetryObservationIsSafe } from './bridge-dev-telemetry-otlp.js';

describe('Bridge dev render disposition telemetry', () => {
	test('admits semantic class and bounded render disposition observations', () => {
		const samples = [
			workerTaskSample(),
			renderDispositionAdmissionSample(),
			workerRenderDispositionBatchSample(),
		] satisfies readonly BridgeTelemetrySample[];

		expect(
			bridgeDevTelemetryObservationIsSafe({
				samples,
				scenario: 'bridge-worker-v2',
			}),
		).toBe(true);
	});

	test('rejects an unbounded render disposition outcome', () => {
		const sample = renderDispositionAdmissionSample();
		expect(
			bridgeDevTelemetryObservationIsSafe({
				samples: [
					{
						...sample,
						stringAttributes: {
							...sample.stringAttributes,
							'agentstudio.bridge.render_disposition.outcome': 'private-request-id',
						},
					},
				],
				scenario: 'bridge-worker-v2',
			}),
		).toBe(false);
	});
});

function workerTaskSample(): BridgeTelemetrySample {
	return {
		scope: 'web',
		name: 'performance.bridge.worker.task',
		durationMilliseconds: 1,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'worker_task',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.slice': 'worker_task',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.command': 'annotationCommand',
			'agentstudio.bridge.worker.lane': 'selected',
			'agentstudio.bridge.worker.semantic_class': 'urgent_action',
			'agentstudio.bridge.worker.task_kind': 'message_handler',
		},
		numericAttributes: {
			'agentstudio.bridge.worker.handler_duration_ms': 1,
			'agentstudio.bridge.worker.queue_wait_ms': 2,
		},
		booleanAttributes: {},
	};
}

function renderDispositionAdmissionSample(): BridgeTelemetrySample {
	return {
		scope: 'web',
		name: 'performance.bridge.web.render_disposition_admission',
		durationMilliseconds: 3,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'render_disposition_batch_terminal',
			'agentstudio.bridge.plane': 'control',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.render_disposition.outcome': 'acked',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.slice': 'command_acks',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.viewer': 'review',
		},
		numericAttributes: {
			'agentstudio.bridge.render_disposition.batch_receipt_count': 64,
			'agentstudio.bridge.render_disposition.duplicate_count': 0,
			'agentstudio.bridge.render_disposition.oldest_pending_age_ms': 2,
			'agentstudio.bridge.render_disposition.pending_count': 3,
			'agentstudio.bridge.render_disposition.pending_high_water_mark': 65,
			'agentstudio.bridge.render_disposition.produced_count': 66,
		},
		booleanAttributes: {},
	};
}

function workerRenderDispositionBatchSample(): BridgeTelemetrySample {
	return {
		scope: 'web',
		name: 'performance.bridge.worker.render_disposition_batch',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'render_disposition_batch_applied',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.render_disposition.outcome': 'degraded',
			'agentstudio.bridge.result': 'failed',
			'agentstudio.bridge.slice': 'command_acks',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.viewer': 'review',
		},
		numericAttributes: {
			'agentstudio.bridge.render_disposition.accepted_count': 62,
			'agentstudio.bridge.render_disposition.batch_receipt_count': 64,
			'agentstudio.bridge.render_disposition.duplicate_count': 1,
			'agentstudio.bridge.render_disposition.rejected_count': 1,
		},
		booleanAttributes: {},
	};
}
