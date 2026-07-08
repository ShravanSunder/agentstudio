import { describe, expect, test } from 'vitest';

import { createBridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgeWorkerMainToServerMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerCodeViewFileItem } from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import {
	makeFileDescriptor,
	makeTreeRowFromDescriptor,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore,
	bridgeFileViewerMinimumSelectedSlicePatchEpoch,
	bridgeCommWorkerContentItemsFromFileViewRenderState,
	bridgeCommWorkerContentRequestDescriptorsFromFileViewRenderState,
	bridgeCommWorkerRowsFromFileViewRenderState,
	createBridgeFileViewerRuntimeProtocolDispatcher,
	publishBridgeFileViewerLoadingStateToSnapshotStore,
	publishBridgeFileViewerRefreshingStateToSnapshotStore,
	publishBridgeFileViewerSelectedCodeViewItemToSnapshotStore,
	selectedBridgeFileViewerCodeViewItemForSnapshot,
} from './bridge-file-viewer-render-snapshot-controller.js';
import type { BridgeFileViewerRenderState } from './bridge-file-viewer-state.js';

describe('Bridge File Viewer render snapshot controller', () => {
	test('builds typed File View source update payloads for the comm worker', () => {
		const descriptor = {
			...makeFileDescriptor({
				contentHandle: 'content-worker',
				fileId: 'file-worker',
				lineCount: 4,
				path: 'Sources/Worker.ts',
			}),
			contentHash: 'hash-worker',
		};
		const renderState = {
			descriptors: [descriptor],
			provenance: null,
			sourceIdentity: descriptor.sourceIdentity,
			treeRows: [makeTreeRowFromDescriptor(descriptor)],
			treeSizeFacts: null,
		} satisfies BridgeFileViewerRenderState;

		expect(bridgeCommWorkerContentItemsFromFileViewRenderState(renderState)).toEqual([
			expect.objectContaining({
				itemId: descriptor.fileId,
				path: descriptor.path,
				cacheKey: `${descriptor.contentHandle}:${descriptor.contentHash}`,
				contentHash: descriptor.contentHash,
				contentHandle: descriptor.contentHandle,
				descriptorId: descriptor.contentDescriptor.ref.descriptorId,
				canFetchContent: true,
			}),
		]);
		expect(bridgeCommWorkerContentRequestDescriptorsFromFileViewRenderState(renderState)).toEqual([
			expect.objectContaining({
				itemId: descriptor.fileId,
				path: descriptor.path,
				handleId: descriptor.contentHandle,
				descriptorId: descriptor.contentDescriptor.ref.descriptorId,
				resourceKind: 'worktree.fileContent',
				resourceUrl:
					'agentstudio://resource/worktree-file/worktree.fileContent/content-worker?cursor=cursor-1&generation=1',
				contentHash: descriptor.contentHash,
			}),
		]);
		expect(bridgeCommWorkerRowsFromFileViewRenderState(renderState)).toEqual([
			{
				id: descriptor.fileId,
				parentId: null,
				index: 0,
			},
		]);
	});

	test('dispatches selected File View commands through the worker transport seam', () => {
		const dispatchedMessages: BridgeWorkerMainToServerMessage[] = [];
		let receivedBootstrapRequestId: string | null = null;
		const runtimeDispatcher = createBridgeFileViewerRuntimeProtocolDispatcher({
			bootstrapRequestId: 'bootstrap-file-view-runtime',
			publishWorkerMessages: (): void => {},
			transportFactory: (props) => {
				receivedBootstrapRequestId = props.bootstrapRequest.requestId;
				return {
					dispatch: (message: BridgeWorkerMainToServerMessage): void => {
						dispatchedMessages.push(message);
					},
					dispose: (): void => {},
				};
			},
		});

		runtimeDispatcher.dispatchSelectedFileViewContentRequest({
			epoch: 5,
			requestId: 'request-file-select',
			selectedItemId: 'file-selected',
			selectedSource: 'user',
		});

		expect(receivedBootstrapRequestId).toBe('bootstrap-file-view-runtime');
		expect(dispatchedMessages).toEqual([
			expect.objectContaining({
				kind: 'command',
				command: 'select',
				requestId: 'request-file-select',
				selectedItemId: 'file-selected',
			}),
		]);
		runtimeDispatcher.dispose();
	});

	test('applies worker File View Pierre render jobs without main raw body synthesis', () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'content-worker-ready',
			fileId: 'file-worker-ready',
			path: 'Sources/WorkerReady.ts',
		});
		const store = createBridgeMainRenderSnapshotStore();
		const workerItem = makeSelectedFileCodeViewItem({
			cacheKey: 'content-worker-ready:hash-worker-ready',
			contents: 'export const workerReady = true;\n',
			displayPath: descriptor.path,
			itemId: descriptor.fileId,
			lineCount: 1,
		});

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'pierreRenderJob',
					job: {
						itemId: descriptor.fileId,
						renderKind: 'fileText',
						contentCacheKey: workerItem.bridgeMetadata.cacheKey,
						contentHash: 'hash-worker-ready',
						language: 'typescript',
						bridgeDemandRank: { lane: 'selected', priority: 0 },
						window: { startLine: 1, endLine: 1, totalLineCount: 1 },
						windowLineCount: 1,
						payload: { kind: 'codeViewFileItem', item: workerItem },
						payloadByteLength: 256,
						budgetClass: 'interactive',
						budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
					},
				},
			],
			renderSnapshotStore: store,
		});

		expect(store.getSnapshot().codeViewItemsById[descriptor.fileId]).toEqual(workerItem);
		expect(JSON.stringify(store.getSnapshot())).not.toMatch(/readText|openFileBody|rawBody/u);
	});

	test('file view receives selected CodeView display from shared worker snapshot state', () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'content-selected',
			fileId: 'file-selected',
			lineCount: 2,
			path: 'Sources/Selected.swift',
		});
		const store = createBridgeMainRenderSnapshotStore();
		const selectedCodeViewItem = makeSelectedFileCodeViewItem({
			cacheKey: 'content-selected:sha256:content-selected',
			contents: 'struct Selected {}\n',
			displayPath: descriptor.path,
			itemId: descriptor.fileId,
			lineCount: 2,
		});

		publishBridgeFileViewerSelectedCodeViewItemToSnapshotStore({
			item: selectedCodeViewItem,
			renderSnapshotStore: store,
			source: 'programmatic',
		});

		expect(
			selectedBridgeFileViewerCodeViewItemForSnapshot({
				openFileState: {
					status: 'ready',
					descriptor,
					path: descriptor.path,
				},
				renderSnapshot: store.getSnapshot(),
			}),
		).toBe(selectedCodeViewItem);
		expect(JSON.stringify(store.getSnapshot())).not.toMatch(
			/openFileBody|rawBody|readText|retryAfterVersion|sourceGeneration|sequence/u,
		);
	});

	test('file view can publish provisional selected CodeView display without mutating worker availability', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const provisionalCodeViewItem = makeSelectedFileCodeViewItem({
			cacheKey: 'content-loading:hash-loading',
			contents: 'struct Loading',
			displayPath: 'Sources/Loading.swift',
			itemId: 'file-loading',
			lineCount: 1,
		});

		publishBridgeFileViewerSelectedCodeViewItemToSnapshotStore({
			item: provisionalCodeViewItem,
			renderSnapshotStore: store,
			source: 'programmatic',
		});

		expect(store.getSnapshot().codeViewItemsById['file-loading']).toBe(provisionalCodeViewItem);
		expect(store.getSnapshot().contentAvailabilityById['file-loading']).toBeUndefined();
	});

	test('file view local request helpers reset availability to loading before worker patches', () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'content-worker-owned',
			fileId: 'file-worker-owned',
			path: 'Sources/WorkerOwned.swift',
		});
		const store = createBridgeMainRenderSnapshotStore();

		publishBridgeFileViewerLoadingStateToSnapshotStore({
			descriptor,
			renderSnapshotStore: store,
		});
		publishBridgeFileViewerRefreshingStateToSnapshotStore({
			descriptor,
			renderSnapshotStore: store,
		});
		publishBridgeFileViewerSelectedCodeViewItemToSnapshotStore({
			item: makeSelectedFileCodeViewItem({
				cacheKey: 'content-worker-owned:sha256:content-worker-owned',
				contents: 'struct WorkerOwned {}\n',
				displayPath: descriptor.path,
				itemId: descriptor.fileId,
				lineCount: 1,
			}),
			renderSnapshotStore: store,
			source: 'programmatic',
		});

		expect(store.getSnapshot().selectionSlice).toEqual({
			selectedItemId: descriptor.fileId,
			source: 'programmatic',
		});
		expect(store.getSnapshot().codeViewItemsById[descriptor.fileId]).toBeDefined();
		expect(store.getSnapshot().contentAvailabilityById[descriptor.fileId]).toEqual({
			state: 'loading',
		});

		store.applyWorkerPatch({
			slice: 'contentAvailability',
			operation: 'upsert',
			itemId: descriptor.fileId,
			payload: { state: 'ready' },
		});

		expect(store.getSnapshot().contentAvailabilityById[descriptor.fileId]).toEqual({
			state: 'ready',
		});
	});

	test('file view ignores stale worker slice patches older than the active selected request', () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'content-worker-epoch',
			fileId: 'file-worker-epoch',
			path: 'Sources/WorkerEpoch.swift',
		});
		const store = createBridgeMainRenderSnapshotStore();

		publishBridgeFileViewerLoadingStateToSnapshotStore({
			descriptor,
			renderSnapshotStore: store,
		});
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			minimumAcceptedSlicePatchEpoch: 4,
			messages: [
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'slicePatch',
					epoch: 3,
					sequence: 12,
					patches: [
						{
							slice: 'contentAvailability',
							operation: 'upsert',
							itemId: descriptor.fileId,
							payload: { state: 'failed' },
						},
					],
				},
			],
			renderSnapshotStore: store,
		});

		expect(store.getSnapshot().contentAvailabilityById[descriptor.fileId]).toEqual({
			state: 'loading',
		});
	});

	test('file view accepts same-turn source update repairs before the selected epoch', () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'content-worker-source-repair',
			fileId: 'file-worker-source-repair',
			path: 'Sources/WorkerSourceRepair.swift',
		});
		const store = createBridgeMainRenderSnapshotStore();
		publishBridgeFileViewerSelectedCodeViewItemToSnapshotStore({
			item: makeSelectedFileCodeViewItem({
				cacheKey: 'content-worker-source-repair:hash-source-repair',
				contents: 'struct SourceRepair {}\n',
				displayPath: descriptor.path,
				itemId: descriptor.fileId,
				lineCount: 1,
			}),
			renderSnapshotStore: store,
			source: 'programmatic',
		});

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			minimumAcceptedSlicePatchEpoch: bridgeFileViewerMinimumSelectedSlicePatchEpoch({
				selectedEpoch: 6,
				synchronizedSourceUpdateEpoch: 5,
			}),
			messages: [
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'slicePatch',
					epoch: 5,
					sequence: 14,
					patches: [
						{
							slice: 'contentAvailability',
							operation: 'upsert',
							itemId: descriptor.fileId,
							payload: { state: 'stale' },
						},
					],
				},
			],
			renderSnapshotStore: store,
		});

		expect(store.getSnapshot().contentAvailabilityById[descriptor.fileId]).toEqual({
			state: 'stale',
		});
	});

	test('file view applies a worker slice-patch message as one render snapshot publish', () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'content-worker-batch',
			fileId: 'file-worker-batch',
			path: 'Sources/WorkerBatch.swift',
		});
		const store = createBridgeMainRenderSnapshotStore();
		let publishCount = 0;
		const unsubscribe = store.subscribe(() => {
			publishCount += 1;
		});

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'slicePatch',
					epoch: 5,
					sequence: 15,
					patches: [
						{
							slice: 'rowPaint',
							operation: 'upsert',
							itemId: descriptor.fileId,
							payload: {
								contentCacheKey: 'content-worker-batch:hash-worker-batch',
								status: 'ready',
							},
						},
						{
							slice: 'contentAvailability',
							operation: 'upsert',
							itemId: descriptor.fileId,
							payload: { state: 'ready' },
						},
					],
				},
			],
			renderSnapshotStore: store,
		});

		expect(publishCount).toBe(1);
		expect(store.getSnapshot().rowPaintById[descriptor.fileId]).toEqual({
			contentCacheKey: 'content-worker-batch:hash-worker-batch',
			status: 'ready',
		});
		expect(store.getSnapshot().contentAvailabilityById[descriptor.fileId]).toEqual({
			state: 'ready',
		});

		unsubscribe();
	});

	test('degraded worker health fails the selected File View request', () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'content-worker-degraded',
			fileId: 'file-worker-degraded',
			path: 'Sources/WorkerDegraded.swift',
		});
		const store = createBridgeMainRenderSnapshotStore();

		publishBridgeFileViewerLoadingStateToSnapshotStore({
			descriptor,
			renderSnapshotStore: store,
		});
		store.setWorkerCodeViewItem({
			itemId: descriptor.fileId,
			item: makeSelectedFileCodeViewItem({
				cacheKey: 'content-worker-degraded:sha256:content-worker-degraded',
				contents: 'struct WorkerDegraded {}\n',
				displayPath: descriptor.path,
				itemId: descriptor.fileId,
				lineCount: 1,
			}),
		});
		store.applyWorkerPatch({
			slice: 'rowPaint',
			operation: 'upsert',
			itemId: descriptor.fileId,
			payload: {
				contentCacheKey: 'content-worker-degraded:sha256:content-worker-degraded',
				status: 'ready',
			},
		});
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'health',
					requestId: 'request-degraded-worker',
					status: 'degraded',
					message: 'worker startup failed',
				},
			],
			renderSnapshotStore: store,
		});

		expect(store.getSnapshot().contentAvailabilityById[descriptor.fileId]).toEqual({
			state: 'failed',
		});
		expect(store.getSnapshot().rowPaintById[descriptor.fileId]).toBeUndefined();
		expect(store.getSnapshot().codeViewItemsById[descriptor.fileId]).toBeUndefined();
	});

	test('file view clears same-descriptor cached body while a fresh open request is loading', () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'content-reopen',
			fileId: 'file-reopen',
			path: 'Sources/Reopen.swift',
		});
		const store = createBridgeMainRenderSnapshotStore();

		publishBridgeFileViewerSelectedCodeViewItemToSnapshotStore({
			item: makeSelectedFileCodeViewItem({
				cacheKey: 'content-reopen:hash-reopen',
				contents: 'struct OldReopen {}\n',
				displayPath: descriptor.path,
				itemId: descriptor.fileId,
				lineCount: 1,
			}),
			renderSnapshotStore: store,
			source: 'programmatic',
		});

		publishBridgeFileViewerLoadingStateToSnapshotStore({
			descriptor,
			renderSnapshotStore: store,
		});

		expect(store.getSnapshot().codeViewItemsById[descriptor.fileId]).toBeUndefined();
		expect(
			selectedBridgeFileViewerCodeViewItemForSnapshot({
				openFileState: {
					status: 'loading',
					descriptor,
					path: descriptor.path,
				},
				renderSnapshot: store.getSnapshot(),
			}),
		).toBeNull();
	});

	test('file view retains same-descriptor cached body while a refresh request is loading', () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'content-refresh',
			fileId: 'file-refresh',
			path: 'Sources/Refresh.swift',
		});
		const store = createBridgeMainRenderSnapshotStore();
		const selectedCodeViewItem = makeSelectedFileCodeViewItem({
			cacheKey: 'content-refresh:hash-refresh',
			contents: 'struct OldRefresh {}\n',
			displayPath: descriptor.path,
			itemId: descriptor.fileId,
			lineCount: 1,
		});

		publishBridgeFileViewerSelectedCodeViewItemToSnapshotStore({
			item: selectedCodeViewItem,
			renderSnapshotStore: store,
			source: 'programmatic',
		});

		publishBridgeFileViewerRefreshingStateToSnapshotStore({
			descriptor,
			renderSnapshotStore: store,
		});

		expect(store.getSnapshot().codeViewItemsById[descriptor.fileId]).toBe(selectedCodeViewItem);
		expect(
			selectedBridgeFileViewerCodeViewItemForSnapshot({
				openFileState: {
					status: 'refreshing',
					descriptor,
					path: descriptor.path,
				},
				renderSnapshot: store.getSnapshot(),
			}),
		).toBe(selectedCodeViewItem);
	});

	test('file view publishes selected display state in one snapshot notification', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const selectedCodeViewItem = makeSelectedFileCodeViewItem({
			cacheKey: 'content-batched:hash-batched',
			contents: 'struct Batched {}\n',
			displayPath: 'Sources/Batched.swift',
			itemId: 'file-batched',
			lineCount: 1,
		});
		let publishCount = 0;
		const unsubscribe = store.subscribe(() => {
			publishCount += 1;
		});

		publishBridgeFileViewerSelectedCodeViewItemToSnapshotStore({
			item: selectedCodeViewItem,
			renderSnapshotStore: store,
			source: 'programmatic',
		});

		expect(publishCount).toBe(1);
		unsubscribe();
	});

	test('file view ignores stale selected CodeView items from an old selected file', () => {
		const currentDescriptor = makeFileDescriptor({
			contentHandle: 'content-current',
			fileId: 'file-current',
			path: 'Sources/Current.swift',
		});
		const store = createBridgeMainRenderSnapshotStore();

		publishBridgeFileViewerSelectedCodeViewItemToSnapshotStore({
			item: makeSelectedFileCodeViewItem({
				cacheKey: 'content-stale:hash-stale',
				contents: 'struct Stale {}\n',
				displayPath: 'Sources/Stale.swift',
				itemId: 'file-stale',
				lineCount: 1,
			}),
			renderSnapshotStore: store,
			source: 'programmatic',
		});
		store.setLocalSelection({
			selectedItemId: currentDescriptor.fileId,
			source: 'user',
		});

		expect(
			selectedBridgeFileViewerCodeViewItemForSnapshot({
				openFileState: {
					status: 'loading',
					descriptor: currentDescriptor,
					path: currentDescriptor.path,
				},
				renderSnapshot: store.getSnapshot(),
			}),
		).toBeNull();
	});

	test('file view retains same-file content while a replacement descriptor refreshes', () => {
		const initialDescriptor = makeFileDescriptor({
			contentHandle: 'content-initial',
			fileId: 'file-same',
			path: 'Sources/Same.swift',
		});
		const replacementDescriptor = makeFileDescriptor({
			contentHandle: 'content-replacement',
			fileId: initialDescriptor.fileId,
			path: initialDescriptor.path,
		});
		const store = createBridgeMainRenderSnapshotStore();
		const selectedCodeViewItem = makeSelectedFileCodeViewItem({
			cacheKey: 'content-initial:hash-initial',
			contents: 'struct Same {}\n',
			displayPath: initialDescriptor.path,
			itemId: initialDescriptor.fileId,
			lineCount: 1,
		});

		publishBridgeFileViewerSelectedCodeViewItemToSnapshotStore({
			item: selectedCodeViewItem,
			renderSnapshotStore: store,
			source: 'programmatic',
		});
		store.setLocalSelection({
			selectedItemId: replacementDescriptor.fileId,
			source: 'programmatic',
		});

		expect(
			selectedBridgeFileViewerCodeViewItemForSnapshot({
				openFileState: {
					status: 'loading',
					descriptor: replacementDescriptor,
					path: replacementDescriptor.path,
				},
				renderSnapshot: store.getSnapshot(),
			}),
		).toBeNull();
		for (const status of ['refreshing', 'stale'] as const) {
			expect(
				selectedBridgeFileViewerCodeViewItemForSnapshot({
					openFileState: {
						status,
						descriptor: replacementDescriptor,
						path: replacementDescriptor.path,
					},
					renderSnapshot: store.getSnapshot(),
				}),
			).toBe(selectedCodeViewItem);
		}
	});
});

function makeSelectedFileCodeViewItem(props: {
	readonly cacheKey: string;
	readonly contents: string;
	readonly displayPath: string;
	readonly itemId: string;
	readonly lineCount: number;
}): BridgeWorkerCodeViewFileItem {
	return {
		id: `file:${props.itemId}`,
		type: 'file',
		file: {
			name: props.displayPath,
			contents: props.contents,
			cacheKey: props.cacheKey,
		},
		version: 1,
		bridgeMetadata: {
			itemId: props.itemId,
			displayPath: props.displayPath,
			contentState: 'hydrated',
			contentRoles: ['file'],
			cacheKey: props.cacheKey,
			lineCount: props.lineCount,
		},
	};
}
