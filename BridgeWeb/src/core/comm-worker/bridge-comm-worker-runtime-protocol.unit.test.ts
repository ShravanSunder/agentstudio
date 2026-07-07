import { describe, expect, test } from 'vitest';

import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import {
	encodeBridgeWorkerFileViewSourceUpdateCommand,
	encodeBridgeWorkerReviewSourceUpdateCommand,
	encodeBridgeWorkerSelectCommand,
} from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import { createWorkerContentPreparationPump } from './bridge-worker-content-preparation-pump.js';
import type {
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerFileViewContentRequestDescriptor,
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerReviewContentRequestDescriptor,
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

interface PostedBridgeWorkerRuntimeMessage {
	readonly message: BridgeWorkerServerToMainMessage;
	readonly transferList: readonly Transferable[] | undefined;
}

describe('Bridge comm worker runtime protocol', () => {
	test('drains selected review content prep through the worker port after local select slices', async () => {
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
				makeContentRequestDescriptor({ role: 'base', text: 'base body' }),
				makeContentRequestDescriptor({ role: 'head', text: 'head body' }),
			],
			createSequence: createBridgeWorkerSequenceCounter(41),
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
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 7,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);

		expect(scheduledDrains).toHaveLength(1);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
		]);
		expect(postedMessages[0]?.transferList).toBeUndefined();
		expect(postedMessages[1]?.transferList).toBeUndefined();
		clockMs += 1;

		const firstDrainCompletion = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toHaveLength(2);
		const secondDrainResult = await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		const firstDrainResult = await firstDrainCompletion;

		expect(firstDrainResult.completedIds).toEqual([]);
		expect(firstDrainResult.yielded).toBe(false);
		expect(secondDrainResult.completedIds).toEqual(['review-content-ready:item-1:7:42']);
		expect(secondDrainResult.yielded).toBe(false);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'slicePatch',
			'health',
			'pierreRenderJob',
			'slicePatch',
		]);
		expect(postedMessages[2]?.transferList).toEqual([]);
		expect(postedMessages[2]?.message).toMatchObject({
			kind: 'pierreRenderJob',
			job: {
				itemId: 'item-1',
				renderKind: 'reviewDiff',
				payload: {
					kind: 'codeViewDiffItem',
				},
			},
		});
		const pierreJobMessage = postedMessages[2]?.message;
		if (pierreJobMessage?.kind !== 'pierreRenderJob') {
			throw new Error('Expected Pierre render job message.');
		}
		expect(pierreJobMessage.transferDescriptors).toEqual([
			{
				messageKind: 'pierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: pierreJobMessage.job.payloadByteLength,
				mode: 'clone',
			},
		]);
		expect(postedMessages[3]?.message).toMatchObject({
			kind: 'slicePatch',
			epoch: 7,
			sequence: 42,
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

	test('applies source update before first select when the runtime boots empty', () => {
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
			createSequence: createBridgeWorkerSequenceCounter(11),
			renderSemantics: [],
			rows: [],
			schedulePreparationDrain: (drain: BridgeCommWorkerPreparationDrain): void => {
				scheduledDrains.push(drain);
			},
		});

		dispatch.message(
			encodeBridgeWorkerReviewSourceUpdateCommand({
				requestId: 'request-source-update',
				epoch: 1,
				contentItems: [makeWorkerReviewContentMetadata()],
				contentRequestDescriptors: [
					makeContentRequestDescriptor({ role: 'base', text: 'base body' }),
					makeContentRequestDescriptor({ role: 'head', text: 'head body' }),
				],
				renderSemantics: [makeRenderSemantics()],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			}),
		);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 2,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);

		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'health',
			'slicePatch',
			'health',
		]);
		expect(postedMessages[1]?.message).toMatchObject({
			kind: 'slicePatch',
			epoch: 2,
			sequence: 11,
			patches: [
				{
					slice: 'selection',
					operation: 'upsert',
					payload: { selectedItemId: 'item-1' },
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'loading' },
				},
			],
		});
		expect(scheduledDrains).toHaveLength(1);
	});

	test('drains selected File View content prep from retained source descriptors', async () => {
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
			createSequence: createBridgeWorkerSequenceCounter(61),
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected File View content URL ${url}.`);
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
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-view-source-update',
				epoch: 6,
				contentItems: [makeWorkerFileViewContentMetadata()],
				contentRequestDescriptors: [makeFileViewContentRequestDescriptor('file body\n')],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-file-view-select',
				epoch: 7,
				selectedItemId: 'file-1',
				selectedSource: 'user',
			}),
		);

		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'health',
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
		expect(secondDrainResult.completedIds).toEqual(['file-view-content-ready:file-1:7:63']);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'health',
			'slicePatch',
			'health',
			'pierreRenderJob',
			'slicePatch',
		]);
		expect(postedMessages[3]?.message).toMatchObject({
			kind: 'pierreRenderJob',
			job: {
				itemId: 'file-1',
				renderKind: 'fileText',
				payload: {
					kind: 'codeViewFileItem',
				},
			},
		});
		expect(postedMessages[4]?.message).toMatchObject({
			kind: 'slicePatch',
			epoch: 7,
			sequence: 63,
			patches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'file-1',
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'file-1',
					payload: { state: 'ready' },
				},
			],
		});
	});

	test('drains a second selected File View prep after ready descriptor refresh', async () => {
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
			createSequence: createBridgeWorkerSequenceCounter(81),
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected File View content URL ${url}.`);
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
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-view-source-before-ready',
				epoch: 6,
				contentItems: [makeWorkerFileViewContentMetadata()],
				contentRequestDescriptors: [
					makeFileViewContentRequestDescriptor({ generation: 6, text: 'first body\n' }),
				],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-file-view-select-before-ready',
				epoch: 7,
				selectedItemId: 'file-1',
				selectedSource: 'user',
			}),
		);
		clockMs += 1;
		const firstDrainCompletion = assertBridgeCommWorkerPreparationDrain(scheduledDrains[0])();
		await flushBridgeWorkerRuntimeContinuations();
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains[1])();
		await firstDrainCompletion;

		dispatch.message(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-view-source-descriptor-refresh',
				epoch: 7,
				contentItems: [makeWorkerFileViewContentMetadata()],
				contentRequestDescriptors: [
					makeFileViewContentRequestDescriptor({ generation: 8, text: 'refreshed body\n' }),
				],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);
		expect(scheduledDrains).toHaveLength(2);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-file-view-select-after-descriptor-refresh',
				epoch: 8,
				selectedItemId: 'file-1',
				selectedSource: 'programmatic',
			}),
		);
		clockMs += 1;
		const refreshFirstDrainCompletion = assertBridgeCommWorkerPreparationDrain(
			scheduledDrains[2],
		)();
		await flushBridgeWorkerRuntimeContinuations();
		const refreshSecondDrainResult = await assertBridgeCommWorkerPreparationDrain(
			scheduledDrains[3],
		)();
		await refreshFirstDrainCompletion;

		expect(refreshSecondDrainResult.completedIds).toEqual(['file-view-content-ready:file-1:8:86']);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'health',
			'slicePatch',
			'health',
			'pierreRenderJob',
			'slicePatch',
			'health',
			'slicePatch',
			'health',
			'pierreRenderJob',
			'slicePatch',
		]);
		expect(postedMessages[8]?.message).toMatchObject({
			kind: 'pierreRenderJob',
			job: {
				itemId: 'file-1',
				renderKind: 'fileText',
				payload: {
					kind: 'codeViewFileItem',
					item: {
						file: {
							contents: 'refreshed body\n',
						},
					},
				},
			},
		});
		expect(postedMessages[9]?.message).toMatchObject({
			kind: 'slicePatch',
			epoch: 8,
			sequence: 86,
			patches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'file-1',
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'file-1',
					payload: { state: 'ready' },
				},
			],
		});
	});
});

