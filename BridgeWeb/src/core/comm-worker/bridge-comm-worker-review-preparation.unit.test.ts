import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
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
				makeContentRequestDescriptor({ role: 'base', text: 'base content\n' }),
				makeContentRequestDescriptor({ role: 'head', text: 'head content\n' }),
			],
			epoch: 7,
			fetchContent: async (url: string): Promise<Response> => {
				executionOrder.push('selected-fetch');
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return makeImmediateTextResponse(descriptor.text);
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
		await flushBridgeWorkerPreparationContinuations();
		const completionRunResult = pump.runUntilBudget();
		await preparation.completion;

		expect(runResult.completedIds).toEqual([]);
		expect(runResult.yielded).toBe(true);
		expect(completionRunResult.completedIds).toEqual([preparation.workId]);
		expect(executionOrder).toEqual([
			'selected-fetch',
			'selected-fetch',
			'background',
			'background',
		]);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'pierreRenderJob',
			'slicePatch',
		]);
	});

	test('keeps post-fetch render-job preparation inside a pump continuation', async () => {
		const postedMessages: PostedBridgeWorkerPreparationMessage[] = [];
		const fetchResponses = [
			createDeferredResponse('base content\n'),
			createDeferredResponse('head content\n'),
		];
		const allFetchResponses = [...fetchResponses];
		const fetchCalls: string[] = [];
		let drainRequestCount = 0;
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 5,
			now: () => 0,
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
				makeContentRequestDescriptor({ role: 'base', text: 'base content\n' }),
				makeContentRequestDescriptor({ role: 'head', text: 'head content\n' }),
			],
			epoch: 7,
			fetchContent: async (url: string): Promise<Response> => {
				fetchCalls.push(url);
				const response = fetchResponses.shift();
				if (response === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return response.promise;
			},
			itemId: 'item-1',
			port: makePostedMessagePort(postedMessages),
			pump,
			renderSemantics: [makeRenderSemantics()],
			requestPreparationDrain: () => {
				drainRequestCount += 1;
			},
			sequence: 12,
			store,
		});

		const firstRun = pump.runUntilBudget();

		expect(firstRun.completedIds).toEqual([]);
		expect(fetchCalls).toEqual([
			'agentstudio://resource/review/content/handle-item-1-base?generation=4',
			'agentstudio://resource/review/content/handle-item-1-head?generation=4',
		]);
		expect(postedMessages).toEqual([]);

		for (const response of allFetchResponses) {
			response.resolve();
		}
		await flushBridgeWorkerPreparationContinuations();

		expect(postedMessages).toEqual([]);
		expect(drainRequestCount).toBe(1);
		expect(pump.getPendingWorkIds()).toEqual([preparation.workId]);

		const secondRun = pump.runUntilBudget();
		await preparation.completion;

		expect(secondRun.completedIds).toEqual([preparation.workId]);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'pierreRenderJob',
			'slicePatch',
		]);
	});

	test('drops stale selected review preparation before publishing content messages', async () => {
		const postedMessages: PostedBridgeWorkerPreparationMessage[] = [];
		const fetchCalls: string[] = [];
		const telemetrySamples: BridgeTelemetrySample[] = [];
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
				return makeImmediateTextResponse(descriptor.text);
			},
			itemId: 'item-1',
			port: makePostedMessagePort(postedMessages),
			pump,
			renderSemantics: [makeRenderSemantics()],
			sequence: 12,
			store,
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});

		const runResult = pump.runUntilBudget();
		await flushBridgeWorkerPreparationContinuations();
		const completionRunResult = pump.runUntilBudget();
		await preparation.completion;

		expect(runResult.completedIds).toEqual([]);
		expect(completionRunResult.completedIds).toEqual([preparation.workId]);
		expect(fetchCalls).toEqual([
			'agentstudio://resource/review/content/handle-item-1-base?generation=4',
			'agentstudio://resource/review/content/handle-item-1-head?generation=4',
		]);
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
		expect(postedMessages).toEqual([]);
	});

	test('records stale selected review preparation before fetch starts', async () => {
		const postedMessages: PostedBridgeWorkerPreparationMessage[] = [];
		const fetchCalls: string[] = [];
		const telemetrySamples: BridgeTelemetrySample[] = [];
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
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return makeImmediateTextResponse(descriptor.text);
			},
			itemId: 'item-1',
			port: makePostedMessagePort(postedMessages),
			pump,
			renderSemantics: [makeRenderSemantics()],
			sequence: 12,
			store,
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});
		store.actions.applySelectedFact({ epoch: 8, itemId: 'item-2' });
		store.actions.takePendingSlicePatchEvent({ epoch: 8, sequence: 13 });

		const runResult = pump.runUntilBudget();
		await preparation.completion;

		expect(runResult.completedIds).toEqual([preparation.workId]);
		expect(fetchCalls).toEqual([]);
		expectSelectedContentDroppedTelemetry(telemetrySamples, 'stale_before_fetch');
		expect(postedMessages).toEqual([]);
	});

	test('records stale selected review preparation after fetch before publish', async () => {
		const postedMessages: PostedBridgeWorkerPreparationMessage[] = [];
		const fetchResponses = [
			createDeferredResponse('base content'),
			createDeferredResponse('head content'),
		];
		const allFetchResponses = [...fetchResponses];
		const telemetrySamples: BridgeTelemetrySample[] = [];
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
			fetchContent: async (): Promise<Response> => {
				const response = fetchResponses.shift();
				if (response === undefined) {
					throw new Error('Unexpected review content fetch.');
				}
				return response.promise;
			},
			itemId: 'item-1',
			port: makePostedMessagePort(postedMessages),
			pump,
			renderSemantics: [makeRenderSemantics()],
			sequence: 12,
			store,
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});

		const firstRun = pump.runUntilBudget();
		for (const response of allFetchResponses) {
			response.resolve();
		}
		await flushBridgeWorkerPreparationContinuations();
		store.actions.applySelectedFact({ epoch: 8, itemId: 'item-2' });
		store.actions.takePendingSlicePatchEvent({ epoch: 8, sequence: 13 });
		const secondRun = pump.runUntilBudget();
		await preparation.completion;

		expect(firstRun.completedIds).toEqual([]);
		expect(secondRun.completedIds).toEqual([preparation.workId]);
		expectSelectedContentDroppedTelemetry(telemetrySamples, 'stale_before_publish');
		expect(postedMessages).toEqual([]);
	});

	test('rejects preparation completion when post-fetch publish throws', async () => {
		const pump = createWorkerContentPreparationPump({
			maxSliceMs: 5,
			now: () => 0,
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
				maxBytes: 1,
				maxWindowLines: 50,
			},
			contentRequestDescriptors: [
				makeContentRequestDescriptor({ role: 'base', text: 'base content\n' }),
				makeContentRequestDescriptor({ role: 'head', text: 'head content\n' }),
			],
			epoch: 7,
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return makeImmediateTextResponse(descriptor.text);
			},
			itemId: 'item-1',
			port: makeThrowingPostedMessagePort(),
			pump,
			renderSemantics: [makeRenderSemantics()],
			sequence: 12,
			store,
		});
		const completionResult = preparation.completion.then(
			() => null,
			(error: unknown) => error,
		);

		pump.runUntilBudget();
		await flushBridgeWorkerPreparationContinuations();
		pump.runUntilBudget();

		await expect(completionResult).resolves.toBeInstanceOf(Error);
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

