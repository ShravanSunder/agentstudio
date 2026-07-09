import { describe, expect, test } from 'vitest';

import { bridgeWorkerPierreRenderPolicy } from '../demand/bridge-content-demand-policy.js';
import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import { dispatchSelectedBridgeWorkerFileViewContentReady } from './bridge-comm-worker-file-view-runtime.js';
import {
	createBridgeCommWorkerStore,
	type BridgeCommWorkerStore,
} from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerFileViewContentRequestDescriptor,
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

interface PostedBridgeWorkerRuntimeMessage {
	readonly message: BridgeWorkerServerToMainMessage;
	readonly transferList: readonly Transferable[] | undefined;
}

describe('Bridge comm worker File View runtime', () => {
	test('selected File View dispatch posts prepared Pierre job before content-ready slice patch', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
		const fetchCalls: string[] = [];
		const store = createSelectedFileViewRuntimeStore();
		store.actions.applySelectedFact({ epoch: 7, itemId: 'file-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		await dispatchSelectedBridgeWorkerFileViewContentReady({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentRequestDescriptors: [makeContentRequestDescriptor('file body\n')],
			epoch: 7,
			fetchContent: async (url: string): Promise<Response> => {
				fetchCalls.push(url);
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected File View content URL ${url}.`);
				}
				return new Response(descriptor.text);
			},
			itemId: 'file-1',
			port: makePostedMessagePort(postedMessages),
			sequence: 12,
			store,
		});

		expect(fetchCalls).toEqual([
			'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?cursor=cursor-file-1&generation=7',
		]);
		expect(postedMessages.map((postedMessage) => postedMessage.message.kind)).toEqual([
			'pierreRenderJob',
			'slicePatch',
		]);
		expect(postedMessages[0]?.message).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'pierreRenderJob',
			job: {
				itemId: 'file-1',
				renderKind: 'fileText',
				contentCacheKey: 'file-view:metadata-cache:file-1',
				payload: {
					kind: 'codeViewFileItem',
					item: {
						id: 'file:file-1',
						file: {
							name: 'Sources/App/FileView.swift',
							contents: 'file body\n',
							cacheKey: 'file-view:metadata-cache:file-1',
						},
						bridgeMetadata: {
							itemId: 'file-1',
							displayPath: 'Sources/App/FileView.swift',
							contentRoles: ['file'],
							contentState: 'hydrated',
							cacheKey: 'file-view:metadata-cache:file-1',
							lineCount: 1,
						},
					},
				},
			},
		});
		const pierreJobMessage = postedMessages[0]?.message;
		if (pierreJobMessage?.kind !== 'pierreRenderJob') {
			throw new Error('Expected File View Pierre render job message first.');
		}
		expect(pierreJobMessage.transferDescriptors).toEqual([
			{
				messageKind: 'pierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: pierreJobMessage.job.payloadByteLength,
				mode: 'clone',
			},
		]);
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

	test('publishes the full selected File View safety window inside 2 MiB and 10k lines', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
		const longFileText = makeNumberedFileText(450);
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerFileViewContentMetadata('file-1', { lineCount: 450 })],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});
		store.actions.applySelectedFact({ epoch: 7, itemId: 'file-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		await dispatchSelectedBridgeWorkerFileViewContentReady({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: bridgeWorkerPierreRenderPolicy.fileViewSelectedRenderBudget,
			contentRequestDescriptors: [makeContentRequestDescriptor(longFileText)],
			epoch: 7,
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected File View content URL ${url}.`);
				}
				return new Response(descriptor.text);
			},
			itemId: 'file-1',
			port: makePostedMessagePort(postedMessages),
			sequence: 12,
			store,
		});

		expect(postedMessages.map((postedMessage) => postedMessage.message.kind).slice(0, 2)).toEqual([
			'pierreRenderJob',
			'slicePatch',
		]);
		const pierreJobMessage = postedMessages.find(
			(postedMessage) => postedMessage.message.kind === 'pierreRenderJob',
		)?.message;
		if (pierreJobMessage?.kind !== 'pierreRenderJob') {
			throw new Error('Expected selected long File View content to publish a Pierre job.');
		}
		expect(pierreJobMessage.job.window).toEqual({
			startLine: 1,
			endLine: 450,
			totalLineCount: 450,
		});
		expect(pierreJobMessage.job.budget).toMatchObject({
			maxBytes: 2 * 1024 * 1024,
			maxWindowLines: 10_000,
		});
		expect(pierreJobMessage.job.windowLineCount).toBe(450);
		expect(pierreJobMessage.job.payload.kind).toBe('codeViewFileItem');
		if (pierreJobMessage.job.payload.kind !== 'codeViewFileItem') {
			throw new Error('Expected selected long File View content to publish a File View payload.');
		}
		const contents = pierreJobMessage.job.payload.item.file.contents;
		expect(contents).toContain('line-450');
		expect(pierreJobMessage.job.payload.item.bridgeMetadata).toMatchObject({
			contentState: 'hydrated',
			lineCount: 450,
		});
	});

	test('publishes selected File View content above the old 512KiB ceiling inside the 2MiB window', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
		const denseFileText = makeDenseNumberedFileText({ lineCount: 6_000, linePayloadLength: 90 });
		const denseFileByteLength = new TextEncoder().encode(denseFileText).byteLength;
		expect(denseFileByteLength).toBeGreaterThan(512 * 1024);
		expect(denseFileByteLength).toBeLessThan(2 * 1024 * 1024);
		const store = createBridgeCommWorkerStore({
			contentItems: [
				makeWorkerFileViewContentMetadata('file-1', {
					lineCount: 6_000,
					sizeBytes: denseFileByteLength,
				}),
			],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});
		store.actions.applySelectedFact({ epoch: 7, itemId: 'file-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		await dispatchSelectedBridgeWorkerFileViewContentReady({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: bridgeWorkerPierreRenderPolicy.fileViewSelectedRenderBudget,
			contentRequestDescriptors: [
				makeContentRequestDescriptor(denseFileText, {
					maxBytes: bridgeWorkerPierreRenderPolicy.fileViewSelectedRenderBudget.maxBytes,
					sizeBytes: denseFileByteLength,
				}),
			],
			epoch: 7,
			fetchContent: async (url: string): Promise<Response> => {
				const descriptor = descriptorByUrl.get(url);
				if (descriptor === undefined) {
					throw new Error(`Unexpected File View content URL ${url}.`);
				}
				return new Response(descriptor.text);
			},
			itemId: 'file-1',
			port: makePostedMessagePort(postedMessages),
			sequence: 12,
			store,
		});

		const pierreJobMessage = postedMessages.find(
			(postedMessage) => postedMessage.message.kind === 'pierreRenderJob',
		)?.message;
		if (pierreJobMessage?.kind !== 'pierreRenderJob') {
			throw new Error('Expected selected dense File View content to publish a Pierre job.');
		}
		expect(pierreJobMessage.job.window).toEqual({
			startLine: 1,
			endLine: 6_000,
			totalLineCount: 6_000,
		});
		expect(pierreJobMessage.job.payloadByteLength).toBeGreaterThan(512 * 1024);
		expect(pierreJobMessage.job.payloadByteLength).toBeLessThanOrEqual(2 * 1024 * 1024);
		expect(pierreJobMessage.job.payload.kind).toBe('codeViewFileItem');
		if (pierreJobMessage.job.payload.kind !== 'codeViewFileItem') {
			throw new Error('Expected selected dense File View content to publish a File View payload.');
		}
		expect(pierreJobMessage.job.payload.item.file.contents).toContain('line-006000');
		expect(pierreJobMessage.job.payload.item.bridgeMetadata).toMatchObject({
			contentState: 'hydrated',
			lineCount: 6_000,
		});
	});

	test('publishes unavailable instead of leaving selected File View content loading when descriptor is absent', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
		const fetchCalls: string[] = [];
		const store = createSelectedFileViewRuntimeStore();
		store.actions.applySelectedFact({ epoch: 7, itemId: 'file-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		await dispatchSelectedBridgeWorkerFileViewContentReady({
			...makeDispatchProps({
				contentRequestDescriptors: [],
				fetchContent: async (url: string): Promise<Response> => {
					fetchCalls.push(url);
					return new Response('must not fetch');
				},
				postedMessages,
				store,
			}),
		});

		expect(fetchCalls).toEqual([]);
		expect(store.getState().availabilityByItemId.get('file-1')).toBe('unavailable');
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
							payload: { reason: 'descriptor_missing', state: 'unavailable' },
						},
					],
				},
				transferList: [],
			},
		]);
	});

	test('publishes unavailable instead of fetching when selected metadata is not File View content', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
		const fetchCalls: string[] = [];
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerReviewContentMetadata('file-1')],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});
		store.actions.applySelectedFact({ epoch: 7, itemId: 'file-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		await dispatchSelectedBridgeWorkerFileViewContentReady({
			...makeDispatchProps({
				contentRequestDescriptors: [makeContentRequestDescriptor('file body\n')],
				fetchContent: async (url: string): Promise<Response> => {
					fetchCalls.push(url);
					return new Response('must not fetch');
				},
				postedMessages,
				store,
			}),
		});

		expect(fetchCalls).toEqual([]);
		expect(store.getState().availabilityByItemId.get('file-1')).toBe('unavailable');
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
							payload: { reason: 'content_unavailable', state: 'unavailable' },
						},
					],
				},
				transferList: [],
			},
		]);
	});

	test('publishes failed instead of leaving selected File View content loading when fetch rejects', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
		const store = createSelectedFileViewRuntimeStore();
		store.actions.applySelectedFact({ epoch: 7, itemId: 'file-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		await dispatchSelectedBridgeWorkerFileViewContentReady({
			...makeDispatchProps({
				contentRequestDescriptors: [makeContentRequestDescriptor('file body\n')],
				fetchContent: async (): Promise<Response> => {
					throw new Error('simulated File View worker fetch failure');
				},
				postedMessages,
				store,
			}),
		});

		expect(store.getState().availabilityByItemId.get('file-1')).toBe('failed');
		expect(postedMessages).toHaveLength(1);
		expect(postedMessages[0]).toMatchObject({
			message: {
				kind: 'slicePatch',
				patches: [
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'file-1',
						payload: { reason: 'load_failed', state: 'failed' },
					},
				],
			},
			transferList: [],
		});
	});

	test('drops stale selected File View terminal dispatch before publishing content messages', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
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

		await dispatchSelectedBridgeWorkerFileViewContentReady({
			...makeDispatchProps({
				contentRequestDescriptors: [makeContentRequestDescriptor('file body\n')],
				fetchContent: async (): Promise<Response> => {
					store.actions.applySelectedFact({ epoch: 8, itemId: 'file-2' });
					throw new Error('simulated stale File View worker fetch failure');
				},
				postedMessages,
				store,
			}),
		});

		expect(postedMessages).toEqual([]);
		expect(store.getState().availabilityByItemId.get('file-1')).toBe('loading');
		expect(store.getState().availabilityByItemId.get('file-2')).toBe('loading');
	});

	test('publishes unavailable when fetched File View content cannot plan a render job', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerFileViewContentMetadata('file-1', { omitContentHash: true })],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});
		store.actions.applySelectedFact({ epoch: 7, itemId: 'file-1' });
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 11 });

		await dispatchSelectedBridgeWorkerFileViewContentReady({
			...makeDispatchProps({
				contentRequestDescriptors: [
					makeContentRequestDescriptor('hashless content cannot become ready\n', {
						omitContentHash: true,
					}),
				],
				fetchContent: async (url: string): Promise<Response> => {
					const descriptor = descriptorByUrl.get(url);
					if (descriptor === undefined) {
						throw new Error(`Unexpected File View content URL ${url}.`);
					}
					return new Response(descriptor.text);
				},
				postedMessages,
				store,
			}),
		});

		expect(store.getState().availabilityByItemId.get('file-1')).toBe('unavailable');
		expect(postedMessages).toHaveLength(1);
		expect(postedMessages[0]).toMatchObject({
			message: {
				kind: 'slicePatch',
				patches: [
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'file-1',
						payload: { reason: 'descriptor_rejected', state: 'unavailable' },
					},
				],
			},
			transferList: [],
		});
	});

	test('drops stale selected File View dispatch before publishing content messages', async () => {
		const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
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

		await dispatchSelectedBridgeWorkerFileViewContentReady({
			...makeDispatchProps({
				contentRequestDescriptors: [makeContentRequestDescriptor('file body\n')],
				fetchContent: async (url: string): Promise<Response> => {
					store.actions.applySelectedFact({ epoch: 8, itemId: 'file-2' });
					const descriptor = descriptorByUrl.get(url);
					if (descriptor === undefined) {
						throw new Error(`Unexpected File View content URL ${url}.`);
					}
					return new Response(descriptor.text);
				},
				postedMessages,
				store,
			}),
		});

		expect(postedMessages).toEqual([]);
	});
});

