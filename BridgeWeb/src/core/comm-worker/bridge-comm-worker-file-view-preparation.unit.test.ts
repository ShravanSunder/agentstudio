import { describe, expect, test } from 'vitest';

import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import { enqueueSelectedBridgeWorkerFileViewContentReadyPreparation } from './bridge-comm-worker-file-view-preparation.js';
import {
	createBridgeCommWorkerStore,
	type BridgeCommWorkerStore,
} from './bridge-comm-worker-store.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';
import type {
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerFileViewContentRequestDescriptor,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

interface PostedBridgeWorkerPreparationMessage {
	readonly message: BridgeWorkerServerToMainMessage;
	readonly transferList: readonly Transferable[] | undefined;
}

describe('Bridge comm worker File View preparation', () => {
	test('enqueues selected File View content-ready dispatch as selected-ranked preparation work', async () => {
		let clockMs = 0;
		const executionOrder: string[] = [];
		const postedMessages: PostedBridgeWorkerPreparationMessage[] = [];
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 1,
			now: () => clockMs,
		});
		pump.enqueue({
			id: 'background-visible-file-view-item',
			rank: 'background',
			runSlice: () => {
				executionOrder.push('background');
				clockMs += 2;
				return { complete: false };
			},
		});
		const store = createSelectedFileViewPreparationStore();
		store.actions.applySelectedFact({ epoch: 7, itemId: 'file-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		const preparation = enqueueSelectedBridgeWorkerFileViewContentReadyPreparation({
			...makePreparationProps({
				contentRequestDescriptors: [makeContentRequestDescriptor('file body\n')],
				fetchContent: async (url: string): Promise<Response> => {
					executionOrder.push('selected-fetch');
					const descriptor = descriptorByUrl.get(url);
					if (descriptor === undefined) {
						throw new Error(`Unexpected File View content URL ${url}.`);
					}
					return new Response(descriptor.text);
				},
				postedMessages,
				pump,
				store,
			}),
		});

		expect(postedMessages).toEqual([]);
		const firstRun = pump.runUntilBudget();
		await flushBridgeWorkerPreparationContinuations();
		const secondRun = pump.runUntilBudget();
		await preparation.completion;

		expect(firstRun.completedIds).toEqual([]);
		expect(firstRun.yielded).toBe(true);
		expect(secondRun.completedIds).toEqual([preparation.workId]);
		expect(executionOrder).toEqual(['selected-fetch', 'background', 'background']);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'pierreRenderJob',
			'slicePatch',
		]);
	});

	test('drops stale deferred selected File View preparation before publishing content messages', async () => {
		const postedMessages: PostedBridgeWorkerPreparationMessage[] = [];
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 5,
			now: () => 0,
		});
		const fetchResponse = createDeferredResponse('file body\n');
		let drainRequestCount = 0;
		const store = createBridgeCommWorkerStore({
			contentItems: [
				makeWorkerFileViewContentMetadata('file-1'),
				makeWorkerFileViewContentMetadata('file-2'),
			],
			rows: [
				{ id: 'file-1', parentId: null, index: 0 },
				{ id: 'file-2', parentId: null, index: 1 },
			],
		});
		store.actions.applySelectedFact({ epoch: 7, itemId: 'file-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		const preparation = enqueueSelectedBridgeWorkerFileViewContentReadyPreparation({
			...makePreparationProps({
				contentRequestDescriptors: [makeContentRequestDescriptor('file body\n')],
				fetchContent: async (): Promise<Response> => fetchResponse.promise,
				postedMessages,
				pump,
				requestPreparationDrain: () => {
					drainRequestCount += 1;
				},
				store,
			}),
		});

		const firstRun = pump.runUntilBudget();
		store.actions.applySelectedFact({ epoch: 8, itemId: 'file-2' });
		fetchResponse.resolve();
		await flushBridgeWorkerPreparationContinuations();

		expect(firstRun.completedIds).toEqual([]);
		expect(drainRequestCount).toBe(1);
		expect(pump.getPendingWorkIds()).toEqual([preparation.workId]);

		const secondRun = pump.runUntilBudget();
		await preparation.completion;

		expect(secondRun.completedIds).toEqual([preparation.workId]);
		expect(postedMessages).toEqual([]);
	});

	test('passes File View descriptors and fetch props through to publish a prepared job and ready patch', async () => {
		const postedMessages: PostedBridgeWorkerPreparationMessage[] = [];
		const fetchCalls: string[] = [];
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 5,
			now: () => 0,
		});
		const store = createSelectedFileViewPreparationStore();
		store.actions.applySelectedFact({ epoch: 7, itemId: 'file-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		const preparation = enqueueSelectedBridgeWorkerFileViewContentReadyPreparation({
			...makePreparationProps({
				bridgeDemandRank: { lane: 'selected', priority: 3 },
				budget: {
					className: 'interactive',
					maxBytes: 512 * 1024,
					maxWindowLines: 1,
				},
				contentRequestDescriptors: [makeContentRequestDescriptor('file body\nsecond line\n')],
				fetchContent: async (url: string): Promise<Response> => {
					fetchCalls.push(url);
					const descriptor = descriptorByUrl.get(url);
					if (descriptor === undefined) {
						throw new Error(`Unexpected File View content URL ${url}.`);
					}
					return new Response(descriptor.text);
				},
				postedMessages,
				pump,
				store,
			}),
		});

		pump.runUntilBudget();
		await flushBridgeWorkerPreparationContinuations();
		pump.runUntilBudget();
		await preparation.completion;

		expect(fetchCalls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?cursor=cursor-file-1&generation=7',
		]);
		expect(postedMessages[0]?.message).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'pierreRenderJob',
			job: {
				itemId: 'file-1',
				renderKind: 'fileText',
				contentCacheKey: 'file-view:metadata-cache:file-1',
				bridgeDemandRank: { lane: 'selected', priority: 3 },
				window: { startLine: 1, endLine: 1, totalLineCount: 1 },
				payload: {
					kind: 'codeViewFileItem',
					item: {
						id: 'file:file-1',
						file: {
							name: 'Sources/App/FileView.swift',
							contents: 'file body\n',
							cacheKey: 'file-view:metadata-cache:file-1',
							lang: 'swift',
						},
						bridgeMetadata: {
							itemId: 'file-1',
							displayPath: 'Sources/App/FileView.swift',
							contentState: 'hydrated',
							contentRoles: ['file'],
							cacheKey: 'file-view:metadata-cache:file-1',
							lineCount: 1,
						},
					},
				},
			},
		});
		expect(postedMessages[1]).toEqual({
			message: {
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'slicePatch',
				epoch: 7,
				sequence: 12,
				transferDescriptors: [],
				patches: [
					{
						slice: 'rowPaint',
						operation: 'upsert',
						itemId: 'file-1',
						payload: { contentCacheKey: 'file-view:metadata-cache:file-1' },
					},
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'file-1',
						payload: { state: 'ready' },
					},
				],
			},
			transferList: [],
		});
	});

	test('publishes failed availability when selected File View fetch fails', async () => {
		const postedMessages: PostedBridgeWorkerPreparationMessage[] = [];
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 5,
			now: () => 0,
		});
		const store = createSelectedFileViewPreparationStore();
		store.actions.applySelectedFact({ epoch: 7, itemId: 'file-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		const preparation = enqueueSelectedBridgeWorkerFileViewContentReadyPreparation({
			...makePreparationProps({
				contentRequestDescriptors: [makeContentRequestDescriptor('file body\n')],
				fetchContent: async (): Promise<Response> => {
					throw new Error('network unavailable');
				},
				postedMessages,
				pump,
				store,
			}),
		});

		pump.runUntilBudget();
		await flushBridgeWorkerPreparationContinuations();
		const secondRun = pump.runUntilBudget();
		await preparation.completion;

		expect(secondRun.completedIds).toEqual([preparation.workId]);
		expect(postedMessages).toEqual([
			{
				message: {
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					kind: 'slicePatch',
					epoch: 7,
					sequence: 12,
					transferDescriptors: [],
					patches: [
						{
							slice: 'contentAvailability',
							operation: 'upsert',
							itemId: 'file-1',
							payload: { state: 'failed' },
						},
					],
				},
				transferList: [],
			},
		]);
		expect(store.getState().availabilityByItemId.get('file-1')).toBe('failed');
	});

	test('clears stale ready paint when selected File View refresh fetch fails', async () => {
		const postedMessages: PostedBridgeWorkerPreparationMessage[] = [];
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 5,
			now: () => 0,
		});
		const store = createSelectedFileViewPreparationStore();
		store.actions.applySelectedFact({ epoch: 7, itemId: 'file-1' });
		store.actions.applyContentReady({
			itemId: 'file-1',
			contentCacheKey: 'file-view:metadata-cache:file-1',
		});
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		const preparation = enqueueSelectedBridgeWorkerFileViewContentReadyPreparation({
			...makePreparationProps({
				contentRequestDescriptors: [makeContentRequestDescriptor('file body\n')],
				fetchContent: async (): Promise<Response> => {
					throw new Error('network unavailable');
				},
				postedMessages,
				pump,
				store,
			}),
		});

		pump.runUntilBudget();
		await flushBridgeWorkerPreparationContinuations();
		pump.runUntilBudget();
		await preparation.completion;

		expect(postedMessages).toEqual([
			{
				message: {
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					kind: 'slicePatch',
					epoch: 7,
					sequence: 12,
					transferDescriptors: [],
					patches: [
						{
							slice: 'rowPaint',
							operation: 'delete',
							itemId: 'file-1',
						},
						{
							slice: 'contentAvailability',
							operation: 'upsert',
							itemId: 'file-1',
							payload: { state: 'failed' },
						},
					],
				},
				transferList: [],
			},
		]);
		expect(store.getState().availabilityByItemId.get('file-1')).toBe('failed');
		expect(store.getState().paintReadyByItemId.has('file-1')).toBe(false);
		expect(store.getState().byteCache.has('file-view:metadata-cache:file-1')).toBe(false);
	});

	test('skips enqueue when selected File View content is no longer current or demand eligible', async () => {
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 5,
			now: () => 0,
		});
		const store = createBridgeCommWorkerStore({
			contentItems: [],
			rows: [{ id: 'file-without-metadata', parentId: null, index: 0 }],
		});
		store.actions.applySelectedFact({ epoch: 7, itemId: 'file-without-metadata' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		const preparation = enqueueSelectedBridgeWorkerFileViewContentReadyPreparation({
			...makePreparationProps({
				contentRequestDescriptors: [],
				itemId: 'file-without-metadata',
				postedMessages: [],
				pump,
				store,
			}),
		});

		await preparation.completion;

		expect(preparation.enqueued).toBe(false);
		expect(pump.getPendingWorkIds()).toEqual([]);
	});
});

