import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerReviewInvalidateCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-source-diff.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import {
	assertBridgeCommWorkerPreparationDrain,
	createBridgeWorkerSequenceCounter,
	createBridgeCommWorkerReviewProductTestSource,
	createDeferredReviewContentStream,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	makeContentRequestDescriptor,
	makeRenderSemantics,
	makeWorkerReviewContentMetadata,
	openReviewContentFromDescriptorMap,
	reviewContentFixtureByDescriptorId,
	type BridgeCommWorkerReviewProductTestSource,
	type DeferredReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';

describe('Bridge comm worker runtime visible demand protocol', () => {
	test('refreshes a ready visible Review item after source update changes content descriptors', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		const reviewProductSource = await registerBridgeRuntimeWithInitialReviewSource(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [
				makeInexactContentRequestDescriptor({
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
			createSequence: createBridgeWorkerSequenceCounter(701),
			openReviewContent: openReviewContentFromDescriptorMap,
			pump: createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => clockMs }),
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-ready-before-source-update',
				epoch: 5,
				surface: 'review',
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		const firstDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await firstDrain;
		expect(
			postedMessages.filter(
				(postedMessage) => postedMessage.message.kind === 'reviewPierreRenderJob',
			),
		).toHaveLength(1);

		reviewProductSource.publishSource(
			{
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
			},
			6,
		);
		await flushBridgeWorkerRuntimeContinuations();
		const refreshDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[2])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[3])();
		await refreshDrain;

		const pierreJobMessages = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'reviewPierreRenderJob' ? [postedMessage.message] : [],
		);
		expect(pierreJobMessages).toHaveLength(2);
		expect(JSON.stringify(pierreJobMessages[1])).toContain('fresh head');
	});

	test('refreshes visible Review demand after source update changes only descriptor byte bounds', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const baseDescriptor = makeInexactContentRequestDescriptor({
			generation: 4,
			itemId: 'item-1',
			role: 'base',
			text: 'same base',
		});
		const headDescriptor = makeInexactContentRequestDescriptor({
			generation: 4,
			itemId: 'item-1',
			role: 'head',
			text: 'same head',
		});
		const updatedBaseDescriptor = {
			...makeContentRequestDescriptor({
				generation: 5,
				itemId: 'item-1',
				role: 'base',
				text: 'same base',
			}),
			contentDigest: baseDescriptor.contentDigest,
		};
		const updatedHeadDescriptor = {
			...makeContentRequestDescriptor({
				generation: 5,
				itemId: 'item-1',
				role: 'head',
				text: 'same head',
			}),
			contentDigest: headDescriptor.contentDigest,
		};

		const reviewProductSource = await registerBridgeRuntimeWithInitialReviewSource(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [baseDescriptor, headDescriptor],
			createSequence: createBridgeWorkerSequenceCounter(801),
			openReviewContent: openReviewContentFromDescriptorMap,
			pump: createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => clockMs }),
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-before-byte-bound-source-update',
				epoch: 5,
				surface: 'review',
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		const firstDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await firstDrain;
		expect(
			postedMessages.filter(
				(postedMessage) => postedMessage.message.kind === 'reviewPierreRenderJob',
			),
		).toHaveLength(1);

		reviewProductSource.publishSource(
			{
				contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
				contentRequestDescriptors: [
					{
						...updatedBaseDescriptor,
						declaredByteLength: 9,
						maximumBytes: 9,
						wholeByteLength: 9,
						window: { ...updatedBaseDescriptor.window, maximumBytes: 9 },
					},
					{
						...updatedHeadDescriptor,
						declaredByteLength: 9,
						maximumBytes: 9,
						wholeByteLength: 9,
						window: { ...updatedHeadDescriptor.window, maximumBytes: 9 },
					},
				],
				renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			},
			6,
		);
		await flushBridgeWorkerRuntimeContinuations();
		const refreshDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[2])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[3])();
		await refreshDrain;

		const pierreJobMessages = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'reviewPierreRenderJob' ? [postedMessage.message] : [],
		);
		expect(pierreJobMessages).toHaveLength(2);
	});

	test('keeps source-update rerun sticky when viewport arrives before stale in-flight completion', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const deferredStreamsByDescriptorId = new Map<string, DeferredReviewContentStream>();

		const reviewProductSource = await registerBridgeRuntimeWithInitialReviewSource(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [
				makeInexactContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'base',
					text: 'ready base',
				}),
				makeContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'head',
					text: 'ready head',
				}),
			],
			createSequence: createBridgeWorkerSequenceCounter(801),
			openReviewContent: (descriptor, abortSignal) => {
				if (descriptor.descriptorId.endsWith('-5')) {
					const deferredStream = createDeferredReviewContentStream(descriptor);
					deferredStreamsByDescriptorId.set(descriptor.descriptorId, deferredStream);
					return deferredStream.stream;
				}
				return openReviewContentFromDescriptorMap(descriptor, abortSignal);
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
				requestId: 'request-visible-before-sticky-rerun',
				epoch: 5,
				surface: 'review',
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		const readyDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await readyDrain;

		reviewProductSource.publishSource(
			{
				contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
				contentRequestDescriptors: [
					makeContentRequestDescriptor({
						generation: 5,
						itemId: 'item-1',
						role: 'base',
						text: 'stale base',
					}),
					makeContentRequestDescriptor({
						generation: 5,
						itemId: 'item-1',
						role: 'head',
						text: 'stale head',
					}),
				],
				renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			},
			6,
		);
		await flushBridgeWorkerRuntimeContinuations();
		const staleSourceDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[2])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(deferredStreamsByDescriptorId.size).toBe(2);

		reviewProductSource.publishSource(
			{
				contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
				contentRequestDescriptors: [
					makeContentRequestDescriptor({
						generation: 6,
						itemId: 'item-1',
						role: 'base',
						text: 'fresh base',
					}),
					makeContentRequestDescriptor({
						generation: 6,
						itemId: 'item-1',
						role: 'head',
						text: 'fresh head',
					}),
				],
				renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			},
			7,
		);
		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-viewport-after-source-b',
				epoch: 8,
				surface: 'review',
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		for (const deferredStream of deferredStreamsByDescriptorId.values()) {
			deferredStream.resolve('stale body');
		}
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[3])();
		await staleSourceDrain;
		await drainBridgeWorkerVisibleDemandRuntimeUntil({
			hasExpectedEvent: () =>
				postedMessages.some(
					(postedMessage) =>
						postedMessage.message.kind === 'reviewPierreRenderJob' &&
						JSON.stringify(postedMessage.message).includes('fresh head'),
				),
			scheduledDrains,
			startIndex: 4,
		});

		const pierreJobMessages = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'reviewPierreRenderJob' ? [postedMessage.message] : [],
		);
		expect(pierreJobMessages).toHaveLength(2);
		expect(JSON.stringify(pierreJobMessages[1])).toContain('fresh head');
		expect(JSON.stringify(pierreJobMessages[1])).not.toContain('stale head');
	});

	test('clears ready visible Review paint when source update removes executable content', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		const reviewProductSource = await registerBridgeRuntimeWithInitialReviewSource(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [
				makeInexactContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'base',
					text: 'ready base',
				}),
				makeContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'head',
					text: 'ready head',
				}),
			],
			createSequence: createBridgeWorkerSequenceCounter(901),
			openReviewContent: openReviewContentFromDescriptorMap,
			pump: createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => clockMs }),
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-before-nonexecutable-source',
				epoch: 5,
				surface: 'review',
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		const readyDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await readyDrain;

		reviewProductSource.publishSource(
			{
				contentItems: [
					{
						...makeWorkerReviewContentMetadata({ itemId: 'item-1' }),
						availableContentRoles: [],
					},
				],
				contentRequestDescriptors: [],
				renderSemantics: [],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			},
			6,
		);
		await flushBridgeWorkerRuntimeContinuations();

		const finalPatch = postedMessages
			.flatMap((postedMessage) =>
				postedMessage.message.kind === 'slicePatch' ? [postedMessage.message] : [],
			)
			.at(-1);
		expect(finalPatch).toMatchObject({
			kind: 'slicePatch',
			patches: [
				{ slice: 'rowPaint', operation: 'delete', itemId: 'item-1' },
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'stale' },
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'unavailable' },
				},
			],
		});
		expect(scheduledDrains).toHaveLength(2);
	});

	test('clears ready visible Review paint when source update keeps only one required diff side', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		const reviewProductSource = await registerBridgeRuntimeWithInitialReviewSource(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [
				makeContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'base',
					text: 'ready base',
				}),
				makeContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'head',
					text: 'ready head',
				}),
			],
			createSequence: createBridgeWorkerSequenceCounter(951),
			openReviewContent: openReviewContentFromDescriptorMap,
			pump: createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => clockMs }),
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-before-one-sided-source',
				epoch: 5,
				surface: 'review',
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		const readyDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await readyDrain;

		reviewProductSource.publishSource(
			{
				contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
				contentRequestDescriptors: [
					makeContentRequestDescriptor({
						generation: 5,
						itemId: 'item-1',
						role: 'head',
						text: 'head only',
					}),
				],
				renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			},
			6,
		);
		await flushBridgeWorkerRuntimeContinuations();

		const finalPatch = postedMessages
			.flatMap((postedMessage) =>
				postedMessage.message.kind === 'slicePatch' ? [postedMessage.message] : [],
			)
			.at(-1);
		expect(finalPatch).toMatchObject({
			kind: 'slicePatch',
			patches: [
				{ slice: 'rowPaint', operation: 'delete', itemId: 'item-1' },
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'stale' },
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'unavailable' },
				},
			],
		});
		expect(scheduledDrains).toHaveLength(2);
	});

	test('keeps unrelated visible Review fetches current when source update changes one item', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const deferredStreamsByDescriptorId = new Map<string, DeferredReviewContentStream>();
		const fetchCallsByItemId = new Map<string, number>();

		const reviewProductSource = await registerBridgeRuntimeWithInitialReviewSource(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [
				makeWorkerReviewContentMetadata({ itemId: 'item-1' }),
				makeWorkerReviewContentMetadata({ itemId: 'item-2' }),
			],
			contentRequestDescriptors: [
				makeContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'base',
					text: 'a old base',
				}),
				makeContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'head',
					text: 'a old head',
				}),
				makeContentRequestDescriptor({
					generation: 4,
					itemId: 'item-2',
					role: 'base',
					text: 'b base',
				}),
				makeContentRequestDescriptor({
					generation: 4,
					itemId: 'item-2',
					role: 'head',
					text: 'b head',
				}),
			],
			createSequence: createBridgeWorkerSequenceCounter(501),
			openReviewContent: (descriptor, abortSignal) => {
				fetchCallsByItemId.set(
					descriptor.itemId,
					(fetchCallsByItemId.get(descriptor.itemId) ?? 0) + 1,
				);
				if (descriptor.descriptorId.endsWith('-4')) {
					const deferredStream = createDeferredReviewContentStream(descriptor);
					deferredStreamsByDescriptorId.set(descriptor.descriptorId, deferredStream);
					return deferredStream.stream;
				}
				return openReviewContentFromDescriptorMap(descriptor, abortSignal);
			},
			pump: createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => clockMs }),
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
				requestId: 'request-two-visible-before-update',
				epoch: 5,
				surface: 'review',
				visibleItemIds: ['item-1', 'item-2'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 1,
				phase: 'settled',
			}),
		);
		const staleFirstDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(deferredStreamsByDescriptorId.size).toBe(4);

		reviewProductSource.publishSource(
			{
				contentItems: [
					makeWorkerReviewContentMetadata({ itemId: 'item-1' }),
					makeWorkerReviewContentMetadata({ itemId: 'item-2' }),
				],
				contentRequestDescriptors: [
					makeContentRequestDescriptor({
						generation: 5,
						itemId: 'item-1',
						role: 'base',
						text: 'a fresh base',
					}),
					makeContentRequestDescriptor({
						generation: 5,
						itemId: 'item-1',
						role: 'head',
						text: 'a fresh head',
					}),
					makeContentRequestDescriptor({
						generation: 4,
						itemId: 'item-2',
						role: 'base',
						text: 'b base',
					}),
					makeContentRequestDescriptor({
						generation: 4,
						itemId: 'item-2',
						role: 'head',
						text: 'b head',
					}),
				],
				renderSemantics: [
					makeRenderSemantics({ itemId: 'item-1' }),
					makeRenderSemantics({ itemId: 'item-2' }),
				],
				rows: [
					{ id: 'item-1', parentId: null, index: 0 },
					{ id: 'item-2', parentId: null, index: 1 },
				],
			},
			6,
		);
		for (const [descriptorId, deferredStream] of deferredStreamsByDescriptorId) {
			const fixture = reviewContentFixtureByDescriptorId.get(descriptorId);
			if (fixture === undefined) {
				throw new Error(`Unexpected Review content descriptor ${descriptorId}.`);
			}
			deferredStream.resolve(fixture.text);
		}
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await staleFirstDrain;
		await flushBridgeWorkerRuntimeContinuations();
		await drainBridgeWorkerVisibleDemandRuntimeUntil({
			hasExpectedEvent: () =>
				postedMessages.some(
					(postedMessage) =>
						postedMessage.message.kind === 'reviewPierreRenderJob' &&
						postedMessage.message.job.itemId === 'item-1' &&
						JSON.stringify(postedMessage.message).includes('a fresh head'),
				),
			scheduledDrains,
			startIndex: 2,
		});

		const pierreJobItemIds = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'reviewPierreRenderJob'
				? [postedMessage.message.job.itemId]
				: [],
		);
		expect(pierreJobItemIds).toEqual(['item-2', 'item-1']);
		expect(fetchCallsByItemId.get('item-1')).toBe(4);
		expect(fetchCallsByItemId.get('item-2')).toBe(2);
	});

	test('reruns an in-flight visible Review fetch after path-hint invalidation', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const deferredStreamsByDescriptorId = new Map<string, DeferredReviewContentStream>();

		await registerBridgeRuntimeWithInitialReviewSource(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [
				makeInexactContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'base',
					text: 'old base',
				}),
				makeInexactContentRequestDescriptor({
					generation: 4,
					itemId: 'item-1',
					role: 'head',
					text: 'old head',
				}),
			],
			createSequence: createBridgeWorkerSequenceCounter(601),
			openReviewContent: (descriptor, abortSignal) => {
				if (descriptor.descriptorId.endsWith('-4')) {
					const deferredStream = createDeferredReviewContentStream(descriptor);
					deferredStreamsByDescriptorId.set(descriptor.descriptorId, deferredStream);
					return deferredStream.stream;
				}
				return openReviewContentFromDescriptorMap(descriptor, abortSignal);
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
				requestId: 'request-visible-before-path-invalidate',
				epoch: 5,
				surface: 'review',
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		const staleDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(deferredStreamsByDescriptorId.size).toBe(2);

		dispatch.message(
			encodeBridgeWorkerReviewInvalidateCommand({
				requestId: 'request-path-hint-invalidate',
				epoch: 6,
				itemIds: [],
				pathHints: ['Sources/App/item-1.swift'],
				reason: 'watchEvent',
				scope: 'items',
			}),
		);
		for (const [descriptorId, deferredStream] of deferredStreamsByDescriptorId) {
			deferredStream.resolve(descriptorId.includes('-base-') ? 'old base' : 'old head');
		}
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await staleDrain;
		await flushBridgeWorkerRuntimeContinuations();
		expect(
			postedMessages.filter(
				(postedMessage) => postedMessage.message.kind === 'reviewPierreRenderJob',
			),
		).toEqual([]);
		deferredStreamsByDescriptorId.clear();
		const rerunDrain = assertBridgeCommWorkerPreparationDrain(scheduledDrains[2])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(deferredStreamsByDescriptorId.size).toBe(2);
		for (const [descriptorId, deferredStream] of deferredStreamsByDescriptorId) {
			deferredStream.resolve(descriptorId.includes('-base-') ? 'fresh base' : 'fresh body');
		}
		await flushBridgeWorkerRuntimeContinuations();
		await drainBridgeWorkerVisibleDemandRuntimeUntil({
			hasExpectedEvent: () =>
				postedMessages.some(
					(postedMessage) =>
						postedMessage.message.kind === 'reviewPierreRenderJob' &&
						JSON.stringify(postedMessage.message).includes('fresh body'),
				),
			scheduledDrains,
			startIndex: 3,
		});
		await rerunDrain;

		const pierreJobMessages = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'reviewPierreRenderJob' ? [postedMessage.message] : [],
		);
		expect(pierreJobMessages).toHaveLength(1);
			expect(JSON.stringify(pierreJobMessages[0])).toContain('fresh body');
		});

	test('drains every visible Review item when one settled window exceeds start concurrency', async () => {
		// Arrange
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const itemIds = Array.from({ length: 9 }, (_, index): string => `visible-item-${index + 1}`);
		await registerBridgeRuntimeWithInitialReviewSource(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: itemIds.map((itemId) => makeWorkerReviewContentMetadata({ itemId })),
			contentRequestDescriptors: itemIds.flatMap((itemId) => [
				makeContentRequestDescriptor({
					generation: 4,
					itemId,
					role: 'base',
					text: `${itemId} base`,
				}),
				makeContentRequestDescriptor({
					generation: 4,
					itemId,
					role: 'head',
					text: `${itemId} head`,
				}),
			]),
			createSequence: createBridgeWorkerSequenceCounter(901),
			openReviewContent: openReviewContentFromDescriptorMap,
			pump: createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => clockMs }),
			renderSemantics: itemIds.map((itemId) => makeRenderSemantics({ itemId })),
			rows: itemIds.map((itemId, index) => ({ id: itemId, parentId: null, index })),
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		// Act
		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-nine-visible-items',
				epoch: 5,
				surface: 'review',
				visibleItemIds: itemIds,
				firstVisibleIndex: 0,
				lastVisibleIndex: itemIds.length - 1,
				phase: 'settled',
			}),
		);
		await drainBridgeWorkerVisibleDemandRuntimeUntil({
			hasExpectedEvent: () =>
				postedMessages.filter(
					(postedMessage) => postedMessage.message.kind === 'reviewPierreRenderJob',
				).length === itemIds.length,
			scheduledDrains,
			startIndex: 0,
		});

		// Assert
		const publishedItemIds = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'reviewPierreRenderJob'
				? [postedMessage.message.job.itemId]
				: [],
		);
		expect(new Set(publishedItemIds)).toEqual(new Set(itemIds));
		expect(publishedItemIds).toHaveLength(itemIds.length);
	});
});

