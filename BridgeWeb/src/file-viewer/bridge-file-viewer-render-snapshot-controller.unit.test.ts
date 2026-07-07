import { describe, expect, test } from 'vitest';

import { createBridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgeWorkerCodeViewFileItem } from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import { makeFileDescriptor } from './bridge-file-viewer-browser-test-fixtures.js';
import {
	publishBridgeFileViewerLoadingStateToSnapshotStore,
	publishBridgeFileViewerRefreshingStateToSnapshotStore,
	publishBridgeFileViewerSelectedCodeViewItemToSnapshotStore,
	selectedBridgeFileViewerCodeViewItemForSnapshot,
} from './bridge-file-viewer-render-snapshot-controller.js';

describe('Bridge File Viewer render snapshot controller', () => {
	test('file view receives selected CodeView display from shared worker snapshot state', () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'content-selected',
			fileId: 'file-selected',
			lineCount: 2,
			path: 'Sources/Selected.swift',
		});
		const store = createBridgeMainRenderSnapshotStore();
		const selectedCodeViewItem = makeSelectedFileCodeViewItem({
			cacheKey: 'content-selected:hash-selected',
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

	test('file view local display helpers leave content availability to worker patches', () => {
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
				cacheKey: 'content-worker-owned:hash-worker-owned',
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
		expect(store.getSnapshot().contentAvailabilityById[descriptor.fileId]).toBeUndefined();

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
