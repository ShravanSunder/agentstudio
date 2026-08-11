import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerRenderDispositionCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-source-diff.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import {
	activateBridgeCommWorkerReviewViewerMode,
	assertBridgeCommWorkerPreparationDrain,
	createBridgeWorkerSequenceCounter,
	createBridgeCommWorkerReviewProductTestSource,
	createDeferredReviewContentStream,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	makeContentRequestDescriptor,
	makeImmediateReviewContentStream,
	makeRenderSemantics,
	makeWorkerReviewContentMetadata,
	type BridgeCommWorkerReviewProductTestSource,
	type DeferredReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import {
	createTrackedBridgeWorkerReviewContentOpen,
	drainBridgeWorkerVisibleDemandRuntimeUntil,
	drainBridgeWorkerVisibleDemandRuntimeUntilQuiescent,
} from './bridge-comm-worker-runtime-protocol.visible-demand.test-support.js';
import type { BridgeProductContentStream } from './bridge-product-transport-contract.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';
import type { BridgeWorkerReviewContentRequestDescriptor } from './bridge-worker-contracts.js';
import { bridgeWorkerRenderDispositionReceiptSchema } from './bridge-worker-render-fulfillment.js';

describe('Bridge comm worker runtime Review demand sharing', () => {
	test('reuses one completed body across authorization reissue without native or render retransmission', async () => {
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const originalDescriptor = makeContentRequestDescriptor({
			generation: 4,
			itemId: 'item-1',
			role: 'head',
			text: 'resident authorization-neutral body\n',
		});
		const reissuedDescriptor: BridgeWorkerReviewContentRequestDescriptor = {
			...originalDescriptor,
			descriptorId: 'descriptor-item-1-head-reissued',
			endpointId: 'endpoint-item-1-reissued',
			handleId: 'handle-item-1-head-reissued',
		};
		const renderSemantics = {
			...makeRenderSemantics({ itemId: 'item-1' }),
			basePath: null,
			changeKind: 'added',
		} as const;
		const trackedContentOpen = createTrackedBridgeWorkerReviewContentOpen((descriptor) =>
			makeImmediateReviewContentStream(descriptor, 'resident authorization-neutral body\n'),
		);
		const pump = createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => 0 });
		const reviewProductSource = await registerBridgeRuntimeWithInitialReviewSource(dispatch, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [originalDescriptor],
			createSequence: createBridgeWorkerSequenceCounter(901),
			openReviewContent: trackedContentOpen.openContent,
			pump,
			renderSemantics: [renderSemantics],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});
		await drainBridgeWorkerVisibleDemandRuntimeUntilQuiescent({
			pendingContentCompletions: trackedContentOpen.pendingCompletions,
			pendingPreparationWorkIds: pump.getPendingWorkIds,
			scheduledDrains,
		});
		expect(trackedContentOpen.openedDescriptorIds).toEqual([originalDescriptor.descriptorId]);
		expect(
			postedMessages.filter(
				(postedMessage) => postedMessage.message.kind === 'reviewPierreRenderJob',
			),
		).toHaveLength(1);
		const firstRenderPublication = postedMessages.find(
			(postedMessage) => postedMessage.message.kind === 'reviewPierreRenderJob',
		)?.message;
		if (firstRenderPublication?.kind !== 'reviewPierreRenderJob') {
			throw new Error('Expected the first Review render publication.');
		}
		dispatch.message(
			encodeBridgeWorkerRenderDispositionCommand({
				epoch: 5,
				receipt: bridgeWorkerRenderDispositionReceiptSchema.parse({
					...firstRenderPublication.renderReceiptIdentity,
					disposition: 'painted',
					kind: 'render.disposition',
					receivedAtMilliseconds: 0,
				}),
				requestId: 'request-acknowledge-resident-body-render',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		const reissuedPublicationApplied = reviewProductSource.publishSourceAndWaitForApplication(
			{
				contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
				contentRequestDescriptors: [reissuedDescriptor],
				renderSemantics: [renderSemantics],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			},
			5,
		);
		await reissuedPublicationApplied;
		await drainReviewSharingPreparationUntilIdle({ pump, scheduledDrains });

		expect(trackedContentOpen.openedDescriptorIds).toEqual([originalDescriptor.descriptorId]);
		expect(
			postedMessages.filter(
				(postedMessage) => postedMessage.message.kind === 'reviewPierreRenderJob',
			),
		).toHaveLength(1);
	});

	test('promotes in-flight visible Review demand to selected without duplicate fetch', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const deferredStreamsByDescriptorId = new Map<string, DeferredReviewContentStream>();
		const openCallsByDescriptorId = new Map<string, number>();
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

		await registerBridgeRuntimeWithInitialReviewSource(dispatch, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [baseDescriptor, headDescriptor],
			createSequence: createBridgeWorkerSequenceCounter(1001),
			openReviewContent: (descriptor) => {
				openCallsByDescriptorId.set(
					descriptor.descriptorId,
					(openCallsByDescriptorId.get(descriptor.descriptorId) ?? 0) + 1,
				);
				const deferredStream = createDeferredReviewContentStream(descriptor);
				deferredStreamsByDescriptorId.set(descriptor.descriptorId, deferredStream);
				return deferredStream.stream;
			},
			pump: createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => clockMs }),
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});
		const initialBackgroundDrain = assertBridgeCommWorkerPreparationDrain(
			scheduledDrains.shift(),
		)();
		await flushBridgeWorkerRuntimeContinuations();

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-before-selected-promote',
				epoch: 5,
				surface: 'review',
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toEqual([]);
		expect(deferredStreamsByDescriptorId.size).toBe(2);
		expect(openCallsByDescriptorId.get(baseDescriptor.descriptorId)).toBe(1);
		expect(openCallsByDescriptorId.get(headDescriptor.descriptorId)).toBe(1);

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-visible-in-flight',
				epoch: 6,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		await flushBridgeWorkerRuntimeContinuations();
		expect(openCallsByDescriptorId.get(baseDescriptor.descriptorId)).toBe(1);
		expect(openCallsByDescriptorId.get(headDescriptor.descriptorId)).toBe(1);
		deferredStreamsByDescriptorId
			.get(baseDescriptor.descriptorId)
			?.resolve('let previousValue = 1;\n');
		deferredStreamsByDescriptorId.get(headDescriptor.descriptorId)?.resolve('let nextValue = 2;\n');
		await drainBridgeWorkerVisibleDemandRuntimeUntil({
			hasExpectedEvent: () =>
				postedMessages.some(
					(postedMessage) => postedMessage.message.kind === 'reviewPierreRenderJob',
				),
			scheduledDrains,
			startIndex: 0,
		});
		await initialBackgroundDrain;

		const pierreJobMessages = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'reviewPierreRenderJob' ? [postedMessage.message] : [],
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

	test('propagates typed byte-limit failures when selected shares visible Review streams', async () => {
		const clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const deferredFailuresByDescriptorId = new Map<string, DeferredReviewContentFailureStream>();
		const baseDescriptor = {
			...makeContentRequestDescriptor({
				generation: 4,
				itemId: 'item-1',
				role: 'base',
				text: 'oversized base',
			}),
			declaredByteLength: 4,
			maximumBytes: 4,
			wholeByteLength: 4,
			window: { kind: 'byteRange', maximumBytes: 4, startByte: 0 },
		} satisfies BridgeWorkerReviewContentRequestDescriptor;
		const headDescriptor = {
			...makeContentRequestDescriptor({
				generation: 4,
				itemId: 'item-1',
				role: 'head',
				text: 'oversized head',
			}),
			declaredByteLength: 4,
			maximumBytes: 4,
			wholeByteLength: 4,
			window: { kind: 'byteRange', maximumBytes: 4, startByte: 0 },
		} satisfies BridgeWorkerReviewContentRequestDescriptor;

		await registerBridgeRuntimeWithInitialReviewSource(dispatch, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [baseDescriptor, headDescriptor],
			createSequence: createBridgeWorkerSequenceCounter(1101),
			openReviewContent: (descriptor) => {
				const deferredFailure = createDeferredReviewContentFailureStream(descriptor);
				deferredFailuresByDescriptorId.set(descriptor.descriptorId, deferredFailure);
				return deferredFailure.stream;
			},
			pump: createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => clockMs }),
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});
		const initialBackgroundDrain = assertBridgeCommWorkerPreparationDrain(
			scheduledDrains.shift(),
		)();
		await flushBridgeWorkerRuntimeContinuations();

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-before-selected-stream-guard',
				epoch: 5,
				surface: 'review',
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toEqual([]);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-stream-guard',
				epoch: 6,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		await flushBridgeWorkerRuntimeContinuations();
		deferredFailuresByDescriptorId.get(baseDescriptor.descriptorId)?.resolve();
		deferredFailuresByDescriptorId.get(headDescriptor.descriptorId)?.resolve();
		await drainBridgeWorkerVisibleDemandRuntimeUntil({
			hasExpectedEvent: () =>
				postedMessages.some(
					(postedMessage) =>
						postedMessage.message.kind === 'reviewRenderPatch' &&
						postedMessage.message.patches.some(
							(patch) =>
								patch.slice === 'contentAvailability' &&
								patch.operation === 'upsert' &&
								patch.itemId === 'item-1' &&
								patch.payload.state === 'failed',
						),
				),
			scheduledDrains,
			startIndex: 0,
		});
		await initialBackgroundDrain;

		expect(
			postedMessages.some(
				(postedMessage) =>
					postedMessage.message.kind === 'reviewRenderPatch' &&
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
		const deferredStreamsByOpenCall: DeferredReviewContentStream[] = [];
		const openCallsByDescriptorId = new Map<string, number>();
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
			...makeContentRequestDescriptor({
				generation: 5,
				itemId: 'item-1',
				role: 'head',
				text: 'first content',
			}),
			contentDigest: firstHeadDescriptor.contentDigest,
			declaredByteLength: null,
			maximumBytes: 64,
			wholeByteLength: null,
			window: { ...firstHeadDescriptor.window, maximumBytes: 64 },
		};

		const reviewProductSource = await registerBridgeRuntimeWithInitialReviewSource(dispatch, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [baseDescriptor, firstHeadDescriptor],
			createSequence: createBridgeWorkerSequenceCounter(1201),
			openReviewContent: (descriptor) => {
				openCallsByDescriptorId.set(
					descriptor.descriptorId,
					(openCallsByDescriptorId.get(descriptor.descriptorId) ?? 0) + 1,
				);
				const deferredStream = createDeferredReviewContentStream(descriptor);
				deferredStreamsByOpenCall.push(deferredStream);
				return deferredStream.stream;
			},
			pump: createWorkerContentPreparationPump({ maxSliceMs: 8, now: () => clockMs }),
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});
		const initialBackgroundDrain = assertBridgeCommWorkerPreparationDrain(
			scheduledDrains.shift(),
		)();
		await flushBridgeWorkerRuntimeContinuations();

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-before-descriptor-identity-change',
				epoch: 5,
				surface: 'review',
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toEqual([]);
		expect(openCallsByDescriptorId.get(baseDescriptor.descriptorId)).toBe(1);
		expect(openCallsByDescriptorId.get(firstHeadDescriptor.descriptorId)).toBe(1);

		reviewProductSource.publishSource(
			{
				contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
				contentRequestDescriptors: [baseDescriptor, updatedHeadDescriptor],
				renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			},
			6,
		);
		await flushBridgeWorkerRuntimeContinuations();
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-after-descriptor-byte-bounds-change',
				epoch: 7,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		await drainBridgeWorkerVisibleDemandRuntimeUntil({
			hasExpectedEvent: () => openCallsByDescriptorId.get(updatedHeadDescriptor.descriptorId) === 1,
			scheduledDrains,
			startIndex: 0,
		});
		expect(openCallsByDescriptorId.get(baseDescriptor.descriptorId)).toBe(2);
		expect(openCallsByDescriptorId.get(firstHeadDescriptor.descriptorId)).toBe(1);
		expect(openCallsByDescriptorId.get(updatedHeadDescriptor.descriptorId)).toBe(1);

		deferredStreamsByOpenCall[0]?.resolve('base content');
		deferredStreamsByOpenCall[1]?.resolve('first content');
		deferredStreamsByOpenCall[2]?.resolve('base content');
		deferredStreamsByOpenCall[3]?.resolve('let updatedHeadValue = 2;\n');
		const publicationDrainStartIndex = scheduledDrains.length;
		await drainBridgeWorkerVisibleDemandRuntimeUntil({
			hasExpectedEvent: () =>
				postedMessages.some(
					(postedMessage) => postedMessage.message.kind === 'reviewPierreRenderJob',
				),
			scheduledDrains,
			startIndex: publicationDrainStartIndex,
		});
		await initialBackgroundDrain;

		const pierreJobMessages = postedMessages.flatMap((postedMessage) =>
			postedMessage.message.kind === 'reviewPierreRenderJob' ? [postedMessage.message] : [],
		);
		expect(pierreJobMessages).toHaveLength(1);
		expect(pierreJobMessages[0]).toMatchObject({
			kind: 'reviewPierreRenderJob',
			job: { bridgeDemandRank: { lane: 'selected', priority: 0 }, itemId: 'item-1' },
			workerDerivationEpoch: 1,
		});
		expect(JSON.stringify(pierreJobMessages[0])).toContain('let updatedHeadValue = 2;');
		expect(JSON.stringify(pierreJobMessages[0])).not.toContain('first content');
	});
});