type InitialReviewSource = BridgeCommWorkerReviewRuntimeSource;

async function registerBridgeRuntimeWithInitialReviewSource(
	port: Parameters<typeof registerBridgeCommWorkerRuntimePortProtocol>[0],
	props: Parameters<typeof registerBridgeCommWorkerRuntimePortProtocol>[1] & InitialReviewSource,
): Promise<BridgeCommWorkerReviewProductTestSource> {
	const {
		contentItems,
		contentRequestDescriptors,
		renderSemantics,
		rows,
		schedulePreparationDrain,
		...runtimeProps
	} = props;
	if (schedulePreparationDrain === undefined) {
		throw new Error('Expected a visible-demand test preparation scheduler.');
	}
	const initializationDrains: BridgeCommWorkerPreparationDrain[] = [];
	let isInitializingSource = true;
	const reviewProductSource = createBridgeCommWorkerReviewProductTestSource();
	registerBridgeCommWorkerRuntimePortProtocol(port, {
		...runtimeProps,
		productTransport: reviewProductSource.productTransport,
		schedulePreparationDrain: (drain): void => {
			if (isInitializingSource) {
				initializationDrains.push(drain);
				return;
			}
			schedulePreparationDrain(drain);
		},
	});
	reviewProductSource.publishSource(
		{
			contentItems,
			contentRequestDescriptors,
			renderSemantics,
			rows,
		},
		4,
	);
	await flushBridgeWorkerRuntimeContinuations();
	for (let drainRound = 0; drainRound < 16; drainRound += 1) {
		const drainsForRound = initializationDrains.splice(0);
		if (drainsForRound.length === 0) break;
		// oxlint-disable-next-line no-await-in-loop -- Each bounded round exposes source-reset continuation drains.
		await Promise.all(drainsForRound.map((drain) => drain()));
		// oxlint-disable-next-line no-await-in-loop -- Continuations publish their next drain at a microtask boundary.
		await flushBridgeWorkerRuntimeContinuations();
	}
	isInitializingSource = false;
	return reviewProductSource;
}

