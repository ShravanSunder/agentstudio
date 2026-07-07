import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerFileViewSourceUpdateCommand,
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
	makeFileViewContentRequestDescriptor,
	makeImmediateTextResponse,
	makeRenderSemantics,
	makeWorkerFileViewContentMetadata,
	makeWorkerReviewContentMetadata,
	type DeferredTextResponse,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';

describe('Bridge comm worker runtime protocol', () => {
	test('drains selected review content prep through the worker port after local select slices', async () => {
		let clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [makeWorkerReviewContentMetadata()],
			contentRequestDescriptors: [
				makeContentRequestDescriptor({ role: 'base', text: 'base body' }),
				makeContentRequestDescriptor({ role: 'head', text: 'head body' }),
			],
			createSequence: createBridgeWorkerSequenceCounter(41),
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return makeImmediateTextResponse(descriptor.text);
			},
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			renderSemantics: [makeRenderSemantics()],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 7,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);

		expect(scheduledDrains).toHaveLength(1);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
		]);
		expect(postedMessages[0]?.transferList).toBeUndefined();
		expect(postedMessages[1]?.transferList).toBeUndefined();
		clockMs += 1;

		const firstDrainCompletion = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toHaveLength(2);
		const secondDrainResult = await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		const firstDrainResult = await firstDrainCompletion;

		expect(firstDrainResult.completedIds).toEqual([]);
		expect(firstDrainResult.yielded).toBe(false);
		expect(secondDrainResult.completedIds).toEqual(['review-content-ready:item-1:7:42']);
		expect(secondDrainResult.yielded).toBe(false);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
			'pierreRenderJob',
			'slicePatch',
		]);
		expect(postedMessages[2]?.transferList).toEqual([]);
		expect(postedMessages[2]?.message).toMatchObject({
			kind: 'pierreRenderJob',
			job: {
				itemId: 'item-1',
				renderKind: 'reviewDiff',
				payload: {
					kind: 'codeViewDiffItem',
				},
			},
		});
		const pierreJobMessage = postedMessages[2]?.message;
		if (pierreJobMessage?.kind !== 'pierreRenderJob') {
			throw new Error('Expected Pierre render job message.');
		}
		expect(pierreJobMessage.transferDescriptors).toEqual([
			{
				messageKind: 'pierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: pierreJobMessage.job.payloadByteLength,
				mode: 'clone',
			},
		]);
		expect(postedMessages[3]?.message).toMatchObject({
			kind: 'slicePatch',
			epoch: 7,
			sequence: 42,
			patches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'item-1',
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'ready' },
				},
			],
		});
	});

	test('applies source update before first select when the runtime boots empty', () => {
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [],
			contentRequestDescriptors: [],
			createSequence: createBridgeWorkerSequenceCounter(11),
			renderSemantics: [],
			rows: [],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerReviewSourceUpdateCommand({
				requestId: 'request-source-update',
				epoch: 1,
				contentItems: [makeWorkerReviewContentMetadata()],
				contentRequestDescriptors: [
					makeContentRequestDescriptor({ role: 'base', text: 'base body' }),
					makeContentRequestDescriptor({ role: 'head', text: 'head body' }),
				],
				renderSemantics: [makeRenderSemantics()],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			}),
		);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 2,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);

		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'health',
			'slicePatch',
			'health',
		]);
		expect(postedMessages[1]?.message).toMatchObject({
			kind: 'slicePatch',
			epoch: 2,
			sequence: 11,
			patches: [
				{
					slice: 'selection',
					operation: 'upsert',
					payload: { selectedItemId: 'item-1' },
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'loading' },
				},
			],
		});
		expect(scheduledDrains).toHaveLength(1);
	});

	test('starts visible Review demand from viewport membership through the worker executor', async () => {
		let clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [makeWorkerReviewContentMetadata()],
			contentRequestDescriptors: [
				makeContentRequestDescriptor({ role: 'base', text: 'visible base' }),
				makeContentRequestDescriptor({ role: 'head', text: 'visible head' }),
			],
			createSequence: createBridgeWorkerSequenceCounter(101),
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return makeImmediateTextResponse(descriptor.text);
			},
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			renderSemantics: [makeRenderSemantics()],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-viewport',
				epoch: 5,
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);

		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
		]);
		expect(scheduledDrains).toHaveLength(1);
		clockMs += 1;

		const firstDrainCompletion = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toHaveLength(2);
		const secondDrainResult = await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		const firstDrainResult = await firstDrainCompletion;

		expect(firstDrainResult.completedIds).toEqual([]);
		expect(secondDrainResult.completedIds).toEqual(['review-content-ready:item-1:visible:102']);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
			'pierreRenderJob',
			'slicePatch',
		]);
		expect(postedMessages[2]?.message).toMatchObject({
			kind: 'pierreRenderJob',
			job: {
				itemId: 'item-1',
				bridgeDemandRank: { lane: 'visible', priority: 1 },
				budgetClass: 'visible',
			},
		});
		expect(postedMessages[3]?.message).toMatchObject({
			kind: 'slicePatch',
			epoch: 5,
			sequence: 102,
			patches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'item-1',
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'ready' },
				},
			],
		});
	});

	test('starts visible Review demand after source update repairs an existing viewport', async () => {
		let clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [],
			contentRequestDescriptors: [],
			createSequence: createBridgeWorkerSequenceCounter(201),
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return makeImmediateTextResponse(descriptor.text);
			},
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			renderSemantics: [],
			rows: [],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-before-source',
				epoch: 5,
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
		]);
		expect(scheduledDrains).toEqual([]);

		dispatch.message(
			encodeBridgeWorkerReviewSourceUpdateCommand({
				requestId: 'request-source-after-viewport',
				epoch: 6,
				contentItems: [makeWorkerReviewContentMetadata()],
				contentRequestDescriptors: [
					makeContentRequestDescriptor({ role: 'base', text: 'source repair base' }),
					makeContentRequestDescriptor({ role: 'head', text: 'source repair head' }),
				],
				renderSemantics: [makeRenderSemantics()],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			}),
		);

		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
			'health',
		]);
		expect(scheduledDrains).toHaveLength(1);
		clockMs += 1;

		const firstDrainCompletion = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toHaveLength(2);
		const secondDrainResult = await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		const firstDrainResult = await firstDrainCompletion;

		expect(firstDrainResult.completedIds).toEqual([]);
		expect(secondDrainResult.completedIds).toEqual(['review-content-ready:item-1:visible:202']);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
			'health',
			'pierreRenderJob',
			'slicePatch',
		]);
		expect(postedMessages[3]?.message).toMatchObject({
			kind: 'pierreRenderJob',
			job: {
				itemId: 'item-1',
				bridgeDemandRank: { lane: 'visible', priority: 1 },
				budgetClass: 'visible',
			},
		});
		expect(postedMessages[4]?.message).toMatchObject({
			kind: 'slicePatch',
			epoch: 6,
			sequence: 202,
			patches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'item-1',
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'ready' },
				},
			],
		});
	});

	test('skips ready visible Review demand when viewport adds cold content', async () => {
		let clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const fetchCallsByItemId = new Map<string, number>();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [
				makeWorkerReviewContentMetadata({ itemId: 'item-1' }),
				makeWorkerReviewContentMetadata({ itemId: 'item-2' }),
			],
			contentRequestDescriptors: [
				makeContentRequestDescriptor({
					itemId: 'item-1',
					role: 'base',
					text: 'ready base',
				}),
				makeContentRequestDescriptor({
					itemId: 'item-1',
					role: 'head',
					text: 'ready head',
				}),
				makeContentRequestDescriptor({
					itemId: 'item-2',
					role: 'base',
					text: 'cold base',
				}),
				makeContentRequestDescriptor({
					itemId: 'item-2',
					role: 'head',
					text: 'cold head',
				}),
			],
			createSequence: createBridgeWorkerSequenceCounter(301),
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				fetchCallsByItemId.set(
					descriptor.itemId,
					(fetchCallsByItemId.get(descriptor.itemId) ?? 0) + 1,
				);
				return makeImmediateTextResponse(descriptor.text);
			},
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			renderSemantics: [
				makeRenderSemantics({ itemId: 'item-1' }),
				makeRenderSemantics({ itemId: 'item-2' }),
			],
			rows: [
				{ id: 'item-1', parentId: null, index: 0 },
				{ id: 'item-2', parentId: null, index: 1 },
			],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-ready-visible',
				epoch: 5,
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		clockMs += 1;
		const readyFirstDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await readyFirstDrain;
		expect(fetchCallsByItemId.get('item-1')).toBe(2);

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-cold-visible',
				epoch: 6,
				visibleItemIds: ['item-1', 'item-2'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 1,
				phase: 'settled',
			}),
		);
		expect(scheduledDrains).toHaveLength(3);
		clockMs += 1;
		const coldFirstDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[2])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[3])();
		await coldFirstDrain;

		const pierreJobItemIds = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'pierreRenderJob' ? [postedMessage.message.job.itemId] : [],
		);
		expect(pierreJobItemIds).toEqual(['item-1', 'item-2']);
		expect(fetchCallsByItemId.get('item-1')).toBe(2);
		expect(fetchCallsByItemId.get('item-2')).toBe(2);
	});

	test('drops in-flight visible Review demand after source update and reruns current content', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const deferredResponsesByUrl = new Map<string, DeferredTextResponse>();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [
				makeContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'base',
					text: 'old base',
				}),
				makeContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'head',
					text: 'old head',
				}),
			],
			createSequence: createBridgeWorkerSequenceCounter(401),
			fetchContent: (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				if (url.includes('generation=4')) {
					const deferredResponse = createDeferredTextResponse();
					deferredResponsesByUrl.set(url, deferredResponse);
					return deferredResponse.promise;
				}
				return Promise.resolve(makeImmediateTextResponse(descriptor.text));
			},
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-before-update',
				epoch: 5,
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		const staleFirstDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(deferredResponsesByUrl.size).toBe(2);

		dispatch.message(
			encodeBridgeWorkerReviewSourceUpdateCommand({
				requestId: 'request-update-during-visible-fetch',
				epoch: 6,
				contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
				contentRequestDescriptors: [
					makeContentRequestDescriptor({
						generation: 5,
						itemId: 'item-1',
						role: 'base',
						text: 'fresh base',
					}),
					makeContentRequestDescriptor({
						generation: 5,
						itemId: 'item-1',
						role: 'head',
						text: 'fresh head',
					}),
				],
				renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			}),
		);
		expect(scheduledDrains).toHaveLength(1);

		for (const deferredResponse of deferredResponsesByUrl.values()) {
			deferredResponse.resolve('old body');
		}
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toHaveLength(2);
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await staleFirstDrain;
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toHaveLength(3);

		const freshFirstDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[2])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toHaveLength(4);
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[3])();
		await freshFirstDrain;

		const pierreJobMessages = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'pierreRenderJob' ? [postedMessage.message] : [],
		);
		expect(pierreJobMessages).toHaveLength(1);
		expect(JSON.stringify(pierreJobMessages[0])).toContain('fresh head');
		expect(JSON.stringify(pierreJobMessages[0])).not.toContain('old head');
	});

	test('drains selected File View content prep from retained source descriptors', async () => {
		let clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [],
			contentRequestDescriptors: [],
			createSequence: createBridgeWorkerSequenceCounter(61),
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected File View content URL ${url}.`);
				}
				return makeImmediateTextResponse(descriptor.text);
			},
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			renderSemantics: [],
			rows: [],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-view-source-update',
				epoch: 6,
				contentItems: [makeWorkerFileViewContentMetadata()],
				contentRequestDescriptors: [makeFileViewContentRequestDescriptor('file body\n')],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-file-view-select',
				epoch: 7,
				selectedItemId: 'file-1',
				selectedSource: 'user',
			}),
		);

		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'health',
			'slicePatch',
			'health',
		]);
		expect(scheduledDrains).toHaveLength(1);
		clockMs += 1;

		const firstDrainCompletion = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toHaveLength(2);
		const secondDrainResult = await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		const firstDrainResult = await firstDrainCompletion;

		expect(firstDrainResult.completedIds).toEqual([]);
		expect(secondDrainResult.completedIds).toEqual(['file-view-content-ready:file-1:7:63']);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'health',
			'slicePatch',
			'health',
			'pierreRenderJob',
			'slicePatch',
		]);
		expect(postedMessages[3]?.message).toMatchObject({
			kind: 'pierreRenderJob',
			job: {
				itemId: 'file-1',
				renderKind: 'fileText',
				payload: {
					kind: 'codeViewFileItem',
				},
			},
		});
		expect(postedMessages[4]?.message).toMatchObject({
			kind: 'slicePatch',
			epoch: 7,
			sequence: 63,
			patches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'file-1',
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'file-1',
					payload: { state: 'ready' },
				},
			],
		});
	});

	test('drains a second selected File View prep after ready descriptor refresh', async () => {
		let clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [],
			contentRequestDescriptors: [],
			createSequence: createBridgeWorkerSequenceCounter(81),
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected File View content URL ${url}.`);
				}
				return makeImmediateTextResponse(descriptor.text);
			},
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			renderSemantics: [],
			rows: [],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-view-source-before-ready',
				epoch: 6,
				contentItems: [makeWorkerFileViewContentMetadata()],
				contentRequestDescriptors: [
					makeFileViewContentRequestDescriptor({ generation: 6, text: 'first body\n' }),
				],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-file-view-select-before-ready',
				epoch: 7,
				selectedItemId: 'file-1',
				selectedSource: 'user',
			}),
		);
		clockMs += 1;
		const firstDrainCompletion = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await firstDrainCompletion;

		dispatch.message(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-view-source-descriptor-refresh',
				epoch: 8,
				contentItems: [makeWorkerFileViewContentMetadata()],
				contentRequestDescriptors: [
					makeFileViewContentRequestDescriptor({ generation: 8, text: 'refreshed body\n' }),
				],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);
		expect(scheduledDrains).toHaveLength(3);
		clockMs += 1;
		const refreshFirstDrainCompletion = assertBridgeCommWorkerPreparationDrain(
			scheduledDrains[2],
		)();
		await flushBridgeWorkerRuntimeContinuations();
		const refreshSecondDrainResult = await assertBridgeCommWorkerPreparationDrain(
			scheduledDrains[3],
		)();
		await refreshFirstDrainCompletion;

		expect(refreshSecondDrainResult.completedIds).toEqual(['file-view-content-ready:file-1:8:85']);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'health',
			'slicePatch',
			'health',
			'pierreRenderJob',
			'slicePatch',
			'health',
			'pierreRenderJob',
			'slicePatch',
		]);
		expect(postedMessages[6]?.message).toMatchObject({
			kind: 'pierreRenderJob',
			job: {
				itemId: 'file-1',
				renderKind: 'fileText',
				payload: {
					kind: 'codeViewFileItem',
					item: {
						file: {
							contents: 'refreshed body\n',
						},
					},
				},
			},
		});
		expect(postedMessages[7]?.message).toMatchObject({
			kind: 'slicePatch',
			epoch: 8,
			sequence: 85,
			patches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'file-1',
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'file-1',
					payload: { state: 'ready' },
				},
			],
		});
	});
});
