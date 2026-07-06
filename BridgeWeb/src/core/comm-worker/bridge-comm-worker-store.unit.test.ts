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

	test('invalidates selected and visible review content through worker-owned cache truth', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [
				makeWorkerReviewContentMetadata('item-selected'),
				makeWorkerReviewContentMetadata('item-visible'),
				makeWorkerReviewContentMetadata('item-hidden'),
			],
			rows: [
				{ id: 'item-selected', parentId: null, index: 0 },
				{ id: 'item-visible', parentId: null, index: 1 },
				{ id: 'item-hidden', parentId: null, index: 2 },
			],
		});
		store.actions.applySelectedFact({ itemId: 'item-selected', epoch: 1 });
		store.actions.applyViewportFact({
			visibleItemIds: ['item-visible'],
			firstVisibleIndex: 1,
			lastVisibleIndex: 1,
		});
		store.actions.applyContentReady({
			itemId: 'item-selected',
			contentCacheKey: 'pierre-content:sha256:selected',
		});
		store.actions.applyContentReady({
			itemId: 'item-visible',
			contentCacheKey: 'pierre-content:sha256:visible',
		});
		store.actions.applyContentReady({
			itemId: 'item-hidden',
			contentCacheKey: 'pierre-content:sha256:hidden',
		});
		store.actions.takePendingSlicePatchEvent({ epoch: 1, sequence: 1 });

		const result = store.actions.applyReviewInvalidationFact({
			epoch: 8,
			itemIds: ['item-selected', 'item-visible'],
			pathHints: [],
			reason: 'watchEvent',
			scope: 'items',
		});
		const state = store.getState();
		const patchEvent = store.actions.takePendingSlicePatchEvent({ epoch: 8, sequence: 2 });

		expect(result.touchedKeys).toEqual([
			'paintReady:item-selected',
			'byteCache:pierre-content:sha256:selected',
			'availability:item-selected',
			'demand:item-selected',
			'paintReady:item-visible',
			'byteCache:pierre-content:sha256:visible',
			'availability:item-visible',
			'demand:item-visible',
		]);
		expect(Object.fromEntries(state.paintReadyByItemId)).toEqual({
			'item-hidden': 'pierre-content:sha256:hidden',
		});
		expect(Object.fromEntries(state.byteCache)).toEqual({
			'pierre-content:sha256:hidden': 'item-hidden',
		});
		expect(Object.fromEntries(state.availabilityByItemId)).toEqual({
			'item-selected': 'stale',
			'item-visible': 'stale',
			'item-hidden': 'ready',
		});
		expect(Object.fromEntries(state.demandByKey)).toEqual({
			'item-selected': 'selected:8',
			'item-visible': 'visible',
		});
		expect(patchEvent?.patches).toEqual([
			{ slice: 'rowPaint', operation: 'delete', itemId: 'item-selected' },
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'item-selected',
				payload: { state: 'stale' },
			},
			{ slice: 'rowPaint', operation: 'delete', itemId: 'item-visible' },
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'item-visible',
				payload: { state: 'stale' },
			},
		]);
	});

	test('keeps selected visible and paint-ready state across review source updates before invalidation', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [
				makeWorkerReviewContentMetadata('item-selected', {
					path: 'Sources/App/Before.swift',
				}),
				makeWorkerReviewContentMetadata('item-visible'),
			],
			rows: [
				{ id: 'item-selected', parentId: null, index: 0 },
				{ id: 'item-visible', parentId: null, index: 1 },
			],
		});
		store.actions.applySelectedFact({ itemId: 'item-selected', epoch: 1 });
		store.actions.applyViewportFact({
			visibleItemIds: ['item-visible'],
			firstVisibleIndex: 1,
			lastVisibleIndex: 1,
		});
		store.actions.applyContentReady({
			itemId: 'item-selected',
			contentCacheKey: 'pierre-content:sha256:selected-before',
		});
		store.actions.takePendingSlicePatchEvent({ epoch: 1, sequence: 1 });

		store.actions.applyReviewSourceUpdateFact({
			contentItems: [
				makeWorkerReviewContentMetadata('item-selected', {
					path: 'Sources/App/After.swift',
				}),
				makeWorkerReviewContentMetadata('item-visible'),
			],
			rows: [
				{ id: 'item-selected', parentId: null, index: 0 },
				{ id: 'item-visible', parentId: null, index: 1 },
			],
		});
		const result = store.actions.applyReviewInvalidationFact({
			epoch: 2,
			itemIds: [],
			pathHints: ['Sources/App/After.swift'],
			reason: 'watchEvent',
			scope: 'paths',
		});
		const patchEvent = store.actions.takePendingSlicePatchEvent({ epoch: 2, sequence: 2 });

		expect(result.touchedKeys).toEqual([
			'paintReady:item-selected',
			'byteCache:pierre-content:sha256:selected-before',
			'availability:item-selected',
			'demand:item-selected',
		]);
		expect(Object.fromEntries(store.getState().paintReadyByItemId)).toEqual({});
		expect(Object.fromEntries(store.getState().demandByKey)).toEqual({
			'item-selected': 'selected:2',
			'item-visible': 'visible',
		});
		expect(patchEvent?.patches).toEqual([
			{ slice: 'rowPaint', operation: 'delete', itemId: 'item-selected' },
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'item-selected',
				payload: { state: 'stale' },
			},
		]);
	});

	test('invalidates package and tree-window scopes without requiring fresh metadata', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerReviewContentMetadata('item-selected')],
			rows: [{ id: 'item-selected', parentId: null, index: 0 }],
		});
		store.actions.applySelectedFact({ itemId: 'item-selected', epoch: 1 });
		store.actions.applyContentReady({
			itemId: 'item-selected',
			contentCacheKey: 'pierre-content:sha256:selected',
		});
		store.actions.takePendingSlicePatchEvent({ epoch: 1, sequence: 1 });
		store.actions.applyReviewSourceUpdateFact({
			contentItems: [],
			rows: [],
		});

		store.actions.applyReviewInvalidationFact({
			epoch: 2,
			itemIds: [],
			pathHints: [],
			reason: 'lineageReplaced',
			scope: 'package',
		});
		const packagePatchEvent = store.actions.takePendingSlicePatchEvent({ epoch: 2, sequence: 2 });
		store.actions.applyContentReady({
			itemId: 'item-selected',
			contentCacheKey: 'pierre-content:sha256:selected-again',
		});
		store.actions.takePendingSlicePatchEvent({ epoch: 2, sequence: 3 });
		store.actions.applyReviewInvalidationFact({
			epoch: 3,
			itemIds: [],
			pathHints: [],
			reason: 'watchEvent',
			scope: 'treeWindow',
		});
		const treeWindowPatchEvent = store.actions.takePendingSlicePatchEvent({
			epoch: 3,
			sequence: 4,
		});

		expect(packagePatchEvent?.patches).toEqual([
			{ slice: 'rowPaint', operation: 'delete', itemId: 'item-selected' },
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'item-selected',
				payload: { state: 'stale' },
			},
		]);
		expect(treeWindowPatchEvent?.patches).toEqual([
			{ slice: 'rowPaint', operation: 'delete', itemId: 'item-selected' },
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'item-selected',
				payload: { state: 'stale' },
			},
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

function makeWorkerReviewContentMetadata(
	itemId: string,
	props: { readonly path?: string } = {},
): BridgeWorkerReviewContentMetadata {
	const item = makeBridgeReviewItem({
		itemId,
		path: props.path ?? `Sources/App/${itemId}.swift`,
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
