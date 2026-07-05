import { describe, expect, test } from 'vitest';

import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import { enqueueSelectedBridgeWorkerReviewContentReadyPreparation } from './bridge-comm-worker-review-preparation.js';
import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';
import type {
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerReviewContentRequestDescriptor,
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

interface PostedBridgeWorkerPreparationMessage {
	readonly message: BridgeWorkerServerToMainMessage;
	readonly transferList: readonly Transferable[] | undefined;
}

describe('Bridge comm worker review preparation', () => {
	test('enqueues selected review content-ready dispatch as selected-ranked preparation work', async () => {
		let clockMs = 0;
		const executionOrder: string[] = [];
		const postedMessages: PostedBridgeWorkerPreparationMessage[] = [];
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 1,
			now: () => clockMs,
		});
		pump.enqueue({
			id: 'background-visible-review-item',
			rank: 'background',
			runSlice: () => {
				executionOrder.push('background');
				clockMs += 2;
				return { complete: false };
			},
		});
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerReviewContentMetadata()],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
		});
		store.actions.applySelectedFact({ epoch: 7, itemId: 'item-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		const preparation = enqueueSelectedBridgeWorkerReviewContentReadyPreparation({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentRequestDescriptors: [
				makeContentRequestDescriptor({ role: 'base', text: 'base content' }),
				makeContentRequestDescriptor({ role: 'head', text: 'head content' }),
			],
			epoch: 7,
			fetchContent: async (url: string): Promise<Response> => {
				executionOrder.push('selected-fetch');
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return new Response(descriptor.text);
			},
			itemId: 'item-1',
			port: makePostedMessagePort(postedMessages),
			pump,
			renderSemantics: [makeRenderSemantics()],
			sequence: 12,
			store,
		});

		expect(postedMessages).toEqual([]);
		const runResult = pump.runUntilBudget();
		await preparation.completion;

		expect(runResult.completedIds).toEqual([preparation.workId]);
		expect(runResult.yielded).toBe(true);
		expect(executionOrder).toEqual(['selected-fetch', 'selected-fetch', 'background']);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'pierreRenderJob',
			'slicePatch',
		]);
	});

	test('drops stale selected review preparation before publishing content messages', async () => {
		const postedMessages: PostedBridgeWorkerPreparationMessage[] = [];
		const fetchCalls: string[] = [];
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 5,
			now: () => 0,
		});
		const store = createBridgeCommWorkerStore({
			contentItems: [
				makeWorkerReviewContentMetadata('item-1'),
				makeWorkerReviewContentMetadata('item-2'),
			],
			rows: [
				{ id: 'item-1', parentId: null, index: 0 },
				{ id: 'item-2', parentId: null, index: 1 },
			],
		});
		store.actions.applySelectedFact({ epoch: 7, itemId: 'item-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		const preparation = enqueueSelectedBridgeWorkerReviewContentReadyPreparation({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentRequestDescriptors: [
				makeContentRequestDescriptor({ role: 'base', text: 'base content' }),
				makeContentRequestDescriptor({ role: 'head', text: 'head content' }),
			],
			epoch: 7,
			fetchContent: async (url: string): Promise<Response> => {
				fetchCalls.push(url);
				store.actions.applySelectedFact({ epoch: 8, itemId: 'item-2' });
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return new Response(descriptor.text);
			},
			itemId: 'item-1',
			port: makePostedMessagePort(postedMessages),
			pump,
			renderSemantics: [makeRenderSemantics()],
			sequence: 12,
			store,
		});

		const runResult = pump.runUntilBudget();
		await preparation.completion;

		expect(runResult.completedIds).toEqual([preparation.workId]);
		expect(fetchCalls).toEqual([
			'agentstudio://resource/review/content/handle-item-1-base?generation=4',
			'agentstudio://resource/review/content/handle-item-1-head?generation=4',
		]);
		expect(postedMessages).toEqual([]);
	});

	test('skips enqueue when selected content is no longer current or demand eligible', async () => {
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 5,
			now: () => 0,
		});
		const store = createBridgeCommWorkerStore({
			contentItems: [],
			rows: [{ id: 'item-without-metadata', parentId: null, index: 0 }],
		});
		store.actions.applySelectedFact({ epoch: 7, itemId: 'item-without-metadata' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		const preparation = enqueueSelectedBridgeWorkerReviewContentReadyPreparation({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentRequestDescriptors: [],
			epoch: 7,
			itemId: 'item-without-metadata',
			port: makePostedMessagePort([]),
			pump,
			renderSemantics: [],
			sequence: 12,
			store,
		});

		await preparation.completion;

		expect(preparation.enqueued).toBe(false);
		expect(pump.getPendingWorkIds()).toEqual([]);
	});
});

const descriptorByUrl = new Map<string, { readonly text: string }>();

function makePostedMessagePort(
	postedMessages: PostedBridgeWorkerPreparationMessage[],
): BridgeCommWorkerPort {
	return {
		postMessage: (
			message: BridgeWorkerServerToMainMessage,
			transferList?: Transferable[],
		): void => {
			postedMessages.push({ message, transferList });
		},
		addEventListener: (): void => {},
	};
}

function makeWorkerReviewContentMetadata(itemId = 'item-1'): BridgeWorkerReviewContentMetadata {
	return {
		itemId,
		path: `Sources/App/${itemId}.swift`,
		language: 'swift',
		cacheKey: `${itemId}:base|${itemId}:head`,
		sizeBytes: 1024,
		availableContentRoles: ['base', 'head'],
		contentLineCountsByRole: { base: 100, head: 80 },
	};
}

function makeRenderSemantics(): BridgeWorkerReviewRenderSemantics {
	return {
		itemId: 'item-1',
		itemKind: 'diff',
		changeKind: 'modified',
		displayPath: 'Sources/App/item-1.swift',
		basePath: 'Sources/App/item-1.swift',
		headPath: 'Sources/App/item-1.swift',
		language: 'swift',
		contentLineCountsByRole: { base: 100, head: 80 },
	};
}

function makeContentRequestDescriptor(props: {
	readonly role: BridgeWorkerReviewContentRequestDescriptor['role'];
	readonly text: string;
}): BridgeWorkerReviewContentRequestDescriptor {
	const descriptor: BridgeWorkerReviewContentRequestDescriptor = {
		itemId: 'item-1',
		role: props.role,
		handleId: `handle-item-1-${props.role}`,
		reviewGeneration: 4,
		resourceUrl: `agentstudio://resource/review/content/handle-item-1-${props.role}?generation=4`,
		contentHash: `sha256:item-1:${props.role}`,
		contentHashAlgorithm: 'fixture-preview',
		language: 'swift',
		sizeBytes: 1024,
		isBinary: false,
	};
	descriptorByUrl.set(descriptor.resourceUrl, { text: props.text });
	return descriptor;
}
