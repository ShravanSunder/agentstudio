import { describe, expect, test } from 'vitest';

import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import { dispatchSelectedBridgeWorkerReviewContentReady } from './bridge-comm-worker-review-runtime.js';
import {
	makeContentRequestDescriptor,
	openReviewContentFromDescriptorMap,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import {
	createBridgeCommWorkerStore,
	type BridgeCommWorkerStore,
} from './bridge-comm-worker-store.js';
import type { BridgeProductReviewContentDescriptor } from './bridge-product-content-contracts.js';
import type { BridgeProductContentStream } from './bridge-product-transport-contract.js';
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
	test('select command posts typed Review Pierre job before typed Review render patch', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
		const openedDescriptorRoles: BridgeProductReviewContentDescriptor['role'][] = [];
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
			workerDerivationEpoch: 7,
			openContent: (descriptor, abortSignal): BridgeProductContentStream<'review.content'> => {
				openedDescriptorRoles.push(descriptor.role);
				return openReviewContentFromDescriptorMap(descriptor, abortSignal);
			},
			itemId: 'item-1',
			port,
			renderSemantics: [makeRenderSemantics()],
			sequence: 12,
			store,
		});

		expect(openedDescriptorRoles).toEqual(['base', 'head']);
		expect(postedMessages).toHaveLength(2);
		expect(postedMessages[0]?.message).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'reviewPierreRenderJob',
			publicationSequence: 12,
			surface: 'review',
			workerDerivationEpoch: 7,
			job: {
				itemId: 'item-1',
				renderKind: 'reviewDiff',
				contentCacheKey:
					'pierre-content:fixture-preview:sha256:item-1:base:generation-4|pierre-content:fixture-preview:sha256:item-1:head:generation-4',
				payload: {
					kind: 'codeViewDiffItem',
				},
			},
		});
		const pierreJobMessage = postedMessages[0]?.message;
		if (pierreJobMessage?.kind !== 'reviewPierreRenderJob') {
			throw new Error('Expected Review Pierre render job message first.');
		}
		expect(pierreJobMessage.transferDescriptors).toEqual([
			{
				messageKind: 'reviewPierreRenderJob',
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
				kind: 'reviewRenderPatch',
				publicationSequence: 12,
				surface: 'review',
				transferDescriptors: [],
				workerDerivationEpoch: 7,
				patches: [
					{
						slice: 'rowPaint',
						operation: 'upsert',
						itemId: 'item-1',
						payload: {
							contentCacheKey:
								'pierre-content:fixture-preview:sha256:item-1:base:generation-4|pierre-content:fixture-preview:sha256:item-1:head:generation-4',
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
				makeDescriptors: () => [
					makeContentRequestDescriptor({ role: 'file', text: 'unused file content' }),
					makeContentRequestDescriptor({ role: 'head', text: 'added head content' }),
				],
				expectedRoles: ['head'],
			},
			{
				name: 'non-diff review item prefers head over fallback roles',
				semantics: makeRenderSemantics({ itemKind: 'file' }),
				makeDescriptors: () => [
					makeContentRequestDescriptor({ role: 'base', text: 'unused base content' }),
					makeContentRequestDescriptor({ role: 'diff', text: 'unused diff content' }),
					makeContentRequestDescriptor({ role: 'head', text: 'file head content' }),
					makeContentRequestDescriptor({ role: 'file', text: 'unused file content' }),
				],
				expectedRoles: ['head'],
			},
		];

		await cases.reduce<Promise<void>>(
			(previousRun, scenario) =>
				previousRun.then(() => runRuntimeDescriptorSelectionCase(scenario)),
			Promise.resolve(),
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
					kind: 'reviewRenderPatch',
					publicationSequence: 12,
					surface: 'review',
					transferDescriptors: [],
					workerDerivationEpoch: 7,
					patches: [
						{
							slice: 'contentAvailability',
							operation: 'upsert',
							itemId: 'item-1',
							payload: { reason: 'descriptor_missing', state: 'unavailable' },
						},
					],
				},
				transferList: [],
			},
		]);
	});

	test('publishes unavailable when selected diff descriptors cannot plan a render job', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
		const openedDescriptorRoles: BridgeProductReviewContentDescriptor['role'][] = [];
		const store = createSelectedReviewRuntimeStore();
		store.actions.applySelectedFact({ epoch: 7, itemId: 'item-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		await dispatchSelectedBridgeWorkerReviewContentReady({
			...makeDispatchProps({
				contentRequestDescriptors: [
					makeContentRequestDescriptor({ role: 'base', text: 'base content' }),
				],
				openContent: (descriptor, abortSignal): BridgeProductContentStream<'review.content'> => {
					openedDescriptorRoles.push(descriptor.role);
					return openReviewContentFromDescriptorMap(descriptor, abortSignal);
				},
				postedMessages,
				renderSemantics: [makeRenderSemantics()],
				store,
			}),
		});

		expect(openedDescriptorRoles).toEqual([]);
		expect(store.getState().availabilityByItemId.get('item-1')).toBe('unavailable');
		expect(postedMessages).toHaveLength(1);
		expect(postedMessages[0]).toMatchObject({
			message: {
				kind: 'reviewRenderPatch',
				publicationSequence: 12,
				surface: 'review',
				workerDerivationEpoch: 7,
				patches: [
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'item-1',
						payload: { reason: 'descriptor_rejected', state: 'unavailable' },
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
				openContent: (descriptor) => makeFailedReviewContentStream(descriptor),
				postedMessages,
				renderSemantics: [makeRenderSemantics()],
				store,
			}),
		});

		expect(store.getState().availabilityByItemId.get('item-1')).toBe('failed');
		expect(postedMessages).toHaveLength(1);
		expect(postedMessages[0]).toMatchObject({
			message: {
				kind: 'reviewRenderPatch',
				publicationSequence: 12,
				surface: 'review',
				workerDerivationEpoch: 7,
				patches: [
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'item-1',
						payload: { reason: 'load_failed', state: 'failed' },
					},
				],
			},
			transferList: [],
		});
	});
});

