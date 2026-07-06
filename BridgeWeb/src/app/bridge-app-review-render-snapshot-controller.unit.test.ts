import { describe, expect, test } from 'vitest';

import { encodeBridgeWorkerSelectCommand } from '../core/comm-worker/bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerPreparationDrain } from '../core/comm-worker/bridge-comm-worker-runtime-protocol.js';
import { createBridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type {
	BridgeWorkerContentAvailabilityPatchPayload,
	BridgeWorkerPierreRenderJobEvent,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerPierreCourier } from '../core/comm-worker/bridge-worker-pierre-courier.js';
import {
	buildBridgeWorkerPierreRenderJob,
	type BridgeWorkerPierreRenderJob,
} from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import {
	applyBridgeWorkerMessagesToMainRenderSnapshotStore,
	bridgeCommWorkerContentRequestDescriptorsFromReviewPackage,
	bridgeCommWorkerContentItemsFromReviewPackage,
	bridgeCommWorkerRenderSemanticsFromReviewPackage,
	createBridgeReviewWorkerPierreCourier,
	createBridgeReviewRuntimeProtocolDispatcher,
} from './bridge-app-review-render-snapshot-controller.js';

describe('Bridge app review render snapshot controller', () => {
	test('dispatches selected review content through the runtime port before Pierre-ready patches', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const postedMessages: BridgeWorkerServerToMainMessage[] = [];
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const runtimeDispatcher = createBridgeReviewRuntimeProtocolDispatcher({
			contentItems: bridgeCommWorkerContentItemsFromReviewPackage(reviewPackage),
			contentRequestDescriptors:
				bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(reviewPackage),
			createSequence: createBridgeWorkerSequenceCounter(41),
			fetchContent: async (url: string): Promise<Response> => {
				const responseBody = url.includes('base') ? 'base body' : 'head body';
				return new Response(responseBody);
			},
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				postedMessages.push(...messages);
			},
			renderSemantics: bridgeCommWorkerRenderSemanticsFromReviewPackage(reviewPackage),
			rows: [{ id: 'item-source', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		runtimeDispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 7,
				selectedItemId: 'item-source',
				selectedSource: 'user',
			}),
		);

		expect(scheduledDrains).toHaveLength(1);
		expect(postedMessages.map((message) => message.kind)).toEqual(['slicePatch', 'health']);
		expect(selectedAvailabilityStateFromMessage(postedMessages[0])).toBe('loading');

		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();

		expect(postedMessages.map((message) => message.kind)).toEqual([
			'slicePatch',
			'health',
			'pierreRenderJob',
			'slicePatch',
		]);
		expect(postedMessages[2]).toMatchObject({
			kind: 'pierreRenderJob',
			job: { itemId: 'item-source', renderKind: 'reviewDiff' },
		});
		expect(selectedAvailabilityStateFromMessage(postedMessages[3])).toBe('ready');
	});

	test('retired runtime dispatchers drop stale selected preparation publications', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const postedMessages: BridgeWorkerServerToMainMessage[] = [];
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const runtimeDispatcher = createBridgeReviewRuntimeProtocolDispatcher({
			contentItems: bridgeCommWorkerContentItemsFromReviewPackage(reviewPackage),
			contentRequestDescriptors:
				bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(reviewPackage),
			createSequence: createBridgeWorkerSequenceCounter(61),
			fetchContent: async (url: string): Promise<Response> => {
				const responseBody = url.includes('base') ? 'base body' : 'head body';
				return new Response(responseBody);
			},
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				postedMessages.push(...messages);
			},
			renderSemantics: bridgeCommWorkerRenderSemanticsFromReviewPackage(reviewPackage),
			rows: [{ id: 'item-source', parentId: null, index: 0 }],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		runtimeDispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-before-retire',
				epoch: 11,
				selectedItemId: 'item-source',
				selectedSource: 'user',
			}),
		);
		runtimeDispatcher.dispose();

		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();

		expect(postedMessages.map((message) => message.kind)).toEqual(['slicePatch', 'health']);
		expect(selectedAvailabilityStateFromMessage(postedMessages[0])).toBe('loading');
	});

	test('routes worker Pierre render jobs through the courier instead of dropping them', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		const job = buildBridgeWorkerPierreRenderJob({
			itemId: 'item-1',
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:sha256:base|pierre-content:sha256:head',
			contentHash: 'sha256:base+head',
			language: 'typescript',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			window: {
				startLine: 1,
				endLine: 10,
				totalLineCount: 100,
			},
			payload: {
				kind: 'diffTextWindow',
				baseTextBytes: new ArrayBuffer(40),
				headTextBytes: new ArrayBuffer(56),
			},
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
		});
		const event = {
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'pierreRenderJob',
			job,
		} satisfies BridgeWorkerPierreRenderJobEvent;
		const enqueuedJobs: BridgeWorkerPierreRenderJob[] = [];
		const pierreCourier: BridgeWorkerPierreCourier = {
			enqueue: (receivedJob: BridgeWorkerPierreRenderJob) => {
				enqueuedJobs.push(receivedJob);
				return {
					status: 'enqueued',
					itemId: receivedJob.itemId,
					payloadByteLength: receivedJob.payloadByteLength,
					budgetClass: receivedJob.budgetClass,
				};
			},
		};

		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [event],
			pierreCourier,
			renderSnapshotStore,
		});

		expect(enqueuedJobs).toEqual([job]);
	});

	test('review worker courier returns typed receipts for worker Pierre jobs', () => {
		const job = buildBridgeWorkerPierreRenderJob({
			itemId: 'item-worker-courier',
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:sha256:base|pierre-content:sha256:worker-courier',
			contentHash: 'sha256:worker-courier',
			language: 'typescript',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			window: {
				startLine: 1,
				endLine: 8,
				totalLineCount: 80,
			},
			payload: {
				kind: 'diffTextWindow',
				baseTextBytes: new ArrayBuffer(16),
				headTextBytes: new ArrayBuffer(48),
			},
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
		});

		expect(createBridgeReviewWorkerPierreCourier().enqueue(job)).toEqual({
			status: 'enqueued',
			itemId: 'item-worker-courier',
			payloadByteLength: 64,
			budgetClass: 'interactive',
		});
	});

	test('routes only slice patches into the render snapshot store', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		const enqueuedJobs: BridgeWorkerPierreRenderJob[] = [];
		const pierreCourier: BridgeWorkerPierreCourier = {
			enqueue: (receivedJob: BridgeWorkerPierreRenderJob) => {
				enqueuedJobs.push(receivedJob);
				return {
					status: 'enqueued',
					itemId: receivedJob.itemId,
					payloadByteLength: receivedJob.payloadByteLength,
					budgetClass: receivedJob.budgetClass,
				};
			},
		};
		const messages = [
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				status: 'ready',
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'subscription',
				requestId: 'request-subscription',
				subscription: 'reviewContent',
				status: 'subscribed',
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'slicePatch',
				epoch: 4,
				sequence: 7,
				patches: [
					{
						slice: 'selection',
						operation: 'upsert',
						payload: {
							selectedItemId: 'item-2',
							source: 'user',
						},
					},
				],
			},
		] satisfies readonly BridgeWorkerServerToMainMessage[];

		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages,
			pierreCourier,
			renderSnapshotStore,
		});

		expect(renderSnapshotStore.getSnapshot().selectionSlice).toEqual({
			selectedItemId: 'item-2',
			source: 'user',
		});
		expect(enqueuedJobs).toEqual([]);
	});

	test('maps review package items into worker content metadata without package snapshots', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const contentItems = bridgeCommWorkerContentItemsFromReviewPackage(reviewPackage);

		expect(contentItems).toHaveLength(1);
		expect(contentItems[0]).toMatchObject({
			itemId: 'item-source',
			path: 'Sources/App/View.swift',
			language: 'swift',
			cacheKey: 'item-source:base|item-source:head',
			sizeBytes: 1024,
			availableContentRoles: ['base', 'head'],
		});
		expect(JSON.stringify(contentItems)).not.toMatch(
			/itemsById|orderedItemIds|summary|groups|"contentRoles"|resourceUrl|endpointId/i,
		);
		expect(bridgeCommWorkerContentItemsFromReviewPackage(null)).toEqual([]);
	});

	test('maps review package handles into explicit worker content request descriptors', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const requestDescriptors =
			bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(reviewPackage);

		expect(requestDescriptors).toHaveLength(2);
		expect(requestDescriptors[0]).toMatchObject({
			itemId: 'item-source',
			role: 'base',
			reviewGeneration: 1,
			resourceUrl: 'agentstudio://resource/review/content/handle-item-source-base?generation=1',
			contentHash: 'sha256:item-source:base',
			language: 'swift',
			isBinary: false,
		});
		expect(JSON.stringify(requestDescriptors)).not.toMatch(
			/itemsById|orderedItemIds|summary|groups|"contentRoles"|endpointId|"cacheKey"|mimeType/i,
		);
		expect(bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(null)).toEqual([]);
	});

	test('maps review package items into worker render semantics without content handles', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const renderSemantics = bridgeCommWorkerRenderSemanticsFromReviewPackage(reviewPackage);

		expect(renderSemantics).toHaveLength(1);
		expect(renderSemantics[0]).toMatchObject({
			itemId: 'item-source',
			itemKind: 'diff',
			changeKind: 'modified',
			displayPath: 'Sources/App/View.swift',
			basePath: 'Sources/App/View.swift',
			headPath: 'Sources/App/View.swift',
			language: 'swift',
		});
		expect(JSON.stringify(renderSemantics)).not.toMatch(
			/itemsById|orderedItemIds|summary|groups|"contentRoles"|resourceUrl|handleId|contentHash|endpointId/i,
		);
		expect(bridgeCommWorkerRenderSemanticsFromReviewPackage(null)).toEqual([]);
	});
});

function createBridgeWorkerSequenceCounter(firstSequence: number): () => number {
	let nextSequence = firstSequence;
	return (): number => {
		const sequence = nextSequence;
		nextSequence += 1;
		return sequence;
	};
}

function assertBridgeCommWorkerPreparationDrain(
	drain: BridgeCommWorkerPreparationDrain | undefined,
): BridgeCommWorkerPreparationDrain {
	if (drain === undefined) {
		throw new Error('Expected scheduled bridge comm worker preparation drain.');
	}
	return drain;
}

function selectedAvailabilityStateFromMessage(
	message: BridgeWorkerServerToMainMessage | undefined,
): BridgeWorkerContentAvailabilityPatchPayload['state'] | null {
	if (message?.kind !== 'slicePatch') {
		return null;
	}
	for (const patch of message.patches) {
		if (
			patch.slice === 'contentAvailability' &&
			patch.operation === 'upsert' &&
			patch.itemId === 'item-source'
		) {
			return patch.payload.state;
		}
	}
	return null;
}