const descriptorByUrl = new Map<string, { readonly text: string }>();

type DispatchSelectedFileViewRuntimeProps = Parameters<
	typeof dispatchSelectedBridgeWorkerFileViewContentReady
>[0];

interface MakeDispatchPropsOptions {
	readonly contentRequestDescriptors: readonly BridgeWorkerFileViewContentRequestDescriptor[];
	readonly fetchContent?: (url: string) => Promise<Response>;
	readonly postedMessages: PostedBridgeWorkerRuntimeMessage[];
	readonly store: BridgeCommWorkerStore;
}

function makeDispatchProps(
	options: MakeDispatchPropsOptions,
): DispatchSelectedFileViewRuntimeProps {
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
		itemId: 'file-1',
		port: makePostedMessagePort(options.postedMessages),
		sequence: 12,
		store: options.store,
	};
}

function makePostedMessagePort(
	postedMessages: PostedBridgeWorkerRuntimeMessage[],
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

function createSelectedFileViewRuntimeStore(): BridgeCommWorkerStore {
	return createBridgeCommWorkerStore({
		contentItems: [makeWorkerFileViewContentMetadata('file-1')],
		rows: [{ id: 'file-1', parentId: null, index: 0 }],
	});
}

function makeWorkerFileViewContentMetadata(
	itemId: string,
	props: {
		readonly lineCount?: number;
		readonly omitContentHash?: boolean;
		readonly sizeBytes?: number;
	} = {},
): BridgeWorkerFileViewContentMetadata {
	return {
		itemId,
		path: 'Sources/App/FileView.swift',
		language: 'swift',
		cacheKey: `file-view:metadata-cache:${itemId}`,
		sizeBytes: props.sizeBytes ?? 128,
		contentHandle: `handle-${itemId}`,
		descriptorId: `descriptor-${itemId}`,
		...(props.omitContentHash === true ? {} : { contentHash: `sha256:${itemId}` }),
		virtualizedExtentKind: 'exactLineCount',
		lineCount: props.lineCount ?? 1,
		isBinary: false,
		canFetchContent: true,
	};
}

function makeWorkerReviewContentMetadata(itemId: string): BridgeWorkerReviewContentMetadata {
	return {
		itemId,
		path: 'Sources/App/FileView.swift',
		language: 'swift',
		cacheKey: `review:metadata-cache:${itemId}`,
		sizeBytes: 128,
		availableContentRoles: ['head'],
		contentLineCountsByRole: {
			base: null,
			head: 1,
			diff: null,
		},
	};
}

function makeContentRequestDescriptor(
	text: string,
	props: {
		readonly maxBytes?: number;
		readonly omitContentHash?: boolean;
		readonly sizeBytes?: number;
	} = {},
): BridgeWorkerFileViewContentRequestDescriptor {
	const descriptor: BridgeWorkerFileViewContentRequestDescriptor = {
		itemId: 'file-1',
		path: 'Sources/App/FileView.swift',
		handleId: 'handle-file-1',
		descriptorId: 'descriptor-file-1',
		resourceKind: 'worktree.fileContent',
		resourceUrl:
			'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?cursor=cursor-file-1&generation=7',
		...(props.omitContentHash === true
			? {}
			: { contentHash: 'sha256:file-1', contentHashAlgorithm: 'sha256' }),
		language: 'swift',
		sizeBytes: props.sizeBytes ?? 128,
		maxBytes: props.maxBytes ?? 4096,
		isBinary: false,
	};
	descriptorByUrl.set(descriptor.resourceUrl, { text });
	return descriptor;
}

function makeNumberedFileText(lineCount: number): string {
	return Array.from(
		{ length: lineCount },
		(_, lineIndex): string => `line-${String(lineIndex + 1).padStart(3, '0')}`,
	).join('\n');
}

function makeDenseNumberedFileText(props: {
	readonly lineCount: number;
	readonly linePayloadLength: number;
}): string {
	const payload = 'x'.repeat(props.linePayloadLength);
	return Array.from(
		{ length: props.lineCount },
		(_, lineIndex): string => `line-${String(lineIndex + 1).padStart(6, '0')} ${payload}`,
	).join('\n');
}
