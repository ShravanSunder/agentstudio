import { expect, test, vi } from 'vitest';

import type { BridgeTelemetryWorkerBatchRequest } from '../../src/core/telemetry-worker/bridge-telemetry-worker-contracts.js';
import { createBridgeDevTelemetrySink } from './bridge-dev-telemetry.js';

test('Bridge dev telemetry accepts bounded demand metrics shared with native', async () => {
	const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 200 }));
	const sink = createBridgeDevTelemetrySink({ fetchImpl });
	const demandSummaryBatch: BridgeTelemetryWorkerBatchRequest = {
		type: 'telemetry.batch',
		schemaVersion: 2,
		telemetrySessionId: 'vite-dev-demand-session',
		batchSequence: 1,
		samples: [
			{
				producerId: 'main',
				producerSequence: 1,
				sample: {
					type: 'event.required',
					timestampMilliseconds: 1,
					sample: {
						scope: 'web',
						name: 'performance.bridge.trees.worktree_file_demand_summary',
						durationMilliseconds: 4,
						traceContext: null,
						stringAttributes: {
							'agentstudio.bridge.phase': 'worktree_file_demand_summary',
							'agentstudio.bridge.plane': 'data',
							'agentstudio.bridge.priority': 'warm',
							'agentstudio.bridge.result': 'success',
							'agentstudio.bridge.slice': 'tree_prepare_input',
							'agentstudio.bridge.transport': 'worker',
							'agentstudio.bridge.viewer': 'file',
						},
						numericAttributes: {
							'agentstudio.bridge.demand.active.count': 2,
							'agentstudio.bridge.demand.deferred.count': 1,
							'agentstudio.bridge.demand.duration_ms': 4,
							'agentstudio.bridge.demand.enqueue_accepted.count': 3,
							'agentstudio.bridge.demand.enqueue_rejected.count': 0,
							'agentstudio.bridge.demand.executor_in_flight_ms': 2,
							'agentstudio.bridge.demand.executor_pending_wait_ms': 1,
							'agentstudio.bridge.demand.failed.count': 0,
							'agentstudio.bridge.demand.foreground.count': 1,
							'agentstudio.bridge.demand.idle.count': 0,
							'agentstudio.bridge.demand.intent.count': 3,
							'agentstudio.bridge.demand.loaded.count': 2,
							'agentstudio.bridge.demand.nearby.count': 0,
							'agentstudio.bridge.demand.request.sequence': 7,
							'agentstudio.bridge.demand.scheduler_queue_wait_ms': 0.5,
							'agentstudio.bridge.demand.speculative.count': 0,
							'agentstudio.bridge.demand.visible.count': 1,
						},
						booleanAttributes: {},
					},
				},
			},
		],
		lossSummaries: [],
	};

	await expect(sink.ingestWorkerBatch(demandSummaryBatch)).resolves.toMatchObject({
		type: 'accepted',
	});
	expect(sink.snapshot()).toMatchObject({
		acceptedBatchCount: 1,
		acceptedSampleCount: 1,
		failedBatchCount: 0,
		lastError: null,
	});
});