const descriptorByUrl = new Map<string, { readonly text: string }>();

function createRecordingBridgeCommWorkerPort(): {
	readonly dispatch: {
		readonly message: (data: unknown) => void;
		readonly port: BridgeCommWorkerPort;
	};
	readonly postedMessages: PostedBridgeWorkerRuntimeMessage[];
} {
	const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
	let listener: ((event: MessageEvent<unknown>) => void) | null = null;
	return {
		dispatch: {
			message: (data: unknown): void => {
				if (listener === null) {
					throw new Error('Bridge comm worker port listener was not registered.');
				}
				listener(new MessageEvent('message', { data }));
			},
			port: {
				postMessage: (
					message: BridgeWorkerServerToMainMessage,
					transferList?: Transferable[],
				): void => {
					postedMessages.push({ message, transferList });
				},
				addEventListener: (
					type: 'message',
					nextListener: (event: MessageEvent<unknown>) => void,
				): void => {
					expect(type).toBe('message');
					listener = nextListener;
				},
				start: (): void => {},
			},
		},
		postedMessages,
	};
}

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

async function flushBridgeWorkerRuntimeContinuations(): Promise<void> {
	await Array.from({ length: 50 }).reduce<Promise<void>>(
		(previousFlush) => previousFlush.then(() => Promise.resolve()),
		Promise.resolve(),
	);
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

function makeWorkerFileViewContentMetadata(): BridgeWorkerFileViewContentMetadata {
	return {
		itemId: 'file-1',
		path: 'Sources/App/file-1.swift',
		language: 'swift',
		cacheKey: 'file-view:metadata-cache:file-1',
		sizeBytes: 128,
		contentHandle: 'handle-file-1',
		descriptorId: 'descriptor-file-1',
		contentHash: 'sha256:file-1',
		virtualizedExtentKind: 'exactLineCount',
		lineCount: 1,
		isBinary: false,
		canFetchContent: true,
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

function makeFileViewContentRequestDescriptor(
	props: string | { readonly generation: number; readonly text: string },
): BridgeWorkerFileViewContentRequestDescriptor {
	const text = typeof props === 'string' ? props : props.text;
	const generation = typeof props === 'string' ? 6 : props.generation;
	const descriptor: BridgeWorkerFileViewContentRequestDescriptor = {
		itemId: 'file-1',
		path: 'Sources/App/file-1.swift',
		handleId: 'handle-file-1',
		descriptorId: 'descriptor-file-1',
		resourceKind: 'worktree.fileContent',
		resourceUrl: `agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?cursor=cursor-file-1&generation=${generation}`,
		contentHash: 'sha256:file-1',
		contentHashAlgorithm: 'sha256',
		language: 'swift',
		sizeBytes: 128,
		maxBytes: 4096,
		isBinary: false,
	};
	descriptorByUrl.set(descriptor.resourceUrl, { text });
	return descriptor;
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
