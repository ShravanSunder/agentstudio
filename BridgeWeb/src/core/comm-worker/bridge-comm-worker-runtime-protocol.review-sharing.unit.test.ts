import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerReviewSourceUpdateCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import {
	assertBridgeCommWorkerPreparationDrain,
	createBridgeWorkerSequenceCounter,
	createDeferredTextResponse,
	createRecordingBridgeCommWorkerPort,
	descriptorByUrl,
	flushBridgeWorkerRuntimeContinuations,
	makeContentRequestDescriptor,
	makeRenderSemantics,
	makeWorkerReviewContentMetadata,
	type DeferredTextResponse,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';

describe('Bridge comm worker runtime Review demand sharing', () => {
	test('promotes in-flight visible Review demand to selected without duplicate fetch', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const deferredResponsesByUrl = new Map<string, DeferredTextResponse>();
		const fetchCallsByUrl = new Map<string, number>();
		const baseDescriptor = makeContentRequestDescriptor({
			generation: 4,
			itemId: 'item-1',
			role: 'base',
			text: 'let previousValue = 1;\n',
		});
		const headDescriptor = makeContentRequestDescriptor({
			generation: 4,
			itemId: 'item-1',
			role: 'head',
			text: 'let nextValue = 2;\n',
		});

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [baseDescriptor, headDescriptor],
			createSequence: createBridgeWorkerSequenceCounter(1001),
			fetchContent: (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				fetchCallsByUrl.set(url, (fetchCallsByUrl.get(url) ?? 0) + 1);
				const deferredResponse = createDeferredTextResponse();
				deferredResponsesByUrl.set(url, deferredResponse);
				return deferredResponse.promise;
			},
			pump: createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => clockMs }),
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-before-selected-promote',
				epoch: 5,
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		const visibleDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(deferredResponsesByUrl.size).toBe(2);
		expect(fetchCallsByUrl.get(baseDescriptor.resourceUrl)).toBe(1);
		expect(fetchCallsByUrl.get(headDescriptor.resourceUrl)).toBe(1);

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-visible-in-flight',
				epoch: 6,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		const selectedDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(fetchCallsByUrl.get(baseDescriptor.resourceUrl)).toBe(1);
		expect(fetchCallsByUrl.get(headDescriptor.resourceUrl)).toBe(1);
		deferredResponsesByUrl.get(baseDescriptor.resourceUrl)?.resolve('let previousValue = 1;\n');
		deferredResponsesByUrl.get(headDescriptor.resourceUrl)?.resolve('let nextValue = 2;\n');
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[2])();
		await selectedDrain;
		await visibleDrain;

		const pierreJobMessages = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'pierreRenderJob' ? [postedMessage.message] : [],
		);
		expect(pierreJobMessages).toHaveLength(1);
		expect(pierreJobMessages[0]?.job.bridgeDemandRank).toEqual({ lane: 'selected', priority: 0 });
		const pierreJob = pierreJobMessages[0]?.job;
		expect(pierreJob?.payload.kind).toBe('codeViewDiffItem');
		if (pierreJob?.payload.kind === 'codeViewDiffItem') {
			expect(pierreJob.payload.item.fileDiff.deletionLines).toContain('let previousValue = 1;\n');
			expect(pierreJob.payload.item.fileDiff.additionLines).toContain('let nextValue = 2;\n');
		}
	});

	test('keeps streamed byte-limit enforcement when selected shares visible Review fetches', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const deferredResponsesByUrl = new Map<string, DeferredTextResponse>();
		const baseDescriptor = {
			...makeContentRequestDescriptor({
				generation: 4,
				itemId: 'item-1',
				role: 'base',
				text: 'oversized base',
			}),
			sizeBytes: 4,
			expectedBytes: 4,
			maxBytes: 4,
		};
		const headDescriptor = {
			...makeContentRequestDescriptor({
				generation: 4,
				itemId: 'item-1',
				role: 'head',
				text: 'oversized head',
			}),
			sizeBytes: 4,
			expectedBytes: 4,
			maxBytes: 4,
		};
		let arrayBufferCallCount = 0;

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [baseDescriptor, headDescriptor],
			createSequence: createBridgeWorkerSequenceCounter(1101),
			fetchContent: (url: string): Promise<Response> => {
				if (!descriptorByUrl.has(url)) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				const deferredResponse = createDeferredTextResponse();
				deferredResponsesByUrl.set(url, {
					promise: deferredResponse.promise.then((response) => {
						Object.defineProperty(response, 'arrayBuffer', {
							value: (): Promise<ArrayBuffer> => {
								arrayBufferCallCount += 1;
								throw new Error('Shared review fetch must preserve streamed reads.');
							},
						});
						return response;
					}),
					resolve: deferredResponse.resolve,
				});
				return deferredResponsesByUrl.get(url)?.promise ?? deferredResponse.promise;
			},
			pump: createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => clockMs }),
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-before-selected-stream-guard',
				epoch: 5,
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		const visibleDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-stream-guard',
				epoch: 6,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		const selectedDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await flushBridgeWorkerRuntimeContinuations();
		deferredResponsesByUrl.get(baseDescriptor.resourceUrl)?.resolve('too large for descriptor\n');
		deferredResponsesByUrl
			.get(headDescriptor.resourceUrl)
			?.resolve('also too large for descriptor\n');
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[2])();
		await selectedDrain;
		await visibleDrain;

		expect(arrayBufferCallCount).toBe(0);
		expect(
			postedMessages.some(
				(postedMessage) =>
					postedMessage.message.kind === 'slicePatch' &&
					postedMessage.message.patches.some(
						(patch) =>
							patch.slice === 'contentAvailability' &&
							patch.operation === 'upsert' &&
							patch.itemId === 'item-1' &&
							patch.payload.state === 'failed',
					),
			),
		).toBe(true);
	});

	test('does not share in-flight Review resources across changed descriptor byte bounds', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const deferredResponsesByFetchCall: DeferredTextResponse[] = [];
		const fetchCallsByUrl = new Map<string, number>();
		const baseDescriptor = makeContentRequestDescriptor({
			generation: 4,
			itemId: 'item-1',
			role: 'base',
			text: 'base content',
		});
		const firstHeadDescriptor = makeContentRequestDescriptor({
			generation: 4,
			itemId: 'item-1',
			role: 'head',
			text: 'first content',
		});
		const updatedHeadDescriptor = {
			...firstHeadDescriptor,
			expectedBytes: undefined,
			maxBytes: 64,
		};

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [baseDescriptor, firstHeadDescriptor],
			createSequence: createBridgeWorkerSequenceCounter(1201),
			fetchContent: (url: string): Promise<Response> => {
				if (!descriptorByUrl.has(url)) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				fetchCallsByUrl.set(url, (fetchCallsByUrl.get(url) ?? 0) + 1);
				const deferredResponse = createDeferredTextResponse();
				deferredResponsesByFetchCall.push(deferredResponse);
				return deferredResponse.promise;
			},
			pump: createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => clockMs }),
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-before-descriptor-identity-change',
				epoch: 5,
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		const visibleDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(fetchCallsByUrl.get(baseDescriptor.resourceUrl)).toBe(1);
		expect(fetchCallsByUrl.get(firstHeadDescriptor.resourceUrl)).toBe(1);

		dispatch.message(
			encodeBridgeWorkerReviewSourceUpdateCommand({
				requestId: 'request-descriptor-byte-bounds-change-same-url',
				epoch: 6,
				contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
				contentRequestDescriptors: [baseDescriptor, updatedHeadDescriptor],
				renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-after-descriptor-byte-bounds-change',
				epoch: 7,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		const selectedDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(fetchCallsByUrl.get(baseDescriptor.resourceUrl)).toBe(1);
		expect(fetchCallsByUrl.get(firstHeadDescriptor.resourceUrl)).toBe(2);

		deferredResponsesByFetchCall[0]?.resolve('base content');
		deferredResponsesByFetchCall[1]?.resolve('first content');
		deferredResponsesByFetchCall[2]?.resolve('let updatedHeadValue = 2;\n');
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[2])();
		await selectedDrain;
		await visibleDrain;

		const pierreJobMessages = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'pierreRenderJob' ? [postedMessage.message] : [],
		);
		expect(pierreJobMessages).toHaveLength(1);
	});
});
