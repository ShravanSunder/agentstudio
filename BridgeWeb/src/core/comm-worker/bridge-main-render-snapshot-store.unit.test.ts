import { describe, expect, test } from 'vitest';

import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainCodeViewItem,
} from './bridge-main-render-snapshot-store.js';

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
			/sourceGeneration|workerDerivationEpoch|streamId|sequence|byteCache|demandMembership|retryAfterVersion/i,
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
});

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
