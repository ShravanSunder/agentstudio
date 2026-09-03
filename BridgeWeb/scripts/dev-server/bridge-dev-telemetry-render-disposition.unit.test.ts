import { describe, expect, test } from 'vitest';

import { recordBridgeWorkerOutstandingPublicationTelemetry } from '../../src/core/comm-worker/bridge-render-disposition-telemetry.js';
import type { BridgeTelemetrySample } from '../../src/foundation/telemetry/bridge-telemetry-event.js';
import { bridgeDevTelemetryObservationIsSafe } from './bridge-dev-telemetry-otlp.js';

describe('Bridge dev render disposition telemetry', () => {
	test('admits semantic class and bounded render disposition observations', () => {
		const samples = [
			workerTaskSample(),
			renderDispositionAdmissionSample(),
			workerRenderDispositionBatchSample(),
			workerRenderPublicationOutstandingSample(),
		] satisfies readonly BridgeTelemetrySample[];

		expect(
			bridgeDevTelemetryObservationIsSafe({
				samples,
				scenario: 'bridge-worker-v2',
			}),
		).toBe(true);
	});

	test('rejects source identity on worker outstanding-publication observations', () => {
		const sample = workerRenderPublicationOutstandingSample();
		expect(
			bridgeDevTelemetryObservationIsSafe({
				samples: [
					{
						...sample,
						stringAttributes: {
							...sample.stringAttributes,
							'agentstudio.bridge.source.identity': 'private-source',
						},
					},
				],
				scenario: 'bridge-worker-v2',
			}),
		).toBe(false);
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

	test('keeps outstanding-publication telemetry failure observational', () => {
		expect((): void => {
			recordBridgeWorkerOutstandingPublicationTelemetry({
				observation: {
					currentCount: 1,
					highWaterMark: 1,
					oldestAgeMilliseconds: 5,
					outcome: 'published',
					phase: 'render_publication_outstanding_changed',
				},
				surface: 'review',
				telemetryClient: {
					record: (): never => {
						throw new Error('telemetry unavailable');
					},
				},
			});
		}).not.toThrow();
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
			'agentstudio.bridge.render_disposition.in_flight_count': 64,
			'agentstudio.bridge.render_disposition.oldest_pending_age_ms': 2,
			'agentstudio.bridge.render_disposition.pending_count': 3,
			'agentstudio.bridge.render_disposition.pending_high_water_mark': 65,
			'agentstudio.bridge.render_disposition.produced_count': 66,
			'agentstudio.bridge.render_disposition.retained_count': 67,
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

function workerRenderPublicationOutstandingSample(): BridgeTelemetrySample {
	return {
		scope: 'web',
		name: 'performance.bridge.worker.render_publication_outstanding',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'render_disposition_response_posted_before_owner_effect',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.render_publication.outcome': 'queued',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.slice': 'command_acks',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.viewer': 'review',
		},
		numericAttributes: {
			'agentstudio.bridge.render_publication.current_count': 12,
			'agentstudio.bridge.render_publication.high_water_mark': 12,
			'agentstudio.bridge.render_publication.oldest_age_ms': 25,
		},
		booleanAttributes: {},
	};
}
