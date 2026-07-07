import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type { BridgeWorkerFileViewContentMetadata } from './bridge-worker-contracts.js';
import type { BridgeWorkerFetchedFileViewContentResource } from './bridge-worker-file-view-content-fetch.js';
import {
	commitBridgeWorkerFileViewContentReadySlicePatch,
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
			resource: makeFetchedFileViewContentResource({
				text: 'export const fileView = true;\n',
			}),
		});

		expect(result?.message).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'pierreRenderJob',
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
							lineCount: 2,
						},
					},
				},
			},
		});
		expect(result?.message.transferDescriptors).toEqual([
			{
				messageKind: 'pierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: result?.message.job.payloadByteLength,
				mode: 'clone',
			},
		]);
		expect(result?.transferList).toEqual([]);
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
			resource: makeFetchedFileViewContentResource({
				text: 'export const fileView = true;\n',
			}),
		});
		if (preparedJobEvent === null) {
			throw new Error('Expected File View render job event.');
		}

		const result = commitBridgeWorkerFileViewContentReadySlicePatch({
			epoch: 17,
			preparedJobEvent,
			sequence: 23,
			store,
		});

		expect(result.touchedKeys).toEqual([
			'byteCache:file-view:metadata-cache:file-1',
			'paintReady:file-1',
			'availability:file-1',
		]);
		expect(result.preparedMessage.message).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'slicePatch',
			epoch: 17,
			sequence: 23,
			transferDescriptors: [],
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
			metadata: makeWorkerFileViewContentMetadata({ lineCount: 4 }),
			resource: makeFetchedFileViewContentResource({
				text: 'one\ntwo\nthree\nfour\n',
			}),
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
					contents: 'one\ntwo\n\n ',
				},
				bridgeMetadata: {
					contentState: 'windowed',
					lineCount: 4,
				},
			},
		});
	});

	test('reserves File View windowed render height without including text beyond the window', () => {
		const result = prepareBridgeWorkerFileViewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 2,
			},
			metadata: makeWorkerFileViewContentMetadata({ lineCount: 5 }),
			resource: makeFetchedFileViewContentResource({
				text: 'one\ntwo\nthree\nfour\nfive\n',
			}),
		});

		expect(result?.message.job.payload.kind).toBe('codeViewFileItem');
		if (result?.message.job.payload.kind !== 'codeViewFileItem') {
			throw new Error('expected File View payload');
		}
		const contents = result.message.job.payload.item.file.contents;
		expect(contents).toContain('one\ntwo\n');
		expect(contents).not.toContain('three');
		expect(renderedLineCountForText(contents)).toBe(5);
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
			metadata: makeWorkerFileViewContentMetadata({ lineCount: 100_000 }),
			resource: makeFetchedFileViewContentResource({
				text: 'one\ntwo\nthree\nfour\nfive\n',
			}),
		});

		expect(result).not.toBeNull();
		expect(result?.message.job.window).toEqual({
			startLine: 1,
			endLine: 2,
			totalLineCount: 100_000,
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
			lineCount: 100_000,
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
			resource: makeFetchedFileViewContentResource({
				omitContentHash: true,
				text: 'hashless content must not fake identity\n',
			}),
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
		resource: makeFetchedFileViewContentResource({
			text: 'blocked metadata must not become text payload\n',
		}),
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
		readonly lineCount?: number;
		readonly omitContentHash?: boolean;
	} = {},
): BridgeWorkerFileViewContentMetadata {
	const contentHash = props.contentHash ?? 'sha256:file-1';
	return {
		itemId: 'file-1',
		path: 'Sources/App/FileView.swift',
		language: 'swift',
		cacheKey:
			props.omitContentHash === true
				? 'file-view:metadata-cache:unknown-file-1'
				: 'file-view:metadata-cache:file-1',
		sizeBytes: 128,
		contentHandle: 'handle-file-1',
		descriptorId: 'descriptor-file-1',
		...(props.omitContentHash === true ? {} : { contentHash }),
		virtualizedExtentKind: 'exactLineCount',
		lineCount: props.lineCount ?? 2,
		isBinary: props.isBinary ?? false,
		canFetchContent: props.canFetchContent ?? true,
	};
}

function makeFetchedFileViewContentResource(props: {
	readonly contentHash?: string | undefined;
	readonly contentHashAlgorithm?: string | undefined;
	readonly omitContentHash?: boolean;
	readonly text: string;
}): BridgeWorkerFetchedFileViewContentResource {
	const contentHash = props.contentHash ?? 'sha256:file-1';
	const contentHashAlgorithm = props.contentHashAlgorithm ?? 'sha256';
	const textBytes = new TextEncoder().encode(props.text).buffer;
	return {
		itemId: 'file-1',
		path: 'Sources/App/FileView.swift',
		handleId: 'handle-file-1',
		descriptorId: 'descriptor-file-1',
		resourceKind: 'worktree.fileContent',
		...(props.omitContentHash === true ? {} : { contentHash, contentHashAlgorithm }),
		language: 'swift',
		sizeBytes: 128,
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
	return (text.match(/\n/gu)?.length ?? 0) + 1;
}
