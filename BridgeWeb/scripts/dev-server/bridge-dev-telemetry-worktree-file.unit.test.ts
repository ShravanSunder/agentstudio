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
	recordBridgeViewerFileOpenReadyTelemetrySample,
	recordBridgeViewerWorktreeFileTreeTelemetrySample,
} from '../../src/foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import { createBridgeDevTelemetrySink } from './bridge-dev-telemetry.js';

describe('Bridge dev Worktree File telemetry', () => {
	test('accepts the canonical progressive File-tree projection sample', async () => {
		// Arrange
		const samples: BridgeTelemetrySample[] = [];
		const telemetryRecorder = recordingTelemetryRecorder(samples);
		recordBridgeViewerWorktreeFileTreeTelemetrySample({
			descriptorCount: 2048,
			durationMilliseconds: 7,
			frameCount: 4,
			phase: 'worktree_file_projection',
			result: 'success',
			telemetryRecorder,
			traceContext: null,
			treeRowCount: 4409,
			treeWindowRowCount: 1024,
		});
		recordBridgeViewerFileOpenReadyTelemetrySample({
			demandQueueWaitMilliseconds: 2,
			disposition: 'cold-loaded',
			durationMilliseconds: 12,
			estimatedBytes: 256,
			executorInFlightMilliseconds: 4,
			executorPendingWaitMilliseconds: 1,
			lane: 'selected',
			requestId: 7,
			resourceBodyRegistryCommitMilliseconds: 3,
			resourceFetchResponseWaitMilliseconds: 2,
			resourceFirstChunkWaitMilliseconds: 1,
			resourceStreamReadMilliseconds: 2,
			result: 'success',
			resultReason: null,
			sourceGeneration: 3,
			telemetryRecorder,
			traceContext: null,
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
		expect(response).toMatchObject({ type: 'accepted', acceptedSampleCount: 4 });
		expect(sink.snapshot()).toMatchObject({ failedBatchCount: 0, lastError: null });
	});

	test('accepts the canonical bounded hover-to-render summary', async () => {
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
		telemetrySessionId: 'vite-dev-worktree-file-session-1',
		type: 'telemetry.batch',
	};
}
