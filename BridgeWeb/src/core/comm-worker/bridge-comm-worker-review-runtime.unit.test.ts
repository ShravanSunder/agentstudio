import { describe, expect, test } from 'vitest';

import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import { dispatchSelectedBridgeWorkerReviewContentReady } from './bridge-comm-worker-review-runtime.js';
import {
	createBridgeCommWorkerStore,
	type BridgeCommWorkerStore,
} from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerReviewContentRequestDescriptor,
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

interface PostedBridgeWorkerRuntimeMessage {
	readonly message: BridgeWorkerServerToMainMessage;
	readonly transferList: readonly Transferable[] | undefined;
}

describe('Bridge comm worker review runtime', () => {
	test('select command posts prepared Pierre job before content-ready slice patch', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
		const fetchCalls: string[] = [];
		const port: BridgeCommWorkerPort = {
			postMessage: (
				message: BridgeWorkerServerToMainMessage,
				transferList?: Transferable[],
			): void => {
				postedMessages.push({ message, transferList });
			},
			addEventListener: (): void => {},
		};
		const store = createSelectedReviewRuntimeStore();
		store.actions.applySelectedFact({ epoch: 7, itemId: 'item-1' });
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 })).toMatchObject({
			kind: 'slicePatch',
			patches: [
				{ slice: 'selection', operation: 'upsert' },
				{ slice: 'contentAvailability', itemId: 'item-1', payload: { state: 'loading' } },
			],
		});

		await dispatchSelectedBridgeWorkerReviewContentReady({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentRequestDescriptors: [
				makeContentRequestDescriptor({ role: 'base', text: 'base content' }),
				makeContentRequestDescriptor({ role: 'head', text: 'head content' }),
				makeContentRequestDescriptor({ role: 'file', text: 'unused full file' }),
			],
			epoch: 7,
			fetchContent: async (url: string): Promise<Response> => {
				fetchCalls.push(url);
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected review content URL ${url}.`);
				}
				return new Response(descriptor.text);
			},
			itemId: 'item-1',
			port,
			renderSemantics: [makeRenderSemantics()],
			sequence: 12,
			store,
		});

		expect(fetchCalls).toEqual([
			'agentstudio://resource/review/content/handle-item-1-base?generation=4',
			'agentstudio://resource/review/content/handle-item-1-head?generation=4',
		]);
		expect(postedMessages).toHaveLength(2);
		expect(postedMessages[0]?.message).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'pierreRenderJob',
			job: {
				itemId: 'item-1',
				renderKind: 'reviewDiff',
				contentCacheKey:
					'pierre-content:fixture-preview:sha256:item-1:base|pierre-content:fixture-preview:sha256:item-1:head',
				payload: {
					kind: 'codeViewDiffItem',
				},
			},
		});
		const pierreJobMessage = postedMessages[0]?.message;
		if (pierreJobMessage?.kind !== 'pierreRenderJob') {
			throw new Error('Expected Pierre render job message first.');
		}
		expect(pierreJobMessage.transferDescriptors).toEqual([
			{
				messageKind: 'pierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: pierreJobMessage.job.payloadByteLength,
				mode: 'clone',
			},
		]);
		if (pierreJobMessage.job.payload.kind !== 'codeViewDiffItem') {
			throw new Error('Expected CodeView diff item payload.');
		}
		expect(pierreJobMessage.job.payload.item.fileDiff.additionLines).toContain('head content');
		expect(pierreJobMessage.job.payload.item.fileDiff.deletionLines).toContain('base content');
		expect(postedMessages[0]?.transferList).toEqual([]);
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
						itemId: 'item-1',
						payload: {
							contentCacheKey:
								'pierre-content:fixture-preview:sha256:item-1:base|pierre-content:fixture-preview:sha256:item-1:head',
						},
					},
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'item-1',
						payload: { state: 'ready' },
					},
				],
			},
			transferList: [],
		});
	});

	test('fetches only the first supported fallback descriptor for one-sided and file renders', async () => {
		const cases: readonly RuntimeDescriptorSelectionCase[] = [
			{
				name: 'added diff prefers head over full file',
				semantics: makeRenderSemantics({ changeKind: 'added' }),
				descriptors: [
					makeContentRequestDescriptor({ role: 'file', text: 'unused file content' }),
					makeContentRequestDescriptor({ role: 'head', text: 'added head content' }),
				],
				expectedUrls: ['agentstudio://resource/review/content/handle-item-1-head?generation=4'],
			},
			{
				name: 'non-diff review item prefers head over fallback roles',
				semantics: makeRenderSemantics({ itemKind: 'file' }),
				descriptors: [
					makeContentRequestDescriptor({ role: 'base', text: 'unused base content' }),
					makeContentRequestDescriptor({ role: 'diff', text: 'unused diff content' }),
					makeContentRequestDescriptor({ role: 'head', text: 'file head content' }),
					makeContentRequestDescriptor({ role: 'file', text: 'unused file content' }),
				],
				expectedUrls: ['agentstudio://resource/review/content/handle-item-1-head?generation=4'],
			},
		];

		await Promise.all(
			cases.map(async (scenario) => {
				const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
				const fetchCalls: string[] = [];
				const store = createSelectedReviewRuntimeStore();
				store.actions.applySelectedFact({ epoch: 7, itemId: 'item-1' });
				store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

				await dispatchSelectedBridgeWorkerReviewContentReady({
					bridgeDemandRank: { lane: 'selected', priority: 0 },
					budget: {
						className: 'interactive',
						maxBytes: 512 * 1024,
						maxWindowLines: 50,
					},
					contentRequestDescriptors: scenario.descriptors,
					epoch: 7,
					fetchContent: async (url: string): Promise<Response> => {
						fetchCalls.push(url);
						const descriptor = descriptorByUrl.get(url);
						if (descriptor === undefined) {
							throw new Error(`Unexpected review content URL ${url}.`);
						}
						return new Response(descriptor.text);
					},
					itemId: 'item-1',
					port: {
						postMessage: (
							message: BridgeWorkerServerToMainMessage,
							transferList?: Transferable[],
						): void => {
							postedMessages.push({ message, transferList });
						},
						addEventListener: (): void => {},
					},
					renderSemantics: [scenario.semantics],
					sequence: 12,
					store,
				});

				expect(fetchCalls, scenario.name).toEqual(scenario.expectedUrls);
				expect(postedMessages[0]?.message, scenario.name).toMatchObject({
					kind: 'pierreRenderJob',
					job: { itemId: 'item-1' },
				});
				expect(postedMessages[1]?.message, scenario.name).toMatchObject({
					kind: 'slicePatch',
					patches: [
						{ slice: 'rowPaint', operation: 'upsert', itemId: 'item-1' },
						{
							slice: 'contentAvailability',
							operation: 'upsert',
							itemId: 'item-1',
							payload: { state: 'ready' },
						},
					],
				});
			}),
		);
	});

	test('publishes unavailable instead of leaving selected content loading when semantics are absent', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
		const store = createSelectedReviewRuntimeStore();
		store.actions.applySelectedFact({ epoch: 7, itemId: 'item-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		await dispatchSelectedBridgeWorkerReviewContentReady({
			...makeDispatchProps({
				contentRequestDescriptors: [
					makeContentRequestDescriptor({ role: 'base', text: 'base content' }),
					makeContentRequestDescriptor({ role: 'head', text: 'head content' }),
				],
				postedMessages,
				renderSemantics: [],
				store,
			}),
		});

		expect(store.getState().availabilityByItemId.get('item-1')).toBe('unavailable');
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
							itemId: 'item-1',
							payload: { state: 'unavailable' },
						},
					],
				},
				transferList: [],
			},
		]);
	});

	test('publishes unavailable when selected diff descriptors cannot plan a render job', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
		const fetchCalls: string[] = [];
		const store = createSelectedReviewRuntimeStore();
		store.actions.applySelectedFact({ epoch: 7, itemId: 'item-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		await dispatchSelectedBridgeWorkerReviewContentReady({
			...makeDispatchProps({
				contentRequestDescriptors: [
					makeContentRequestDescriptor({ role: 'base', text: 'base content' }),
				],
				fetchContent: async (url: string): Promise<Response> => {
					fetchCalls.push(url);
					return fetchContentFromDescriptorMap(url);
				},
				postedMessages,
				renderSemantics: [makeRenderSemantics()],
				store,
			}),
		});

		expect(fetchCalls).toEqual([]);
		expect(store.getState().availabilityByItemId.get('item-1')).toBe('unavailable');
		expect(postedMessages).toHaveLength(1);
		expect(postedMessages[0]).toMatchObject({
			message: {
				kind: 'slicePatch',
				patches: [
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'item-1',
						payload: { state: 'unavailable' },
					},
				],
			},
			transferList: [],
		});
	});

	test('publishes failed instead of leaving selected content loading when fetch rejects', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
		const store = createSelectedReviewRuntimeStore();
		store.actions.applySelectedFact({ epoch: 7, itemId: 'item-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		await dispatchSelectedBridgeWorkerReviewContentReady({
			...makeDispatchProps({
				contentRequestDescriptors: [
					makeContentRequestDescriptor({ role: 'base', text: 'base content' }),
					makeContentRequestDescriptor({ role: 'head', text: 'head content' }),
				],
				fetchContent: async (): Promise<Response> => {
					throw new Error('simulated worker fetch failure');
				},
				postedMessages,
				renderSemantics: [makeRenderSemantics()],
				store,
			}),
		});

		expect(store.getState().availabilityByItemId.get('item-1')).toBe('failed');
		expect(postedMessages).toHaveLength(1);
		expect(postedMessages[0]).toMatchObject({
			message: {
				kind: 'slicePatch',
				patches: [
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'item-1',
						payload: { state: 'failed' },
					},
				],
			},
			transferList: [],
		});
	});
});

const descriptorByUrl = new Map<string, { readonly text: string }>();

interface RuntimeDescriptorSelectionCase {
	readonly descriptors: readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly expectedUrls: readonly string[];
	readonly name: string;
	readonly semantics: BridgeWorkerReviewRenderSemantics;
}

interface MakeDispatchPropsOptions {
	readonly contentRequestDescriptors: readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly fetchContent?: (url: string) => Promise<Response>;
	readonly postedMessages: PostedBridgeWorkerRuntimeMessage[];
	readonly renderSemantics: readonly BridgeWorkerReviewRenderSemantics[];
	readonly store: BridgeCommWorkerStore;
}

type DispatchSelectedReviewRuntimeProps = Parameters<
	typeof dispatchSelectedBridgeWorkerReviewContentReady
>[0];

function makeDispatchProps(options: MakeDispatchPropsOptions): DispatchSelectedReviewRuntimeProps {
	return {
		bridgeDemandRank: { lane: 'selected', priority: 0 },
		budget: {
			className: 'interactive',
			maxBytes: 512 * 1024,
			maxWindowLines: 50,
		},
		contentRequestDescriptors: options.contentRequestDescriptors,
		epoch: 7,
		...(options.fetchContent === undefined ? {} : { fetchContent: options.fetchContent }),
		itemId: 'item-1',
		port: {
			postMessage: (
				message: BridgeWorkerServerToMainMessage,
				transferList?: Transferable[],
			): void => {
				options.postedMessages.push({ message, transferList });
			},
			addEventListener: (): void => {},
		},
		renderSemantics: options.renderSemantics,
		sequence: 12,
		store: options.store,
	};
}

async function fetchContentFromDescriptorMap(url: string): Promise<Response> {
	const descriptor = descriptorByUrl.get(url);
	if (descriptor === undefined) {
		throw new Error(`Unexpected review content URL ${url}.`);
	}
	return new Response(descriptor.text);
}

function createSelectedReviewRuntimeStore(): BridgeCommWorkerStore {
	return createBridgeCommWorkerStore({
		contentItems: [makeWorkerReviewContentMetadata()],
		rows: [{ id: 'item-1', parentId: null, index: 0 }],
	});
}

function makeWorkerReviewContentMetadata(): BridgeWorkerReviewContentMetadata {
	return {
		itemId: 'item-1',
		path: 'Sources/App/item-1.swift',
		language: 'swift',
		cacheKey: 'item-1:base|item-1:head',
		sizeBytes: 1024,
		availableContentRoles: ['base', 'head'],
		contentLineCountsByRole: { base: 100, head: 80 },
	};
}

function makeRenderSemantics(
	props: Partial<Pick<BridgeWorkerReviewRenderSemantics, 'changeKind' | 'itemKind'>> = {},
): BridgeWorkerReviewRenderSemantics {
	return {
		itemId: 'item-1',
		itemKind: props.itemKind ?? 'diff',
		changeKind: props.changeKind ?? 'modified',
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
