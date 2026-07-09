import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import { encodeBridgeWorkerSelectCommand } from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import {
	assertBridgeCommWorkerPreparationDrain,
	createRecordingBridgeCommWorkerPort,
	createDeferredTextResponse,
	descriptorByUrl,
	flushBridgeWorkerRuntimeContinuations,
	makeContentRequestDescriptor,
	makeRenderSemantics,
	makeWorkerReviewContentMetadata,
	type DeferredTextResponse,
} from './bridge-comm-worker-runtime-protocol.test-support.js';

describe('Bridge comm worker runtime protocol telemetry', () => {
	test('records command queue wait and handler duration from typed dispatch timestamp', () => {
		const clockReadings = [18, 18, 22];
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const { dispatch } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [],
			now: () => {
				const value = clockReadings.shift();
				if (value === undefined) {
					throw new Error('Unexpected runtime clock read.');
				}
				return value;
			},
			renderSemantics: [],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (): void => {},
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 3,
				issuedAtMilliseconds: 10,
				requestId: 'request-select',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.worker.task',
				durationMilliseconds: 4,
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.result': 'success',
					'agentstudio.bridge.worker.command': 'select',
					'agentstudio.bridge.worker.lane': 'selected',
					'agentstudio.bridge.worker.task_kind': 'message_handler',
				}),
				numericAttributes: expect.objectContaining({
					'agentstudio.bridge.worker.handler_duration_ms': 4,
					'agentstudio.bridge.worker.queue_wait_ms': 8,
				}),
			}),
		);
	});

	test('threads runtime telemetry client into stale selected review preparation drops', async () => {
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch } = createRecordingBridgeCommWorkerPort();
		const deferredResponsesByUrl = new Map<string, DeferredTextResponse>();
		const baseDescriptor = makeContentRequestDescriptor({
			itemId: 'item-1',
			role: 'base',
			text: 'base content\n',
		});
		const headDescriptor = makeContentRequestDescriptor({
			itemId: 'item-1',
			role: 'head',
			text: 'head content\n',
		});

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [baseDescriptor, headDescriptor],
			fetchContent: (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				const deferredResponse = createDeferredTextResponse();
				deferredResponsesByUrl.set(url, deferredResponse);
				return deferredResponse.promise;
			},
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [
				{ id: 'item-1', parentId: null, index: 0 },
				{ id: 'item-2', parentId: null, index: 1 },
			],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 7,
				requestId: 'request-select-item-1',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		const firstDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 8,
				requestId: 'request-select-item-2',
				selectedItemId: 'item-2',
				selectedSource: 'user',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		deferredResponsesByUrl.get(baseDescriptor.resourceUrl)?.resolve('base content\n');
		deferredResponsesByUrl.get(headDescriptor.resourceUrl)?.resolve('head content\n');
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await firstDrain;

		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.web.selected_content_dropped',
				durationMilliseconds: null,
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.drop_reason': 'stale_after_fetch',
					'agentstudio.bridge.phase': 'selected_content_dropped',
					'agentstudio.bridge.result': 'dropped',
					'agentstudio.bridge.viewer': 'review',
				}),
			}),
		);
	});
});