const descriptorByUrl = new Map<string, { readonly text: string }>();

interface DeferredResponse {
	readonly promise: Promise<Response>;
	readonly resolve: () => void;
}

interface MakePreparationPropsOptions {
	readonly bridgeDemandRank?: { readonly lane: 'selected'; readonly priority: number };
	readonly budget?: {
		readonly className: 'interactive';
		readonly maxBytes: number;
		readonly maxWindowLines: number;
	};
	readonly contentRequestDescriptors: readonly BridgeWorkerFileViewContentRequestDescriptor[];
	readonly fetchContent?: (url: string, init?: RequestInit) => Promise<Response>;
	readonly itemId?: string;
	readonly postedMessages: PostedBridgeWorkerPreparationMessage[];
	readonly pump: ReturnType<typeof createWorkerContentPreparationPump>;
	readonly requestPreparationDrain?: () => void;
	readonly store: BridgeCommWorkerStore;
}

function makePreparationProps(options: MakePreparationPropsOptions): {
	readonly bridgeDemandRank: { readonly lane: 'selected'; readonly priority: number };
	readonly budget: {
		readonly className: 'interactive';
		readonly maxBytes: number;
		readonly maxWindowLines: number;
	};
	readonly contentRequestDescriptors: readonly BridgeWorkerFileViewContentRequestDescriptor[];
	readonly epoch: number;
	readonly fetchContent?: (url: string, init?: RequestInit) => Promise<Response>;
	readonly itemId: string;
	readonly port: BridgeCommWorkerPort;
	readonly pump: ReturnType<typeof createWorkerContentPreparationPump>;
	readonly requestPreparationDrain?: () => void;
	readonly sequence: number;
	readonly store: BridgeCommWorkerStore;
} {
	return {
		bridgeDemandRank: options.bridgeDemandRank ?? { lane: 'selected', priority: 0 },
		budget: options.budget ?? {
			className: 'interactive',
			maxBytes: 512 * 1024,
			maxWindowLines: 50,
		},
		contentRequestDescriptors: options.contentRequestDescriptors,
		epoch: 7,
		...(options.fetchContent === undefined ? {} : { fetchContent: options.fetchContent }),
		itemId: options.itemId ?? 'file-1',
		port: makePostedMessagePort(options.postedMessages),
		pump: options.pump,
		...(options.requestPreparationDrain === undefined
			? {}
			: { requestPreparationDrain: options.requestPreparationDrain }),
		sequence: 12,
		store: options.store,
	};
}

