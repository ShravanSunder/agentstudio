import { describe, expect, test, vi } from 'vitest';

import {
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerMetadataInterestUpdateCommand,
	encodeBridgeWorkerReviewIntakeReadyCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import {
	assertBridgeCommWorkerPreparationDrain,
	createBridgeWorkerSequenceCounter,
	createBridgeCommWorkerReviewProductTestSource,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	makeContentRequestDescriptor,
	makeRenderSemantics,
	makeWorkerReviewContentMetadata,
	openReviewContentFromDescriptorMap,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';
import type {
	BridgeProductSubscriptionEvent,
	BridgeProductSubscriptionUpdateOptions,
} from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';

describe('Bridge comm worker runtime protocol', () => {
	test('opens Review metadata through worker-owned intake readiness', async () => {
		// Arrange
		const sentCommands: BridgeProductControlCommand[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			sendProductControl: async (command): Promise<void> => {
				sentCommands.push(command);
			},
		});

		// Act
		dispatch.message(
			encodeBridgeWorkerReviewIntakeReadyCommand({
				requestId: 'request-review-intake-ready',
				epoch: 1,
				reason: 'bridge-ready',
				streamId: 'review:pane-1',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(sentCommands).toEqual([
			{
				method: 'bridge.intakeReady',
				params: {
					protocolId: 'review',
					reason: 'bridge-ready',
					streamId: 'review:pane-1',
				},
			},
		]);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-review-intake-ready',
				status: 'ready',
			}),
		);
	});

	test('sends markFileViewed through worker-owned product control', async () => {
		const sentCommands: BridgeProductControlCommand[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const productControlCompletion = createDeferredVoid();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			sendProductControl: async (command): Promise<void> => {
				sentCommands.push(command);
				await productControlCompletion.promise;
			},
		});

		dispatch.message(
			encodeBridgeWorkerMarkFileViewedCommand({
				requestId: 'request-mark-viewed',
				epoch: 3,
				fileId: 'item-1',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(sentCommands).toEqual([
			{
				method: 'review.markFileViewed',
				params: { fileId: 'item-1' },
			},
		]);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-mark-viewed',
				status: 'ready',
			}),
		);
		productControlCompletion.resolve();
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-mark-viewed',
				status: 'ready',
			}),
		);
	});

	test('reports degraded health when markFileViewed product control fails', async () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			sendProductControl: async (): Promise<void> => {
				throw new Error('scheme down');
			},
		});

		dispatch.message(
			encodeBridgeWorkerMarkFileViewedCommand({
				requestId: 'request-mark-viewed',
				epoch: 3,
				fileId: 'item-1',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-mark-viewed',
				status: 'degraded',
				message: 'Bridge comm worker failed to forward review.markFileViewed.',
			}),
		);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-mark-viewed',
				status: 'ready',
			}),
		);
	});

	test('does not send rejected markFileViewed product control', async () => {
		const sentCommands: BridgeProductControlCommand[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			sendProductControl: async (command): Promise<void> => {
				sentCommands.push(command);
			},
		});

		dispatch.message(
			encodeBridgeWorkerMarkFileViewedCommand({
				requestId: 'request-current',
				epoch: 3,
				fileId: 'item-1',
			}),
		);
		dispatch.message(
			encodeBridgeWorkerMarkFileViewedCommand({
				requestId: 'request-stale',
				epoch: 2,
				fileId: 'item-1',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(sentCommands).toEqual([
			{
				method: 'review.markFileViewed',
				params: { fileId: 'item-1' },
			},
		]);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-stale',
				status: 'degraded',
				message: 'Bridge comm worker rejected stale epoch 2 after 3.',
			}),
		);
	});

	test('updates Review metadata interests through the worker-owned product subscription', async () => {
		const updates: BridgeProductSubscriptionUpdateOptions<'review.metadata'>[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const updateCompletion = createDeferredVoid();
		const reviewProductTransport = createReviewMetadataInterestProductTransport(
			async (options): Promise<void> => {
				updates.push(options);
				await updateCompletion.promise;
			},
		);

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			productTransport: reviewProductTransport.productTransport,
			sendProductControl: async (): Promise<void> => {
				throw new Error('metadata interests must not use generic product control');
			},
		});

		dispatch.message(
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				requestId: 'request-metadata-interest',
				epoch: 3,
				request: {
					protocol: 'review',
					itemIds: ['item-1'],
					lane: 'foreground',
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(updates).toEqual([
			{
				interests: [{ itemIds: ['item-1'], lane: 'foreground' }],
			},
		]);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-metadata-interest',
				status: 'ready',
			}),
		);
		updateCompletion.resolve();
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-metadata-interest',
				status: 'ready',
			}),
		);
		reviewProductTransport.close();
	});

	test('reports degraded health when the Review metadata subscription update fails', async () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const reviewProductTransport = createReviewMetadataInterestProductTransport(
			async (): Promise<void> => {
				throw new Error('subscription down');
			},
		);

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			productTransport: reviewProductTransport.productTransport,
		});

		dispatch.message(
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				requestId: 'request-metadata-interest',
				epoch: 3,
				request: {
					protocol: 'review',
					itemIds: ['item-1'],
					lane: 'foreground',
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-metadata-interest',
				status: 'degraded',
				message: 'Bridge comm worker failed to update Review metadata interests.',
			}),
		);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-metadata-interest',
				status: 'ready',
			}),
		);
		reviewProductTransport.close();
	});

	test('reports degraded health when the Review metadata subscription update never settles', async () => {
		vi.useFakeTimers();
		try {
			const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
			const reviewProductTransport = createReviewMetadataInterestProductTransport(
				async (): Promise<void> => new Promise((): void => {}),
			);

			registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
				bridgeDemandRank: { lane: 'selected', priority: 0 },
				budget: {
					className: 'interactive',
					maxBytes: 512 * 1024,
					maxWindowLines: 50,
				},
				productControlTimeoutMilliseconds: 25,
				productTransport: reviewProductTransport.productTransport,
			});

			dispatch.message(
				encodeBridgeWorkerMetadataInterestUpdateCommand({
					requestId: 'request-metadata-interest',
					epoch: 3,
					request: {
						protocol: 'review',
						itemIds: ['item-1'],
						lane: 'foreground',
					},
				}),
			);
			await flushBridgeWorkerRuntimeContinuations();

			expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
				expect.objectContaining({
					kind: 'health',
					requestId: 'request-metadata-interest',
					status: 'degraded',
				}),
			);

			await vi.advanceTimersByTimeAsync(25);
			await flushBridgeWorkerRuntimeContinuations();

			expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
				expect.objectContaining({
					kind: 'health',
					requestId: 'request-metadata-interest',
					status: 'degraded',
					message: 'Bridge comm worker failed to update Review metadata interests.',
				}),
			);
			expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
				expect.objectContaining({
					kind: 'health',
					requestId: 'request-metadata-interest',
					status: 'ready',
				}),
			);
			reviewProductTransport.close();
		} finally {
			vi.useRealTimers();
		}
	});

	test('sends activeViewerModeUpdate through worker-owned product control', async () => {
		const sentCommands: BridgeProductControlCommand[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const productControlCompletion = createDeferredVoid();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			sendProductControl: async (command): Promise<void> => {
				sentCommands.push(command);
				await productControlCompletion.promise;
			},
		});

		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				requestId: 'request-active-viewer-mode',
				epoch: 3,
				update: {
					sessionId: 'active-viewer-session',
					sequence: 4,
					mode: 'review',
					activeSource: {
						protocol: 'review',
						streamId: 'review:pane-1',
						generation: 5,
					},
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(sentCommands).toEqual([
			{
				method: 'bridge.activeViewerMode.update',
				params: {
					sessionId: 'active-viewer-session',
					sequence: 4,
					mode: 'review',
					activeSource: {
						protocol: 'review',
						streamId: 'review:pane-1',
						generation: 5,
					},
				},
			},
		]);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-active-viewer-mode',
				status: 'ready',
			}),
		);
		productControlCompletion.resolve();
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-active-viewer-mode',
				status: 'ready',
			}),
		);
	});

	test('reports degraded health when activeViewerModeUpdate product control fails', async () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			sendProductControl: async (): Promise<void> => {
				throw new Error('scheme down');
			},
		});

		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				requestId: 'request-active-viewer-mode',
				epoch: 3,
				update: {
					sessionId: 'active-viewer-session',
					sequence: 4,
					mode: 'file',
					activeSource: null,
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-active-viewer-mode',
				status: 'degraded',
				message: 'Bridge comm worker failed to forward bridge.activeViewerMode.update.',
				deliveryStatus: 'unknownAfterDispatch',
			}),
		);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-active-viewer-mode',
				status: 'ready',
			}),
		);
	});

	test('starts visible Review demand from viewport membership through the worker executor', async () => {
		let clockMs = 0;
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const reviewProductSource = createBridgeCommWorkerReviewProductTestSource();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			createSequence: createBridgeWorkerSequenceCounter(101),
			openReviewContent: openReviewContentFromDescriptorMap,
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			productTransport: reviewProductSource.productTransport,
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});
		reviewProductSource.publishSource(
			{
				contentItems: [makeWorkerReviewContentMetadata()],
				contentRequestDescriptors: [
					makeContentRequestDescriptor({ role: 'base', text: 'visible base' }),
					makeContentRequestDescriptor({ role: 'head', text: 'visible head' }),
				],
				renderSemantics: [makeRenderSemantics()],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			},
			4,
		);
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		scheduledDrains.length = 0;
		postedMessages.length = 0;

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-viewport',
				epoch: 5,
				surface: 'review',
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
		expect(secondDrainResult.completedIds).toEqual(['review-content-ready:item-1:visible:105']);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
			'reviewPierreRenderJob',
			'reviewRenderPatch',
		]);
		expect(postedMessages[2]?.message).toMatchObject({
			kind: 'reviewPierreRenderJob',
			job: {
				itemId: 'item-1',
				bridgeDemandRank: { lane: 'visible', priority: 1 },
				budgetClass: 'visible',
			},
		});
		expect(postedMessages[3]?.message).toMatchObject({
			kind: 'reviewRenderPatch',
			publicationSequence: 105,
			workerDerivationEpoch: 1,
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
		const reviewProductSource = createBridgeCommWorkerReviewProductTestSource();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			createSequence: createBridgeWorkerSequenceCounter(201),
			openReviewContent: openReviewContentFromDescriptorMap,
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			productTransport: reviewProductSource.productTransport,
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});
		await flushBridgeWorkerRuntimeContinuations();

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-visible-before-source',
				epoch: 5,
				surface: 'review',
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

		reviewProductSource.publishSource(
			{
				contentItems: [makeWorkerReviewContentMetadata()],
				contentRequestDescriptors: [
					makeContentRequestDescriptor({ role: 'base', text: 'source repair base' }),
					makeContentRequestDescriptor({ role: 'head', text: 'source repair head' }),
				],
				renderSemantics: [makeRenderSemantics()],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			},
			6,
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
			'reviewRenderPatch',
			'reviewDisplayPatch',
		]);
		expect(scheduledDrains).toHaveLength(1);
		clockMs += 1;

		const firstDrainCompletion = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toHaveLength(2);
		const secondDrainResult = await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		const firstDrainResult = await firstDrainCompletion;

		expect(firstDrainResult.completedIds).toEqual(['review-source-reset:1']);
		expect(secondDrainResult.completedIds).toEqual(['review-content-ready:item-1:visible:205']);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
			'reviewRenderPatch',
			'reviewDisplayPatch',
			'reviewPierreRenderJob',
			'reviewRenderPatch',
		]);
		expect(postedMessages[4]?.message).toMatchObject({
			kind: 'reviewPierreRenderJob',
			job: {
				itemId: 'item-1',
				bridgeDemandRank: { lane: 'visible', priority: 1 },
				budgetClass: 'visible',
			},
		});
		expect(postedMessages[5]?.message).toMatchObject({
			kind: 'reviewRenderPatch',
			publicationSequence: 205,
			workerDerivationEpoch: 1,
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
		const reviewProductSource = createBridgeCommWorkerReviewProductTestSource();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			createSequence: createBridgeWorkerSequenceCounter(301),
			openReviewContent: (descriptor, abortSignal) => {
				fetchCallsByItemId.set(
					descriptor.itemId,
					(fetchCallsByItemId.get(descriptor.itemId) ?? 0) + 1,
				);
				return openReviewContentFromDescriptorMap(descriptor, abortSignal);
			},
			pump: createWorkerContentPreparationPump({
				maxSliceMs: 8,
				now: () => clockMs,
			}),
			productTransport: reviewProductSource.productTransport,
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});
		reviewProductSource.publishSource(
			{
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
				renderSemantics: [
					makeRenderSemantics({ itemId: 'item-1' }),
					makeRenderSemantics({ itemId: 'item-2' }),
				],
				rows: [
					{ id: 'item-1', parentId: null, index: 0 },
					{ id: 'item-2', parentId: null, index: 1 },
				],
			},
			4,
		);
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		scheduledDrains.length = 0;
		postedMessages.length = 0;

		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-ready-visible',
				epoch: 5,
				surface: 'review',
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
				surface: 'review',
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
			postedMessage.message.kind === 'reviewPierreRenderJob'
				? [postedMessage.message.job.itemId]
				: [],
		);
		expect(pierreJobItemIds).toEqual(['item-1', 'item-2']);
		expect(fetchCallsByItemId.get('item-1')).toBe(2);
		expect(fetchCallsByItemId.get('item-2')).toBe(2);
	});
});