interface DeferredResponse {
	readonly promise: Promise<Response>;
	readonly resolve: () => void;
}

function createDeferredResponse(text: string): DeferredResponse {
	let resolveResponse: (response: Response) => void = noopResolveDeferredResponse;
	const promise = new Promise<Response>((resolve) => {
		resolveResponse = resolve;
	});
	return {
		promise,
		resolve: (): void => {
			resolveResponse(makeImmediateTextResponse(text));
		},
	};
}

function makeImmediateTextResponse(text: string): Response {
	const encodedText = new TextEncoder().encode(text);
	return new Response(
		new ReadableStream({
			start: (controller): void => {
				controller.enqueue(encodedText);
				controller.close();
			},
		}),
	);
}

async function flushBridgeWorkerPreparationContinuations(): Promise<void> {
	await Array.from({ length: 50 }).reduce<Promise<void>>(
		(previousFlush) => previousFlush.then(() => Promise.resolve()),
		Promise.resolve(),
	);
}

function noopResolveDeferredResponse(_response: Response): void {}

function expectSelectedContentDroppedTelemetry(
	telemetrySamples: readonly BridgeTelemetrySample[],
	dropReason: string,
): void {
	expect(telemetrySamples).toContainEqual(
		expect.objectContaining({
			name: 'performance.bridge.web.selected_content_dropped',
			durationMilliseconds: null,
			stringAttributes: expect.objectContaining({
				'agentstudio.bridge.drop_reason': dropReason,
				'agentstudio.bridge.phase': 'selected_content_dropped',
				'agentstudio.bridge.result': 'dropped',
				'agentstudio.bridge.transport': 'content',
				'agentstudio.bridge.viewer': 'review',
			}),
		}),
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

function makeThrowingPostedMessagePort(): BridgeCommWorkerPort {
	return {
		postMessage: (): void => {
			throw new Error('publish failed');
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
	const textByteLength = new TextEncoder().encode(props.text).byteLength;
	const descriptor: BridgeWorkerReviewContentRequestDescriptor = {
		itemId: 'item-1',
		role: props.role,
		handleId: `handle-item-1-${props.role}`,
		reviewGeneration: 4,
		resourceUrl: `agentstudio://resource/review/content/handle-item-1-${props.role}?generation=4`,
		contentHash: `sha256:item-1:${props.role}`,
		contentHashAlgorithm: 'fixture-preview',
		language: 'swift',
		sizeBytes: textByteLength,
		expectedBytes: textByteLength,
		maxBytes: Math.max(textByteLength, 1),
		isBinary: false,
	};
	descriptorByUrl.set(descriptor.resourceUrl, { text: props.text });
	return descriptor;
}