type InitialReviewSource = BridgeCommWorkerReviewRuntimeSource;

async function registerBridgeRuntimeWithInitialReviewSource(
	dispatch: {
		readonly message: (data: unknown) => void;
		readonly port: Parameters<typeof registerBridgeCommWorkerRuntimePortProtocol>[0];
	},
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
		throw new Error('Expected a Review-sharing test preparation scheduler.');
	}
	const initializationDrains: BridgeCommWorkerPreparationDrain[] = [];
	let isInitializingSource = true;
	const reviewProductSource = createBridgeCommWorkerReviewProductTestSource();
	registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
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
	activateBridgeCommWorkerReviewViewerMode(dispatch, 'initial-review-sharing-source');
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
	isInitializingSource = false;
	await assertBridgeCommWorkerPreparationDrain(initializationDrains.shift())();
	expect(initializationDrains).toEqual([]);
	return reviewProductSource;
}

async function drainReviewSharingPreparationUntilIdle(props: {
	readonly pump: ReturnType<typeof createWorkerContentPreparationPump>;
	readonly scheduledDrains: BridgeCommWorkerPreparationDrain[];
}): Promise<void> {
	const drainCompletions: Array<ReturnType<BridgeCommWorkerPreparationDrain>> = [];
	for (let drainRound = 0; drainRound < 16; drainRound += 1) {
		const drainsForRound = props.scheduledDrains.splice(0);
		drainCompletions.push(...drainsForRound.map((drain) => drain()));
		// oxlint-disable-next-line no-await-in-loop -- Each bounded round exposes the resident preparation continuation drain.
		await flushBridgeWorkerRuntimeContinuations();
		if (props.scheduledDrains.length === 0 && props.pump.getPendingWorkIds().length === 0) {
			break;
		}
	}
	expect(props.scheduledDrains).toEqual([]);
	expect(props.pump.getPendingWorkIds()).toEqual([]);
	await Promise.all(drainCompletions);
	await flushBridgeWorkerRuntimeContinuations();
}

interface DeferredReviewContentFailureStream {
	readonly resolve: () => void;
	readonly stream: BridgeProductContentStream<'review.content'>;
}

function createDeferredReviewContentFailureStream(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
): DeferredReviewContentFailureStream {
	let resolveFailure: (() => void) | null = null;
	const terminal: BridgeProductContentStream<'review.content'>['terminal'] = new Promise(
		(resolve) => {
			resolveFailure = (): void => {
				resolve({
					code: 'payload_too_large',
					contentKind: 'review.content',
					descriptorId: descriptor.descriptorId,
					kind: 'error',
					retryable: false,
					safeMessage: 'Review content exceeds the admitted byte range.',
				});
			};
		},
	);
	return {
		resolve: (): void => {
			if (resolveFailure === null) {
				throw new Error('Deferred Review content failure resolver was not initialized.');
			}
			resolveFailure();
		},
		stream: {
			contentKind: 'review.content',
			contentRequestId: `content-request-${descriptor.descriptorId}`,
			frames: emptyReviewContentFrames(),
			terminal,
		},
	};
}

async function* emptyReviewContentFrames(): AsyncIterable<never> {}
