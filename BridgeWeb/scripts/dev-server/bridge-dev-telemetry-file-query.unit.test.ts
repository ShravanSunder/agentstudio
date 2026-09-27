import { describe, expect, test, vi } from 'vitest';

import {
	recordBridgeCommWorkerFileQueryDiagnosticPhase,
	recordBridgeMainFileQueryDiagnosticPhase,
} from '../../src/core/comm-worker/bridge-comm-worker-telemetry.js';
import type { BridgeTelemetryWorkerBatchRequest } from '../../src/core/telemetry-worker/bridge-telemetry-worker-contracts.js';
import type { BridgeTelemetrySample } from '../../src/foundation/telemetry/bridge-telemetry-event.js';
import { createBridgeDevTelemetrySink } from './bridge-dev-telemetry.js';

describe('Bridge dev File query telemetry contract', () => {
	test('accepts every emitted File query telemetry variant and rejects an unlisted phase', async () => {
		const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 200 }));
		const sink = createBridgeDevTelemetrySink({
			fetchImpl,
			marker: 'vite-dev-proof-1',
			nowUnixNano: () => '1782218790000000000',
			serviceVersion: 'vite-dev',
			worktreeHash: 'wt-hash',
		});
		const emittedSamples: BridgeTelemetrySample[] = [];
		const telemetryClient = {
			record: (sample: BridgeTelemetrySample): void => {
				emittedSamples.push(sample);
			},
		};

		recordBridgeCommWorkerFileQueryDiagnosticPhase({ phase: 'command_received', telemetryClient });
		recordBridgeCommWorkerFileQueryDiagnosticPhase({
			chunkIndex: 0,
			phase: 'chunk_started',
			telemetryClient,
		});
		recordBridgeCommWorkerFileQueryDiagnosticPhase({
			chunkIndex: 0,
			evaluatedRowCount: 128,
			phase: 'chunk_completed',
			telemetryClient,
		});
		recordBridgeCommWorkerFileQueryDiagnosticPhase({
			phase: 'projection_published',
			telemetryClient,
		});
		recordBridgeCommWorkerFileQueryDiagnosticPhase({ phase: 'outcome_published', telemetryClient });

		recordBridgeMainFileQueryDiagnosticPhase({
			batchCount: 2,
			batchIndex: 1,
			pageHidden: true,
			phase: 'patch_received',
			telemetryClient,
		});
		recordBridgeMainFileQueryDiagnosticPhase({
			batchCount: 2,
			batchIndex: 1,
			pageHidden: true,
			phase: 'applier_batch_accepted',
			telemetryClient,
		});
		recordBridgeMainFileQueryDiagnosticPhase({
			batchCount: 2,
			batchIndex: 1,
			pageHidden: true,
			phase: 'applier_batch_rejected_stale',
			telemetryClient,
		});
		recordBridgeMainFileQueryDiagnosticPhase({
			batchCount: 2,
			batchIndex: 1,
			pageHidden: true,
			phase: 'applier_batch_rejected_protocol',
			telemetryClient,
		});
		recordBridgeMainFileQueryDiagnosticPhase({
			batchCount: 2,
			batchIndex: 1,
			pageHidden: true,
			phase: 'applier_batch_buffered_after_commit',
			telemetryClient,
		});
		recordBridgeMainFileQueryDiagnosticPhase({
			batchCount: 2,
			batchIndex: 2,
			pageHidden: true,
			phase: 'transaction_committed',
			telemetryClient,
		});
		recordBridgeMainFileQueryDiagnosticPhase({
			displayItemCount: 1,
			pageHidden: true,
			phase: 'snapshot_published',
			treeRowCount: 2,
			telemetryClient,
		});
		recordBridgeMainFileQueryDiagnosticPhase({
			displayItemCount: 1,
			pageHidden: true,
			phase: 'render_consumer_committed',
			queryKeyMatchesInput: true,
			treeRowCount: 2,
			telemetryClient,
		});
		recordBridgeMainFileQueryDiagnosticPhase({
			pageHidden: true,
			phase: 'tree_stream_received',
			telemetryClient,
		});
		recordBridgeMainFileQueryDiagnosticPhase({
			pageHidden: true,
			phase: 'tree_task_started',
			telemetryClient,
		});
		recordBridgeMainFileQueryDiagnosticPhase({
			pageHidden: true,
			phase: 'tree_turn_completed',
			telemetryClient,
		});

		expect(emittedSamples).toHaveLength(16);
		const admission = await sink.ingestWorkerBatch(makeTelemetryBatchFromSamples(emittedSamples));
		expect(sink.snapshot().lastError).toBeNull();
		expect(admission).toMatchObject({
			type: 'accepted',
			acceptedSampleCount: 16,
		});
		expect(fetchImpl).toHaveBeenCalledTimes(2);

		const renderConsumerSample = emittedSamples.find(
			(sample) =>
				sample.stringAttributes['agentstudio.bridge.file_query.diagnostic.phase'] ===
				'render_consumer_committed',
		);
		if (renderConsumerSample === undefined) {
			throw new Error('Render-consumer query sample was not emitted.');
		}
		const invalidRenderConsumerSample: BridgeTelemetrySample = {
			...renderConsumerSample,
			stringAttributes: {
				...renderConsumerSample.stringAttributes,
				'agentstudio.bridge.file_query.diagnostic.phase': 'unlisted_phase',
			},
		};
		const strictSink = createBridgeDevTelemetrySink({ fetchImpl });
		await expect(
			strictSink.ingestWorkerBatch(makeTelemetryBatch(invalidRenderConsumerSample)),
		).resolves.toMatchObject({
			type: 'rejected',
			reason: 'invalid_body',
		});
		expect(strictSink.snapshot().lastError).toBe('unsafe_attributes');

		const commandReceivedSample = emittedSamples.find(
			(sample) =>
				sample.stringAttributes['agentstudio.bridge.worker.file_query.phase'] ===
				'command_received',
		);
		if (commandReceivedSample === undefined) {
			throw new Error('Worker command-received query sample was not emitted.');
		}
		const invalidWorkerSample: BridgeTelemetrySample = {
			...commandReceivedSample,
			stringAttributes: {
				...commandReceivedSample.stringAttributes,
				'agentstudio.bridge.worker.file_query.phase': 'unlisted_phase',
			},
		};
		const strictWorkerSink = createBridgeDevTelemetrySink({ fetchImpl });
		await expect(
			strictWorkerSink.ingestWorkerBatch(makeTelemetryBatch(invalidWorkerSample)),
		).resolves.toMatchObject({
			type: 'rejected',
			reason: 'invalid_body',
		});
		expect(strictWorkerSink.snapshot().lastError).toBe('unsafe_attributes');
	});
});

function makeTelemetryBatch(
	sample: BridgeTelemetrySample,
	batchSequence = 1,
): BridgeTelemetryWorkerBatchRequest {
	return makeTelemetryBatchFromSamples([sample], batchSequence);
}

function makeTelemetryBatchFromSamples(
	samples: readonly BridgeTelemetrySample[],
	batchSequence = 1,
): BridgeTelemetryWorkerBatchRequest {
	let producerSequence = 0;
	const stampedSamples = samples.map((sample) => {
		producerSequence += 1;
		const type: 'event.optional' | 'event.required' =
			sample.stringAttributes['agentstudio.bridge.priority'] === 'best_effort'
				? 'event.optional'
				: 'event.required';
		return {
			producerId: 'main' as const,
			producerSequence,
			sample: {
				type,
				timestampMilliseconds: producerSequence,
				sample,
			},
		};
	});
	return {
		type: 'telemetry.batch',
		schemaVersion: 2,
		telemetrySessionId: 'vite-dev-file-query-session',
		batchSequence,
		samples: stampedSamples,
		lossSummaries: [],
	};
}
