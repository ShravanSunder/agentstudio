import { describe, expect, test, vi } from 'vitest';

import type { BridgeTelemetryWorkerBatchRequest } from '../../src/core/telemetry-worker/bridge-telemetry-worker-contracts.js';
import type { BridgeTelemetrySample } from '../../src/foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeTelemetryRecorder } from '../../src/foundation/telemetry/bridge-telemetry-recorder.js';
import {
	recordBridgeTreeAnchorRestoreTelemetrySample,
	recordBridgeTreeHoverToRenderTelemetrySample,
	recordBridgeTreeScrollToPathTelemetrySample,
} from '../../src/foundation/telemetry/bridge-tree-telemetry-adapter.js';
import {
	recordBridgeReviewContentDemandTelemetrySample,
	recordBridgeViewerFileOpenReadyTelemetrySample,
	recordBridgeViewerWorktreeFileTreeTelemetrySample,
	recordBridgeWorktreeFileVisibleDemandSettledTelemetrySample,
} from '../../src/foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import { createBridgeDevTelemetrySink } from './bridge-dev-telemetry.js';

describe('Bridge dev telemetry current File emitters', () => {
	test('accepts the canonical File-open-ready sample', async () => {
		// Arrange
		const samples: BridgeTelemetrySample[] = [];
		recordBridgeViewerFileOpenReadyTelemetrySample({
			demandQueueWaitMilliseconds: 2,
			disposition: 'cold-loaded',
			durationMilliseconds: 12,
			estimatedBytes: 256,
			executorInFlightMilliseconds: 4,
			executorPendingWaitMilliseconds: 1,
			lane: 'foreground',
			requestId: 7,
			resourceBodyRegistryCommitMilliseconds: 3,
			resourceFetchResponseWaitMilliseconds: 2,
			resourceFirstChunkWaitMilliseconds: 1,
			resourceStreamReadMilliseconds: 2,
			result: 'success',
			resultReason: null,
			sourceGeneration: 3,
			telemetryRecorder: recordingTelemetryRecorder(samples),
			traceContext: null,
		});
		const sink = createBridgeDevTelemetrySink({
			fetchImpl: vi.fn(async (): Promise<Response> => new Response('', { status: 200 })),
		});

		// Act
		const response = await sink.ingestWorkerBatch(telemetryBatch(samples));

		// Assert
		expect(response).toMatchObject({ type: 'accepted', acceptedSampleCount: 1 });
		expect(sink.snapshot()).toMatchObject({
			failedBatchCount: 0,
			lastError: null,
		});
	});

	test('accepts current File tree, demand, anchor, and scroll samples', async () => {
		// Arrange
		const samples: BridgeTelemetrySample[] = [];
		const telemetryRecorder = recordingTelemetryRecorder(samples);
		recordBridgeViewerWorktreeFileTreeTelemetrySample({
			descriptorCount: 2_048,
			durationMilliseconds: 7,
			frameCount: 4,
			phase: 'worktree_file_projection',
			result: 'success',
			telemetryRecorder,
			traceContext: null,
			treeRowCount: 4_409,
			treeWindowRowCount: 1_024,
		});
		recordBridgeReviewContentDemandTelemetrySample({
			activeIntentCount: 2,
			deferredCount: 1,
			durationMilliseconds: 4,
			failedCount: 0,
			foregroundIntentCount: 1,
			idleIntentCount: 0,
			interest: 'selected',
			intentCount: 3,
			loadedCount: 2,
			nearbyIntentCount: 0,
			result: 'success',
			resultReason: null,
			speculativeIntentCount: 0,
			telemetryRecorder,
			traceContext: null,
			viewer: 'review',
			visibleIntentCount: 1,
		});
		recordBridgeWorktreeFileVisibleDemandSettledTelemetrySample({
			demandQueueWaitMilliseconds: 1,
			durationMilliseconds: 5,
			enqueueAcceptedCount: 2,
			enqueueRejectedCount: 0,
			executorInFlightMilliseconds: 2,
			executorPendingWaitMilliseconds: 1,
			failedCount: 0,
			firstChunkWaitMilliseconds: 1,
			intentCount: 2,
			lane: 'visible',
			loadedCount: 2,
			requestId: 8,
			responseWaitMilliseconds: 2,
			result: 'success',
			resultReason: null,
			streamReadMilliseconds: 2,
			telemetryRecorder,
			traceContext: null,
			visibleItemCount: 12,
		});
		recordBridgeTreeAnchorRestoreTelemetrySample({
			callCount: 1,
			directScrollTopWriteCount: 0,
			durationMilliseconds: 2,
			phase: 'raf_restore',
			syntheticScrollCount: 1,
			telemetryRecorder,
			traceContext: null,
		});
		recordBridgeTreeScrollToPathTelemetrySample({
			durationMilliseconds: 3,
			focus: true,
			offset: 'nearest',
			reason: 'selected_path_effect',
			telemetryRecorder,
			traceContext: null,
			viewer: 'file',
		});
		const sink = createBridgeDevTelemetrySink({
			fetchImpl: vi.fn(async (): Promise<Response> => new Response('', { status: 200 })),
		});

		// Act
		const response = await sink.ingestWorkerBatch(telemetryBatch(samples));

		// Assert
		expect(response).toMatchObject({ type: 'accepted', acceptedSampleCount: 5 });
		expect(sink.snapshot()).toMatchObject({ failedBatchCount: 0, lastError: null });
	});

	test('accepts the current bounded hover-to-render aggregate', async () => {
		vi.useFakeTimers();
		try {
			// Arrange
			const samples: BridgeTelemetrySample[] = [];
			recordBridgeTreeHoverToRenderTelemetrySample({
				durationMilliseconds: 7,
				result: 'success',
				rowMounted: true,
				telemetryRecorder: recordingTelemetryRecorder(samples),
				traceContext: null,
				viewer: 'file',
				visibleItemCount: 12,
			});
			await vi.advanceTimersByTimeAsync(50);
			const sink = createBridgeDevTelemetrySink({
				fetchImpl: vi.fn(async (): Promise<Response> => new Response('', { status: 200 })),
			});

			// Act
			const response = await sink.ingestWorkerBatch(telemetryBatch(samples));

			// Assert
			expect(response).toMatchObject({ type: 'accepted', acceptedSampleCount: 1 });
			expect(sink.snapshot()).toMatchObject({ failedBatchCount: 0, lastError: null });
		} finally {
			vi.useRealTimers();
		}
	});

	test('rejects values outside the current closed File string enums', async () => {
		// Arrange
		const emittedSamples: BridgeTelemetrySample[] = [];
		recordBridgeTreeScrollToPathTelemetrySample({
			durationMilliseconds: 3,
			focus: true,
			offset: 'nearest',
			reason: 'selected_path_effect',
			telemetryRecorder: recordingTelemetryRecorder(emittedSamples),
			traceContext: null,
			viewer: 'file',
		});
		const emittedSample = emittedSamples[0];
		if (emittedSample === undefined) {
			throw new Error('Expected the current File scroll emitter to record one sample.');
		}
		const sampleWithUnknownOffset: BridgeTelemetrySample = {
			...emittedSample,
			stringAttributes: {
				...emittedSample.stringAttributes,
				'agentstudio.bridge.scroll.offset': 'sideways',
			},
		};
		const fetchImpl = vi.fn(async (): Promise<Response> => new Response('', { status: 200 }));
		const sink = createBridgeDevTelemetrySink({ fetchImpl });

		// Act
		const response = await sink.ingestWorkerBatch(telemetryBatch([sampleWithUnknownOffset]));

		// Assert
		expect(response).toMatchObject({ type: 'rejected', reason: 'invalid_body' });
		expect(fetchImpl).not.toHaveBeenCalled();
		expect(sink.snapshot()).toMatchObject({
			failedBatchCount: 1,
			lastError: 'unsafe_attributes',
		});
	});
});

function recordingTelemetryRecorder(samples: BridgeTelemetrySample[]): BridgeTelemetryRecorder {
	return {
		flush: (): boolean => true,
		isEnabled: (): boolean => true,
		measure: <TResult>(props: { readonly operation: () => TResult }): TResult => props.operation(),
		record: (sample): void => {
			samples.push(sample);
		},
	};
}

function telemetryBatch(
	samples: readonly BridgeTelemetrySample[],
): BridgeTelemetryWorkerBatchRequest {
	return {
		batchSequence: 1,
		lossSummaries: [],
		samples: samples.map((sample, index) => ({
			producerId: 'main',
			producerSequence: index + 1,
			sample: {
				sample,
				timestampMilliseconds: index + 1,
				type: 'event.required',
			},
		})),
		schemaVersion: 2,
		telemetrySessionId: 'vite-dev-current-file-emitter-session',
		type: 'telemetry.batch',
	};
}
