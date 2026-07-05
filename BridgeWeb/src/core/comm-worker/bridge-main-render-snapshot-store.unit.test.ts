import { describe, expect, test } from 'vitest';

import { createBridgeMainRenderSnapshotStore } from './bridge-main-render-snapshot-store.js';

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
});
