import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import {
	bridgeWorkerServerToMainMessageSchema,
	type BridgeWorkerFileViewContentMetadata,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerFetchedFileViewContentResource } from './bridge-worker-file-view-content-fetch.js';
import {
	commitBridgeWorkerFileViewContentReadyRenderPatch,
	prepareBridgeWorkerFileViewContentRenderJobEvent,
} from './bridge-worker-file-view-content-ready.js';

describe('Bridge worker File View content ready', () => {
	test('prepares File View Pierre job events without publishing ready before courier acceptance', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerFileViewContentMetadata()],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});

		const result = prepareBridgeWorkerFileViewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			metadata: makeWorkerFileViewContentMetadata(),
			publicationSequence: 23,
			resource: makeFetchedFileViewContentResource({
				text: 'export const fileView = true;\n',
			}),
			workerDerivationEpoch: 17,
		});

		expect(result?.message).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'filePierreRenderJob',
			publicationSequence: 23,
			surface: 'file',
			workerDerivationEpoch: 17,
			job: {
				itemId: 'file-1',
				renderKind: 'fileText',
				contentCacheKey: 'file-view:metadata-cache:file-1',
				contentHash: 'sha256:file-1',
				payload: {
					kind: 'codeViewFileItem',
					item: {
						id: 'file:file-1',
						type: 'file',
						file: {
							name: 'Sources/App/FileView.swift',
							contents: 'export const fileView = true;\n',
							cacheKey: 'file-view:metadata-cache:file-1',
							lang: 'swift',
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
		expect(result?.message.transferDescriptors).toEqual([
			{
				messageKind: 'filePierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: result?.message.job.payloadByteLength,
				mode: 'clone',
			},
		]);
		expect(result?.transferList).toEqual([]);
		if (result === null) {
			throw new Error('Expected a File Pierre publication.');
		}
		expect(bridgeWorkerServerToMainMessageSchema.parse(result.message)).toEqual(result.message);
		for (const invalidPublication of [
			{ ...result.message, workerDerivationEpoch: undefined },
			{ ...result.message, publicationSequence: undefined },
			{ ...result.message, surface: 'fileView' },
			{ ...result.message, sourceId: 'must-not-repeat-source-identity' },
			{ ...result.message, job: { ...result.message.job, renderKind: 'reviewDiff' } },
		]) {
			expect(bridgeWorkerServerToMainMessageSchema.safeParse(invalidPublication).success).toBe(
				false,
			);
		}
		expect(store.getState().paintReadyByItemId.has('file-1')).toBe(false);
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 17, sequence: 24 })).toBeNull();
	});

	test('commits File View content-ready slice patches only after the render job is accepted', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerFileViewContentMetadata()],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});
		const preparedJobEvent = prepareBridgeWorkerFileViewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			metadata: makeWorkerFileViewContentMetadata(),
			publicationSequence: 23,
			resource: makeFetchedFileViewContentResource({
				text: 'export const fileView = true;\n',
			}),
			workerDerivationEpoch: 17,
		});
		if (preparedJobEvent === null) {
			throw new Error('Expected File View render job event.');
		}

		const result = commitBridgeWorkerFileViewContentReadyRenderPatch({
			preparedJobEvent,
			publicationSequence: 23,
			store,
			workerDerivationEpoch: 17,
		});

		expect(result.touchedKeys).toEqual([
			'byteCache:file-view:metadata-cache:file-1',
			'paintReady:file-1',
			'availability:file-1',
		]);
		expect(result.preparedMessage.message).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'fileRenderPatch',
			publicationSequence: 23,
			surface: 'file',
			transferDescriptors: [],
			workerDerivationEpoch: 17,
			patches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'file-1',
					payload: {
						contentCacheKey: 'file-view:metadata-cache:file-1',
					},
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'file-1',
					payload: { state: 'ready' },
				},
			],
		});
		expect(result.preparedMessage.transferList).toEqual([]);
		expect(bridgeWorkerServerToMainMessageSchema.parse(result.preparedMessage.message)).toEqual(
			result.preparedMessage.message,
		);
		for (const invalidPublication of [
			{ ...result.preparedMessage.message, workerDerivationEpoch: undefined },
			{ ...result.preparedMessage.message, publicationSequence: undefined },
			{ ...result.preparedMessage.message, surface: 'review' },
			{
				...result.preparedMessage.message,
				patches: [{ operation: 'reset', slice: 'selection' }],
			},
		]) {
			expect(bridgeWorkerServerToMainMessageSchema.safeParse(invalidPublication).success).toBe(
				false,
			);
		}
		expect(store.getState().paintReadyByItemId.get('file-1')).toBe(
			'file-view:metadata-cache:file-1',
		);
	});

	test('windows oversized File View text before preparing CodeView payloads', () => {
		const result = prepareBridgeWorkerFileViewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'visible', priority: 10 },
			budget: {
				className: 'visible',
				maxBytes: 512 * 1024,
				maxWindowLines: 2,
			},
			metadata: makeWorkerFileViewContentMetadata({
				payloadByteCount: 19,
				payloadLineCount: 4,
			}),
			publicationSequence: 23,
			resource: makeFetchedFileViewContentResource({
				text: 'one\ntwo\nthree\nfour\n',
			}),
			workerDerivationEpoch: 17,
		});

		expect(result?.message.job.window).toEqual({
			startLine: 1,
			endLine: 2,
			totalLineCount: 4,
		});
		expect(result?.message.job.payload).toMatchObject({
			kind: 'codeViewFileItem',
			item: {
				file: {
					contents: 'one\ntwo\n',
				},
				bridgeMetadata: {
					contentState: 'windowed',
					lineCount: 4,
				},
			},
		});
	});

	test('publishes only truthful File View prefix bytes without synthetic height padding', () => {
		const result = prepareBridgeWorkerFileViewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 2,
			},
			metadata: makeWorkerFileViewContentMetadata({
				payloadByteCount: 24,
				payloadLineCount: 5,
			}),
			publicationSequence: 23,
			resource: makeFetchedFileViewContentResource({
				text: 'one\ntwo\nthree\nfour\nfive\n',
			}),
			workerDerivationEpoch: 17,
		});

		expect(result?.message.job.payload.kind).toBe('codeViewFileItem');
		if (result?.message.job.payload.kind !== 'codeViewFileItem') {
			throw new Error('expected File View payload');
		}
		const contents = result.message.job.payload.item.file.contents;
		expect(contents).toContain('one\ntwo\n');
		expect(contents).not.toContain('three');
		expect(contents).toBe('one\ntwo\n');
		expect(renderedLineCountForText(contents)).toBe(2);
		expect(result.message.job.payload.item.bridgeMetadata).toMatchObject({
			contentState: 'windowed',
			lineCount: 5,
		});
	});

	test('keeps File View windowed payload byte budget bound to the rendered window', () => {
		const result = prepareBridgeWorkerFileViewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'visible', priority: 10 },
			budget: {
				className: 'visible',
				maxBytes: 64,
				maxWindowLines: 2,
			},
			metadata: makeWorkerFileViewContentMetadata({
				payloadByteCount: 24,
				payloadLineCount: 10_000,
			}),
			publicationSequence: 23,
			resource: makeFetchedFileViewContentResource({
				text: 'one\ntwo\nthree\nfour\nfive\n',
			}),
			workerDerivationEpoch: 17,
		});

		expect(result).not.toBeNull();
		expect(result?.message.job.window).toEqual({
			startLine: 1,
			endLine: 2,
			totalLineCount: 10_000,
		});
		expect(result?.message.job.payload.kind).toBe('codeViewFileItem');
		if (result?.message.job.payload.kind !== 'codeViewFileItem') {
			throw new Error('expected File View payload');
		}
		const contents = result.message.job.payload.item.file.contents;
		expect(new TextEncoder().encode(contents).byteLength).toBeLessThanOrEqual(64);
		expect(contents).toContain('one\ntwo\n');
		expect(contents).not.toContain('three');
		expect(result.message.job.payload.item.bridgeMetadata).toMatchObject({
			contentState: 'windowed',
			lineCount: 10_000,
		});
	});

	test('keeps a complete line-limited File prefix windowed instead of hydrated', () => {
		const text = `${Array.from({ length: 10_000 }, () => 'x').join('\n')}\n`;
		const payloadByteCount = new TextEncoder().encode(text).byteLength;
		const sourceByteCount = payloadByteCount + 100;
		const result = prepareBridgeWorkerFileViewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 10_000,
			},
			metadata: makeWorkerFileViewContentMetadata({
				payloadByteCount,
				payloadLineCount: 10_000,
				sizeBytes: sourceByteCount,
				totalLineCount: 12_000,
				truncationKind: 'lineLimit',
			}),
			publicationSequence: 23,
			resource: makeFetchedFileViewContentResource({ sizeBytes: sourceByteCount, text }),
			workerDerivationEpoch: 17,
		});

		expect(result?.message.job.window).toEqual({
			startLine: 1,
			endLine: 10_000,
			totalLineCount: 10_000,
		});
		expect(result?.message.job.payload).toMatchObject({
			kind: 'codeViewFileItem',
			item: { bridgeMetadata: { contentState: 'windowed', lineCount: 10_000 } },
		});
	});

	test('does not prepare ready jobs when File View content lacks a trustworthy hash', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerFileViewContentMetadata({ omitContentHash: true })],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});

		const result = prepareBridgeWorkerFileViewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			metadata: makeWorkerFileViewContentMetadata({ omitContentHash: true }),
			publicationSequence: 23,
			resource: makeFetchedFileViewContentResource({
				omitContentHash: true,
				text: 'hashless content must not fake identity\n',
			}),
			workerDerivationEpoch: 17,
		});

		expect(result).toBeNull();
		expect(store.getState().paintReadyByItemId.has('file-1')).toBe(false);
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 17, sequence: 24 })).toBeNull();
	});

	test('does not prepare ready jobs for non-fetchable File View metadata', () => {
		expectNoPreparedJobForMetadata(
			makeWorkerFileViewContentMetadata({
				canFetchContent: false,
				isBinary: false,
			}),
		);
	});

	test('does not prepare ready jobs for binary File View metadata', () => {
		expectNoPreparedJobForMetadata(
			makeWorkerFileViewContentMetadata({
				canFetchContent: true,
				isBinary: true,
			}),
		);
	});
});

