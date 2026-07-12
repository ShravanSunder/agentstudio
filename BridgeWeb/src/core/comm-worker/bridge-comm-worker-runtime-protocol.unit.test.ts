import { describe, expect, test, vi } from 'vitest';

import type { BridgeRPCCommand } from '../../bridge/bridge-rpc-client.js';
import {
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerMetadataInterestUpdateCommand,
	encodeBridgeWorkerReviewSourceUpdateCommand,
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
	makeImmediateTextResponse,
	makeRenderSemantics,
	makeWorkerReviewContentMetadata,
	type DeferredTextResponse,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';

describe('Bridge comm worker runtime protocol', () => {
	test('forwards markFileViewed commands to Swift through worker-owned scheme RPC', async () => {
		const sentCommands: BridgeRPCCommand[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const schemeRpcCompletion = createDeferredVoid();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [],
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			sendSchemeRpcCommand: async (command): Promise<void> => {
				sentCommands.push(command);
				await schemeRpcCompletion.promise;
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
		schemeRpcCompletion.resolve();
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-mark-viewed',
				status: 'ready',
			}),
		);
	});

	test('reports degraded health when markFileViewed scheme RPC forwarding fails', async () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [],
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			sendSchemeRpcCommand: async (): Promise<void> => {
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

	test('does not forward rejected markFileViewed commands through scheme RPC', async () => {
		const sentCommands: BridgeRPCCommand[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [],
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			sendSchemeRpcCommand: async (command): Promise<void> => {
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

	test('forwards metadataInterestUpdate commands to Swift through worker-owned scheme RPC', async () => {
		const sentCommands: BridgeRPCCommand[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const schemeRpcCompletion = createDeferredVoid();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [],
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			sendSchemeRpcCommand: async (command): Promise<void> => {
				sentCommands.push(command);
				await schemeRpcCompletion.promise;
			},
		});

		dispatch.message(
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				requestId: 'request-metadata-interest',
				epoch: 3,
				request: {
					protocol: 'review',
					streamId: 'stream-1',
					generation: 7,
					itemIds: ['item-1'],
					lane: 'foreground',
					loaded_by: 'foreground',
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(sentCommands).toEqual([
			{
				method: 'bridge.metadata_interest.update',
				params: {
					protocol: 'review',
					streamId: 'stream-1',
					generation: 7,
					itemIds: ['item-1'],
					lane: 'foreground',
					loaded_by: 'foreground',
				},
			},
		]);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-metadata-interest',
				status: 'ready',
			}),
		);
		schemeRpcCompletion.resolve();
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-metadata-interest',
				status: 'ready',
			}),
		);
	});

	test('reports degraded health when metadataInterestUpdate scheme RPC forwarding fails', async () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [],
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			sendSchemeRpcCommand: async (): Promise<void> => {
				throw new Error('scheme down');
			},
		});

		dispatch.message(
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				requestId: 'request-metadata-interest',
				epoch: 3,
				request: {
					protocol: 'review',
					streamId: 'stream-1',
					generation: 7,
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
				message: 'Bridge comm worker failed to forward bridge.metadata_interest.update.',
			}),
		);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-metadata-interest',
				status: 'ready',
			}),
		);
	});

	test('reports degraded health when metadataInterestUpdate scheme RPC forwarding never settles', async () => {
		vi.useFakeTimers();
		try {
			const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

			registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
				bridgeDemandRank: { lane: 'selected', priority: 0 },
				budget: {
					className: 'interactive',
					maxBytes: 512 * 1024,
					maxWindowLines: 50,
				},
				contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
				contentRequestDescriptors: [],
				renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
				schemeRpcTimeoutMilliseconds: 25,
				sendSchemeRpcCommand: async (): Promise<void> => new Promise((): void => {}),
			});

			dispatch.message(
				encodeBridgeWorkerMetadataInterestUpdateCommand({
					requestId: 'request-metadata-interest',
					epoch: 3,
					request: {
						protocol: 'review',
						streamId: 'stream-1',
						generation: 7,
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
					message: 'Bridge comm worker failed to forward bridge.metadata_interest.update.',
				}),
			);
			expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
				expect.objectContaining({
					kind: 'health',
					requestId: 'request-metadata-interest',
					status: 'ready',
				}),
			);
		} finally {
			vi.useRealTimers();
		}
	});

	test('forwards activeViewerModeUpdate commands to Swift through worker-owned scheme RPC', async () => {
		const sentCommands: BridgeRPCCommand[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const schemeRpcCompletion = createDeferredVoid();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [],
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			sendSchemeRpcCommand: async (command): Promise<void> => {
				sentCommands.push(command);
				await schemeRpcCompletion.promise;
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
		schemeRpcCompletion.resolve();
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-active-viewer-mode',
				status: 'ready',
			}),
		);
	});

	test('reports degraded health when activeViewerModeUpdate scheme RPC forwarding fails', async () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [],
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			sendSchemeRpcCommand: async (): Promise<void> => {
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

		expect(firstDrainResult.completedIds).toEqual(['review-source-reset:6']);
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
		expect(scheduledDrains).toHaveLength(2);

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
});

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