function createReviewMetadataInterestProductTransport(
	update: (options: BridgeProductSubscriptionUpdateOptions<'review.metadata'>) => Promise<void>,
): { readonly close: () => void; readonly productTransport: BridgeProductTransportSession } {
	const events = new BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'review.metadata'>
	>(1);
	let reviewWorkerDerivationEpoch = 0;
	const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
		cancel: async (): Promise<void> => {},
		events,
		subscriptionId: 'review-metadata-interest-test-subscription',
		subscriptionKind: 'review.metadata',
		update,
	};
	return {
		close: (): void => {
			events.close(true);
		},
		productTransport: {
			bumpWorkerDerivationEpoch: (surface): number => {
				if (surface === 'review') reviewWorkerDerivationEpoch += 1;
				return surface === 'review' ? reviewWorkerDerivationEpoch : 0;
			},
			call: async (...arguments_): Promise<never> => {
				const [method] = arguments_;
				if (method === 'file.source.current') {
					return { reason: 'review-only-test', status: 'unavailable' } as never;
				}
				return undefined as never;
			},
			openContent: (): never => {
				throw new Error('Review metadata interest test does not open content.');
			},
			subscribe: (...arguments_): never => {
				const [subscriptionKind] = arguments_;
				if (subscriptionKind !== 'review.metadata') {
					throw new Error(`Unexpected subscription ${subscriptionKind}.`);
				}
				return reviewSubscription as never;
			},
			workerDerivationEpoch: (surface): number =>
				surface === 'review' ? reviewWorkerDerivationEpoch : 0,
		},
	};
}

function createDeferredVoid(): { readonly promise: Promise<void>; readonly resolve: () => void } {
	let resolvePromise: (() => void) | null = null;
	const promise = new Promise<void>((resolve): void => {
		resolvePromise = resolve;
	});
	return {
		promise,
		resolve: (): void => {
			if (resolvePromise === null) {
				throw new Error('Deferred promise resolver was not initialized.');
			}
			resolvePromise();
		},
	};
}