function expectNoPreparedJobForMetadata(metadata: BridgeWorkerFileViewContentMetadata): void {
	const store = createBridgeCommWorkerStore({
		contentItems: [metadata],
		rows: [{ id: 'file-1', parentId: null, index: 0 }],
	});

	const result = prepareBridgeWorkerFileViewContentRenderJobEvent({
		bridgeDemandRank: { lane: 'selected', priority: 0 },
		budget: {
			className: 'interactive',
			maxBytes: 512 * 1024,
			maxWindowLines: 50,
		},
		metadata,
		publicationSequence: 23,
		resource: makeFetchedFileViewContentResource({
			text: 'blocked metadata must not become text payload\n',
		}),
		workerDerivationEpoch: 17,
	});

	expect(result).toBeNull();
	expect(store.getState().paintReadyByItemId.has('file-1')).toBe(false);
	expect(store.actions.takePendingSlicePatchEvent({ epoch: 17, sequence: 24 })).toBeNull();
}

function makeWorkerFileViewContentMetadata(
	props: {
		readonly canFetchContent?: boolean;
		readonly contentHash?: string | undefined;
		readonly isBinary?: boolean;
		readonly omitContentHash?: boolean;
		readonly payloadByteCount?: number;
		readonly payloadLineCount?: number;
		readonly sizeBytes?: number;
		readonly totalLineCount?: number | null;
		readonly truncationKind?: 'none' | 'byteLimit' | 'lineLimit' | 'both';
	} = {},
): BridgeWorkerFileViewContentMetadata {
	const contentHash = props.contentHash ?? 'sha256:file-1';
	const payloadByteCount = props.payloadByteCount ?? 30;
	const payloadLineCount = props.payloadLineCount ?? 1;
	return {
		metadataKind: 'fileView',
		itemId: 'file-1',
		path: 'Sources/App/FileView.swift',
		language: 'swift',
		cacheKey:
			props.omitContentHash === true
				? 'file-view:metadata-cache:unknown-file-1'
				: 'file-view:metadata-cache:file-1',
		sizeBytes: props.sizeBytes ?? payloadByteCount,
		descriptorId: 'descriptor-file-1',
		...(props.omitContentHash === true ? {} : { contentHash }),
		encoding: props.isBinary === true ? null : 'utf-8',
		endsMidLine: false,
		endsWithNewline: true,
		virtualizedExtentKind: 'exactLineCount',
		payloadByteCount,
		payloadLineCount,
		totalLineCount: props.totalLineCount === undefined ? payloadLineCount : props.totalLineCount,
		truncationKind: props.truncationKind ?? 'none',
		isBinary: props.isBinary ?? false,
		canFetchContent: props.canFetchContent ?? true,
	};
}

function makeFetchedFileViewContentResource(props: {
	readonly contentHash?: string | undefined;
	readonly contentHashAlgorithm?: string | undefined;
	readonly omitContentHash?: boolean;
	readonly sizeBytes?: number;
	readonly text: string;
}): BridgeWorkerFetchedFileViewContentResource {
	const contentHash = props.contentHash ?? 'sha256:file-1';
	const textBytes = new TextEncoder().encode(props.text).buffer;
	return {
		itemId: 'file-1',
		path: 'Sources/App/FileView.swift',
		descriptorId: 'descriptor-file-1',
		resourceKind: 'file.content',
		contentHash,
		contentHashAlgorithm: 'sha256',
		language: 'swift',
		sizeBytes: props.sizeBytes ?? textBytes.byteLength,
		maxBytes: 4096,
		byteLength: textBytes.byteLength,
		text: props.text,
		textBytes,
	};
}

function renderedLineCountForText(text: string): number {
	if (text.length === 0) {
		return 0;
	}
	return (text.match(/\n/gu)?.length ?? 0) + (text.endsWith('\n') ? 0 : 1);
}