interface RuntimeDescriptorSelectionCase {
	readonly expectedRoles: readonly BridgeProductReviewContentDescriptor['role'][];
	readonly makeDescriptors: () => readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly name: string;
	readonly semantics: BridgeWorkerReviewRenderSemantics;
}

async function runRuntimeDescriptorSelectionCase(
	scenario: RuntimeDescriptorSelectionCase,
): Promise<void> {
	const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
	const openedDescriptorRoles: BridgeProductReviewContentDescriptor['role'][] = [];
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
		contentRequestDescriptors: scenario.makeDescriptors(),
		epoch: 7,
		workerDerivationEpoch: 7,
		openContent: (descriptor, abortSignal): BridgeProductContentStream<'review.content'> => {
			openedDescriptorRoles.push(descriptor.role);
			return openReviewContentFromDescriptorMap(descriptor, abortSignal);
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

	expect(openedDescriptorRoles, scenario.name).toEqual(scenario.expectedRoles);
	expect(postedMessages[0]?.message, scenario.name).toMatchObject({
		kind: 'reviewPierreRenderJob',
		publicationSequence: 12,
		surface: 'review',
		workerDerivationEpoch: 7,
		job: { itemId: 'item-1' },
	});
	expect(postedMessages[1]?.message, scenario.name).toMatchObject({
		kind: 'reviewRenderPatch',
		publicationSequence: 12,
		surface: 'review',
		workerDerivationEpoch: 7,
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
}

interface MakeDispatchPropsOptions {
	readonly contentRequestDescriptors: readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly openContent?: DispatchSelectedReviewRuntimeProps['openContent'];
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
		workerDerivationEpoch: 7,
		...(options.openContent === undefined ? {} : { openContent: options.openContent }),
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

function makeFailedReviewContentStream(
	descriptor: BridgeProductReviewContentDescriptor,
): BridgeProductContentStream<'review.content'> {
	return {
		contentKind: 'review.content',
		contentRequestId: `content-request-${descriptor.descriptorId}`,
		frames: emptyReviewContentFrames(),
		terminal: Promise.resolve({
			code: 'internal',
			contentKind: 'review.content',
			descriptorId: descriptor.descriptorId,
			kind: 'error',
			retryable: true,
			safeMessage: 'simulated worker content stream failure',
		}),
	};
}

async function* emptyReviewContentFrames(): AsyncIterable<never> {}