async function drainBridgeWorkerVisibleDemandRuntimeUntil(props: {
	readonly hasExpectedEvent: () => boolean;
	readonly scheduledDrains: readonly BridgeCommWorkerPreparationDrain[];
	readonly startIndex: number;
}): Promise<void> {
	return drainBridgeWorkerVisibleDemandRuntimeUntilAttempt({ ...props, attempt: 0 });
}

async function drainBridgeWorkerVisibleDemandRuntimeUntilAttempt(props: {
	readonly attempt: number;
	readonly hasExpectedEvent: () => boolean;
	readonly scheduledDrains: readonly BridgeCommWorkerPreparationDrain[];
	readonly startIndex: number;
}): Promise<void> {
	if (props.hasExpectedEvent() || props.attempt >= 8) {
		return;
	}
	await flushBridgeWorkerRuntimeContinuations();
	if (props.startIndex >= props.scheduledDrains.length) {
		await waitBridgeWorkerVisibleDemandRuntimeTaskBoundary();
		return drainBridgeWorkerVisibleDemandRuntimeUntilAttempt({
			...props,
			attempt: props.attempt + 1,
		});
	}
	void assertBridgeCommWorkerPreparationDrain(props.scheduledDrains[props.startIndex])();
	return drainBridgeWorkerVisibleDemandRuntimeUntilAttempt({
		...props,
		attempt: props.attempt + 1,
		startIndex: props.startIndex + 1,
	});
}

async function waitBridgeWorkerVisibleDemandRuntimeTaskBoundary(): Promise<void> {
	await new Promise<void>((resolve) => {
		setTimeout(resolve, 0);
	});
}

function makeInexactContentRequestDescriptor(
	props: Parameters<typeof makeContentRequestDescriptor>[0],
): ReturnType<typeof makeContentRequestDescriptor> {
	const descriptor = makeContentRequestDescriptor(props);
	return {
		...descriptor,
		declaredByteLength: null,
		maximumBytes: 512 * 1024,
		wholeByteLength: null,
		window: { ...descriptor.window, maximumBytes: 512 * 1024 },
	};
}