function createDeferredResponse(text: string): DeferredResponse {
	let resolveResponse: (response: Response) => void = noopResolveDeferredResponse;
	const promise = new Promise<Response>((resolve) => {
		resolveResponse = resolve;
	});
	return {
		promise,
		resolve: (): void => {
			resolveResponse(new Response(text));
		},
	};
}

function createSelectedFileViewPreparationStore(): BridgeCommWorkerStore {
	return createBridgeCommWorkerStore({
		contentItems: [makeWorkerFileViewContentMetadata('file-1')],
		rows: [{ id: 'file-1', parentId: null, index: 0 }],
	});
}

function makeWorkerFileViewContentMetadata(itemId: string): BridgeWorkerFileViewContentMetadata {
	return {
		itemId,
		path: 'Sources/App/FileView.swift',
		language: 'swift',
		cacheKey: `file-view:metadata-cache:${itemId}`,
		sizeBytes: 128,
		contentHandle: `handle-${itemId}`,
		descriptorId: `descriptor-${itemId}`,
		contentHash: `sha256:${itemId}`,
		virtualizedExtentKind: 'exactLineCount',
		lineCount: 1,
		isBinary: false,
		canFetchContent: true,
	};
}

function makeContentRequestDescriptor(
	text: string,
	itemId = 'file-1',
): BridgeWorkerFileViewContentRequestDescriptor {
	const descriptor: BridgeWorkerFileViewContentRequestDescriptor = {
		itemId,
		path: 'Sources/App/FileView.swift',
		handleId: `handle-${itemId}`,
		descriptorId: `descriptor-${itemId}`,
		resourceKind: 'worktree.fileContent',
		resourceUrl: `agentstudio://resource/worktree-file/worktree.fileContent/descriptor-${itemId}?cursor=cursor-${itemId}&generation=7`,
		contentHash: `sha256:${itemId}`,
		contentHashAlgorithm: 'sha256',
		language: 'swift',
		sizeBytes: 128,
		maxBytes: 4096,
		isBinary: false,
	};
	descriptorByUrl.set(descriptor.resourceUrl, { text });
	return descriptor;
}

async function flushBridgeWorkerPreparationContinuations(): Promise<void> {
	await Array.from({ length: 50 }).reduce<Promise<void>>(
		(previousFlush) => previousFlush.then(() => Promise.resolve()),
		Promise.resolve(),
	);
}

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

function noopResolveDeferredResponse(_response: Response): void {}
