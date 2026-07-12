import { describe, expect, test } from 'vitest';

import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainCodeViewItem,
} from './bridge-main-render-snapshot-store.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerFileDisplayPatchEvent,
} from './bridge-worker-contracts.js';

describe('Bridge main render snapshot store', () => {
	test('uses useSyncExternalStore and accepts only local intent plus worker patch writes', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const initialSnapshot = store.getSnapshot();
		let publishCount = 0;
		const unsubscribe = store.subscribe(() => {
			publishCount += 1;
		});

		expect(store.getSnapshot()).toBe(initialSnapshot);
		expect(store.getServerSnapshot()).toBe(initialSnapshot);

		store.setLocalSelection({ selectedItemId: 'item-1', source: 'user' });
		store.setLocalViewport({
			firstVisibleIndex: 0,
			lastVisibleIndex: 2,
			visibleItemIds: ['item-1', 'item-2', 'item-3'],
		});
		store.applyWorkerPatch({
			slice: 'selection',
			operation: 'upsert',
			payload: {
				selectedItemId: 'item-from-worker',
				source: 'keyboard',
			},
		});
		store.applyWorkerPatch({
			slice: 'viewport',
			operation: 'upsert',
			payload: {
				firstVisibleIndex: 1,
				lastVisibleIndex: 2,
				visibleItemIds: ['item-from-worker', 'item:2/path'],
			},
		});
		store.applyWorkerPatch({
			slice: 'rowPaint',
			operation: 'upsert',
			itemId: 'item:2/path',
			payload: {
				label: 'README.md',
				status: 'modified',
			},
		});
		store.applyWorkerPatch({
			slice: 'contentAvailability',
			operation: 'upsert',
			itemId: 'item:2/path',
			payload: {
				state: 'ready',
			},
		});

		const snapshot = store.getSnapshot();

		expect(snapshot.selectionSlice).toEqual({
			selectedItemId: 'item-from-worker',
			source: 'keyboard',
		});
		expect(snapshot.viewportSlice.visibleItemIds).toEqual(['item-from-worker', 'item:2/path']);
		expect(snapshot.rowPaintById['item:2/path']).toEqual({
			label: 'README.md',
			status: 'modified',
		});
		expect(snapshot.contentAvailabilityById['item:2/path']).toEqual({
			state: 'ready',
		});
		expect(JSON.stringify(snapshot)).not.toMatch(
			/workerDerivationEpoch|streamId|byteCache|demandMembership|retryAfterVersion|contentDescriptor|descriptorId|expectedSha256|leaseId|sourceCursor/i,
		);
		expect(publishCount).toBe(6);

		unsubscribe();
	});

	test('applies reset and delete worker patches without app-side payload parsing', () => {
		const store = createBridgeMainRenderSnapshotStore();

		store.applyWorkerPatch({
			slice: 'selection',
			operation: 'upsert',
			payload: {
				selectedItemId: 'item-1',
				source: 'user',
			},
		});
		store.applyWorkerPatch({
			slice: 'viewport',
			operation: 'upsert',
			payload: {
				firstVisibleIndex: 0,
				lastVisibleIndex: 1,
				visibleItemIds: ['item-1', 'item-2'],
			},
		});
		store.applyWorkerPatch({
			slice: 'rowPaint',
			operation: 'upsert',
			itemId: 'item-1',
			payload: {
				contentCacheKey: 'pierre-content:item-1',
			},
		});
		store.applyWorkerPatch({
			slice: 'contentAvailability',
			operation: 'upsert',
			itemId: 'item-1',
			payload: {
				state: 'ready',
			},
		});

		store.applyWorkerPatch({ slice: 'selection', operation: 'delete' });
		store.applyWorkerPatch({ slice: 'viewport', operation: 'reset' });
		store.applyWorkerPatch({
			slice: 'rowPaint',
			operation: 'delete',
			itemId: 'item-1',
		});
		store.applyWorkerPatch({ slice: 'contentAvailability', operation: 'reset' });

		expect(store.getSnapshot()).toMatchObject({
			selectionSlice: {
				selectedItemId: null,
				source: null,
			},
			viewportSlice: {
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				visibleItemIds: [],
			},
			rowPaintById: {},
			contentAvailabilityById: {},
		});
	});

	test('drops cached CodeView display items when worker row paint invalidates them', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const item = makeBridgeMainCodeViewItem('item-1');

		store.setWorkerCodeViewItem({ itemId: 'item-1', item });
		store.applyWorkerPatch({
			slice: 'rowPaint',
			operation: 'upsert',
			itemId: 'item-1',
			payload: {
				contentCacheKey: 'pierre-content:item-1',
			},
		});

		expect(store.getSnapshot().codeViewItemsById['item-1']).toBe(item);

		store.applyWorkerPatch({
			slice: 'rowPaint',
			operation: 'delete',
			itemId: 'item-1',
		});

		expect(store.getSnapshot().codeViewItemsById['item-1']).toBeUndefined();

		store.setWorkerCodeViewItem({ itemId: 'item-1', item });
		store.applyWorkerPatch({
			slice: 'rowPaint',
			operation: 'reset',
		});

		expect(store.getSnapshot().codeViewItemsById).toEqual({});
	});

	test('keeps CodeView display cache identity stable for row paint upserts', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const item = makeBridgeMainCodeViewItem('item-1');

		store.setWorkerCodeViewItem({ itemId: 'item-1', item });
		const beforeRowPaint = store.getSnapshot().codeViewItemsById;

		store.applyWorkerPatch({
			slice: 'rowPaint',
			operation: 'upsert',
			itemId: 'item-1',
			payload: {
				contentCacheKey: 'pierre-content:item-1',
				status: 'ready',
			},
		});

		const afterRowPaint = store.getSnapshot();
		expect(afterRowPaint.codeViewItemsById).toBe(beforeRowPaint);
		expect(afterRowPaint.codeViewItemsById['item-1']).toBe(item);
		expect(afterRowPaint.rowPaintById['item-1']).toEqual({
			contentCacheKey: 'pierre-content:item-1',
			status: 'ready',
		});
	});

	test('does not mutate previous snapshots for single CodeView item patches', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const item = makeBridgeMainCodeViewItem('item-1');
		const emptySnapshot = store.getSnapshot();

		store.setWorkerCodeViewItem({ itemId: 'item-1', item });
		const populatedSnapshot = store.getSnapshot();

		store.applySnapshotUpdate({
			codeViewItemPatches: [
				{
					operation: 'delete',
					itemId: 'item-1',
				},
			],
		});

		expect(emptySnapshot.codeViewItemsById['item-1']).toBeUndefined();
		expect(populatedSnapshot.codeViewItemsById['item-1']).toBe(item);
		expect(store.getSnapshot().codeViewItemsById['item-1']).toBeUndefined();
	});

	test('batches local selection, CodeView item, and worker patches into one publish', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const item = makeBridgeMainCodeViewItem('item-1');
		let publishCount = 0;
		const unsubscribe = store.subscribe(() => {
			publishCount += 1;
		});

		store.applySnapshotUpdate({
			localSelection: {
				selectedItemId: 'item-1',
				source: 'programmatic',
			},
			codeViewItemPatches: [
				{
					operation: 'upsert',
					itemId: 'item-1',
					item,
				},
			],
			workerPatches: [
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'ready' },
				},
			],
		});

		expect(publishCount).toBe(1);
		expect(store.getSnapshot().selectionSlice).toEqual({
			selectedItemId: 'item-1',
			source: 'programmatic',
		});
		expect(store.getSnapshot().codeViewItemsById['item-1']).toBe(item);
		expect(store.getSnapshot().contentAvailabilityById['item-1']).toEqual({
			state: 'ready',
		});

		unsubscribe();
	});

	test('atomically applies a strict File display event without product authority fields', () => {
		const store = createBridgeMainRenderSnapshotStore();
		let publishCount = 0;
		const unsubscribe = store.subscribe(() => {
			publishCount += 1;
		});

		store.applyFileDisplayPatchEvent(makeFileDisplayPatchEvent());

		expect(publishCount).toBe(1);
		const snapshot = store.getSnapshot();
		expect(snapshot).toMatchObject({
			fileDisplayFreshness: {
				epoch: 4,
				projectionRevision: 8,
				sequence: 12,
			},
			fileStatusSlice: {
				ahead: 1,
				behind: 0,
				branchName: 'main',
				staged: 2,
				state: 'ready',
				unstaged: 3,
				untracked: 4,
			},
			fileTreeSlice: {
				sourceGeneration: 6,
				sourceId: 'file-source-1',
			},
		});
		expect(snapshot.fileItemById.size).toBe(1);
		expect(snapshot.fileItemById.get('file-1')).toMatchObject({
			displayPath: 'Sources/File.swift',
			payloadByteCount: 100_000,
			payloadLineCount: 10_000,
			truncationKind: 'lineLimit',
		});
		expect(snapshot.fileTreeSlice.index.size).toBe(1);
		expect(snapshot.fileTreeSlice.index.rowForId('row-file-1')).toMatchObject({
			path: 'Sources/File.swift',
			projectionIndex: 3,
		});
		expect(JSON.stringify(snapshot)).not.toMatch(
			/contentDescriptor|descriptorId|expectedSha256|leaseId|sourceCursor|byteCache|demandMembership|retryAfterVersion/i,
		);

		unsubscribe();
	});

	test('rejects stale File display events and clears old display copies on epoch advance', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const acceptedEvent = makeFileDisplayPatchEvent();
		store.applyFileDisplayPatchEvent(acceptedEvent);
		const acceptedSnapshot = store.getSnapshot();

		for (const staleEvent of [
			{ ...acceptedEvent, epoch: 3, sequence: 99, projectionRevision: 99 },
			{ ...acceptedEvent, sequence: acceptedEvent.sequence },
			{ ...acceptedEvent, sequence: 13, projectionRevision: acceptedEvent.projectionRevision },
		]) {
			store.applyFileDisplayPatchEvent(staleEvent);
			expect(store.getSnapshot()).toBe(acceptedSnapshot);
		}

		store.applyFileDisplayPatchEvent({
			...acceptedEvent,
			epoch: 5,
			sequence: 1,
			projectionRevision: 9,
			patches: [
				{
					slice: 'fileStatus',
					operation: 'upsert',
					payload: { state: 'stale' },
				},
			],
		});

		const nextSnapshot = store.getSnapshot();
		expect(nextSnapshot).toMatchObject({
			fileDisplayFreshness: { epoch: 5, projectionRevision: 9, sequence: 1 },
			fileStatusSlice: { state: 'stale' },
			fileTreeSlice: {
				sourceGeneration: null,
				sourceId: null,
			},
		});
		expect(nextSnapshot.fileItemById.size).toBe(0);
		expect(nextSnapshot.fileTreeSlice.index.size).toBe(0);
	});

	test('applies File tree removals and File item/status reset variants', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const initialEvent = makeFileDisplayPatchEvent();
		store.applyFileDisplayPatchEvent(initialEvent);

		store.applyFileDisplayPatchEvent({
			...initialEvent,
			sequence: 13,
			projectionRevision: 9,
			patches: [
				{
					slice: 'fileTree',
					operation: 'batch',
					payload: {
						operations: [
							{
								operation: 'remove',
								path: 'Sources/File.swift',
								rowId: 'row-file-1',
							},
						],
					},
				},
				{ slice: 'fileItem', operation: 'delete', itemId: 'file-1' },
				{ slice: 'fileStatus', operation: 'reset' },
			],
		});

		const nextSnapshot = store.getSnapshot();
		expect(nextSnapshot.fileItemById.size).toBe(0);
		expect(nextSnapshot.fileStatusSlice).toBeNull();
		expect(nextSnapshot.fileTreeSlice.index.size).toBe(0);
	});

	test('clears File source identity and display copies on a failure epoch', () => {
		const store = createBridgeMainRenderSnapshotStore();
		store.applyFileDisplayPatchEvent(makeFileDisplayPatchEvent());

		store.applyFileDisplayPatchEvent({
			direction: 'serverWorkerToMain',
			epoch: 5,
			kind: 'fileDisplayPatch',
			patches: [
				{ operation: 'clear', slice: 'fileTree' },
				{ operation: 'reset', slice: 'fileItem' },
				{ operation: 'reset', slice: 'fileStatus' },
			],
			projectionRevision: 1,
			sequence: 13,
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		});

		const nextSnapshot = store.getSnapshot();
		expect(nextSnapshot).toMatchObject({
			fileDisplayFreshness: { epoch: 5, projectionRevision: 1, sequence: 13 },
			fileStatusSlice: null,
			fileTreeSlice: { sourceGeneration: null, sourceId: null },
		});
		expect(nextSnapshot.fileItemById.size).toBe(0);
		expect(nextSnapshot.fileTreeSlice.index.size).toBe(0);
	});
});

