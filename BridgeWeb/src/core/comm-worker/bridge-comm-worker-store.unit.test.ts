import { describe, expect, test } from 'vitest';

import { makeBridgeReviewItem } from '../../foundation/review-package/bridge-review-package-test-support.js';
import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type { BridgeWorkerReviewContentMetadata } from './bridge-worker-contracts.js';

describe('Bridge comm worker store', () => {
	test('normalizes worker state and rejects root snapshots getState payloads and package-shaped hot actions', () => {
		const contentItem = makeWorkerReviewContentMetadata('item-2');
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerReviewContentMetadata('item-1'), contentItem],
			rows: [
				{ id: 'root', parentId: null, index: 0 },
				{ id: 'item-1', parentId: 'root', index: 1 },
				{ id: 'item-2', parentId: 'root', index: 2 },
			],
		});

		const selectedResult = store.actions.applySelectedFact({
			itemId: 'item-2',
			epoch: 3,
		});
		const viewportResult = store.actions.applyViewportFact({
			visibleItemIds: ['item-1', 'item-2'],
			firstVisibleIndex: 1,
			lastVisibleIndex: 2,
		});
		const contentReadyResult = store.actions.applyContentReady({
			itemId: 'item-2',
			contentCacheKey: 'pierre-content:sha256:item-2',
		});
		const patchEvent = store.actions.takePendingSlicePatchEvent({ epoch: 4, sequence: 9 });
		const state = store.getState();

		expect(state.rowById.get('item-2')).toEqual({ id: 'item-2', parentId: 'root', index: 2 });
		expect(state.orderedIds).toEqual(['root', 'item-1', 'item-2']);
		expect(state.indexById.get('item-2')).toBe(2);
		expect(state.childrenByParentId.get('root')).toEqual(['item-1', 'item-2']);
		expect(state.contentMetadataByItemId.get('item-2')).toEqual(contentItem);
		expect(Object.fromEntries(state.demandByKey)).toEqual({
			'item-1': 'visible',
			'item-2': 'selected:3',
		});
		expect(selectedResult.touchedKeys).toEqual([
			'selectedId',
			'rowPaint:item-2',
			'availability:item-2',
			'contentMetadata:item-2',
			'demand:item-2',
		]);
		expect(viewportResult.touchedKeys).toEqual([
			'viewportRange',
			'visibleIds:item-1',
			'visibleIds:item-2',
			'demand:item-1',
			'demand:item-2',
		]);
		expect(contentReadyResult.touchedKeys).toEqual([
			'byteCache:pierre-content:sha256:item-2',
			'paintReady:item-2',
			'availability:item-2',
		]);
		expect(patchEvent).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'slicePatch',
			epoch: 4,
			sequence: 9,
		});
		expect(patchEvent?.patches).toEqual([
			{
				slice: 'selection',
				operation: 'upsert',
				payload: { selectedItemId: 'item-2' },
			},
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'item-2',
				payload: { state: 'loading' },
			},
			{
				slice: 'viewport',
				operation: 'upsert',
				payload: {
					firstVisibleIndex: 1,
					lastVisibleIndex: 2,
					visibleItemIds: ['item-1', 'item-2'],
				},
			},
			{
				slice: 'rowPaint',
				operation: 'upsert',
				itemId: 'item-2',
				payload: { contentCacheKey: 'pierre-content:sha256:item-2' },
			},
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'item-2',
				payload: { state: 'ready' },
			},
		]);
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 4, sequence: 10 })).toBeNull();
		expect(JSON.stringify(patchEvent)).not.toMatch(/rowById|orderedIds|rootSnapshot|allRows/i);
		expect(() => store.actions.buildRootSnapshotPayload()).toThrow(/root snapshots are forbidden/i);
	});

	test('does not create selected demand or loading availability when selected preparation is absent', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerReviewContentMetadata('item-2')],
			rows: [{ id: 'item-2', parentId: null, index: 0 }],
		});

		const selectedResult = store.actions.applySelectedFact({
			itemId: 'item-2',
			epoch: 3,
			selectedPreparationAvailable: false,
		});
		const patchEvent = store.actions.takePendingSlicePatchEvent({ epoch: 3, sequence: 9 });

		expect(store.getState().selectedId).toBe('item-2');
		expect(Object.fromEntries(store.getState().demandByKey)).toEqual({});
		expect(store.getState().availabilityByItemId.has('item-2')).toBe(false);
		expect(selectedResult.touchedKeys).toEqual(['selectedId']);
		expect(patchEvent?.patches).toEqual([
			{
				slice: 'selection',
				operation: 'upsert',
				payload: { selectedItemId: 'item-2' },
			},
		]);
	});

	test('keeps raw ids distinct and retires stale selected and viewport demand entries', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [
				makeWorkerReviewContentMetadata('item-1'),
				makeWorkerReviewContentMetadata('item:2/path'),
			],
			rows: [
				{ id: 'item-1', parentId: null, index: 0 },
				{ id: 'item_1', parentId: null, index: 1 },
				{ id: 'item:2/path', parentId: null, index: 2 },
			],
		});

		store.actions.applyViewportFact({
			visibleItemIds: ['item-1', 'item_1'],
			firstVisibleIndex: 0,
			lastVisibleIndex: 1,
		});
		store.actions.applySelectedFact({ itemId: 'item-1', epoch: 1 });
		store.actions.applySelectedFact({ itemId: 'item:2/path', epoch: 2 });
		const viewportReplaceResult = store.actions.applyViewportFact({
			visibleItemIds: ['item:2/path'],
			firstVisibleIndex: 2,
			lastVisibleIndex: 2,
		});

		const state = store.getState();

		expect(state.rowById.get('item-1')?.id).toBe('item-1');
		expect(state.rowById.get('item_1')?.id).toBe('item_1');
		expect(state.rowById.get('item:2/path')?.id).toBe('item:2/path');
		expect(Object.fromEntries(state.demandByKey)).toEqual({
			'item:2/path': 'selected:2',
		});
		expect(viewportReplaceResult.touchedKeys).toEqual([
			'viewportRange',
			'visibleIds:item-1',
			'visibleIds:item_1',
			'visibleIds:item:2/path',
			'demand:item-1',
			'demand:item_1',
			'demand:item:2/path',
		]);
	});

	test('marks selected content unavailable when worker metadata is absent', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerReviewContentMetadata('visible-item')],
			rows: [
				{ id: 'item-without-content-metadata', parentId: null, index: 0 },
				{ id: 'visible-item', parentId: null, index: 1 },
			],
		});

		store.actions.applySelectedFact({
			itemId: 'item-without-content-metadata',
			epoch: 5,
		});
		store.actions.applyViewportFact({
			visibleItemIds: ['visible-item'],
			firstVisibleIndex: 1,
			lastVisibleIndex: 1,
		});

		expect(Object.fromEntries(store.getState().demandByKey)).toEqual({
			'visible-item': 'visible',
		});
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 5, sequence: 12 })?.patches).toEqual([
			{
				slice: 'selection',
				operation: 'upsert',
				payload: { selectedItemId: 'item-without-content-metadata' },
			},
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'item-without-content-metadata',
				payload: { state: 'unavailable' },
			},
			{
				slice: 'viewport',
				operation: 'upsert',
				payload: {
					firstVisibleIndex: 1,
					lastVisibleIndex: 1,
					visibleItemIds: ['visible-item'],
				},
			},
		]);
	});

	test('marks selected content unavailable when worker metadata has no content roles', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [
				{
					...makeWorkerReviewContentMetadata('metadata-only-item'),
					availableContentRoles: [],
				},
			],
			rows: [{ id: 'metadata-only-item', parentId: null, index: 0 }],
		});

		store.actions.applySelectedFact({
			itemId: 'metadata-only-item',
			epoch: 6,
		});

		expect(Object.fromEntries(store.getState().demandByKey)).toEqual({});
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 6, sequence: 13 })?.patches).toEqual([
			{
				slice: 'selection',
				operation: 'upsert',
				payload: { selectedItemId: 'metadata-only-item' },
			},
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'metadata-only-item',
				payload: { state: 'unavailable' },
			},
		]);
	});

	test('publishes terminal availability for selected content failures', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
		});

		store.actions.applySelectedFact({
			itemId: 'item-1',
			epoch: 7,
		});
		store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 14 });
		const failedResult = store.actions.applyContentTerminalAvailability({
			itemId: 'item-1',
			state: 'failed',
		});

		expect(store.getState().availabilityByItemId.get('item-1')).toBe('failed');
		expect(failedResult.touchedKeys).toEqual(['availability:item-1']);
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 15 })?.patches).toEqual([
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'item-1',
				payload: { state: 'failed' },
			},
		]);
	});
});

function makeWorkerReviewContentMetadata(itemId: string): BridgeWorkerReviewContentMetadata {
	const item = makeBridgeReviewItem({
		itemId,
		path: `Sources/App/${itemId}.swift`,
	});
	return {
		itemId: item.itemId,
		path: item.headPath ?? item.basePath ?? item.itemId,
		language: item.language ?? null,
		cacheKey: item.cacheKey,
		sizeBytes: item.sizeBytes,
		availableContentRoles: ['head'],
		contentLineCountsByRole: item.contentLineCountsByRole ?? {},
	};
}