function makeFileDisplayPatchEvent(): BridgeWorkerFileDisplayPatchEvent {
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'fileDisplayPatch',
		surface: 'fileView',
		epoch: 4,
		sequence: 12,
		projectionRevision: 8,
		patches: [
			{
				slice: 'fileTree',
				operation: 'reset',
				payload: { sourceGeneration: 6, sourceId: 'file-source-1' },
			},
			{
				slice: 'fileTree',
				operation: 'batch',
				payload: {
					operations: [
						{
							operation: 'upsert',
							row: {
								changeStatus: 'modified',
								depth: 1,
								fileId: 'file-1',
								isDirectory: false,
								lineCount: 12_000,
								name: 'File.swift',
								parentPath: 'Sources',
								path: 'Sources/File.swift',
								projectionIndex: 3,
								rowId: 'row-file-1',
								sizeBytes: 120_000,
							},
						},
					],
				},
			},
			{
				slice: 'fileItem',
				operation: 'upsert',
				itemId: 'file-1',
				payload: {
					availability: { kind: 'available' },
					displayPath: 'Sources/File.swift',
					endsMidLine: false,
					endsWithNewline: true,
					extent: { kind: 'exactLineCount', lineCount: 12_000 },
					fileExtension: 'swift',
					language: 'swift',
					payloadByteCount: 100_000,
					payloadLineCount: 10_000,
					rowId: 'row-file-1',
					sizeBytes: 120_000,
					totalLineCount: 12_000,
					truncationKind: 'lineLimit',
				},
			},
			{
				slice: 'fileStatus',
				operation: 'upsert',
				payload: {
					state: 'ready',
					ahead: 1,
					behind: 0,
					branchName: 'main',
					staged: 2,
					unstaged: 3,
					untracked: 4,
				},
			},
		],
	};
}

function makeBridgeMainCodeViewItem(itemId: string): BridgeMainCodeViewItem {
	return {
		id: itemId,
		type: 'file',
		file: {
			name: 'src/stale.ts',
			contents: 'export const stale = true;\n',
			lang: 'typescript',
			cacheKey: `pierre-content:${itemId}`,
		},
		version: 1,
		bridgeMetadata: {
			itemId,
			displayPath: 'src/stale.ts',
			contentState: 'hydrated',
			contentRoles: ['file'],
			cacheKey: `pierre-content:${itemId}`,
			lineCount: 1,
		},
	};
}
