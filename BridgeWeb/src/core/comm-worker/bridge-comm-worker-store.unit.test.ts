import { describe, expect, test } from 'vitest';

import { makeBridgeReviewItem } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerReviewContentMetadata,
} from './bridge-worker-contracts.js';

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

	test('does not churn availability state for viewport facts with no unavailable content', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
		});

		const previousAvailabilityByItemId = store.getState().availabilityByItemId;
		const viewportResult = store.actions.applyViewportFact({
			visibleItemIds: ['item-1'],
			firstVisibleIndex: 0,
			lastVisibleIndex: 0,
		});

		expect(store.getState().availabilityByItemId).toBe(previousAvailabilityByItemId);
		expect(viewportResult.touchedKeys).toEqual([
			'viewportRange',
			'visibleIds:item-1',
			'demand:item-1',
		]);
	});

	test('records touched keys and patch size for worker hot store actions', () => {
		let clockMs = 10;
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			now: () => {
				const value = clockMs;
				clockMs += 2;
				return value;
			},
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});

		store.actions.applySelectedFact({ itemId: 'item-1', epoch: 4 });

		expect(telemetrySamples).toHaveLength(1);
		expect(telemetrySamples[0]).toMatchObject({
			name: 'performance.bridge.worker.task',
			durationMilliseconds: 2,
			stringAttributes: {
				'agentstudio.bridge.result': 'success',
				'agentstudio.bridge.worker.action': 'applySelectedFact',
				'agentstudio.bridge.worker.lane': 'selected',
				'agentstudio.bridge.worker.task_kind': 'store_action',
			},
			numericAttributes: {
				'agentstudio.bridge.worker.handler_duration_ms': 2,
				'agentstudio.bridge.worker.patch_count': 2,
				'agentstudio.bridge.worker.touched_key_count': 5,
			},
		});
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

	test('review source updates report summary touches instead of package-shaped metadata touches', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [],
			rows: [],
		});
		const contentItems = Array.from({ length: 130 }, (_unused, index) =>
			makeWorkerReviewContentMetadata(`item-${index + 1}`),
		);
		const rows = contentItems.map((metadata, index) => ({
			id: metadata.itemId,
			parentId: null,
			index,
		}));

		const result = store.actions.applyReviewSourceUpdateFact({
			contentItems,
			rows,
		});

		expect(result.touchedKeys).toEqual(['sourceRows', 'sourceContentMetadata']);
		expect(result.touchedKeys).not.toContain('contentMetadata:item-130');
		expect(store.getState().contentMetadataByItemId.get('item-130')).toEqual(contentItems[129]);
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

	test('partial review source updates retain row-only rows through final reset completion', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerReviewContentMetadata('old-item')],
			rows: [
				{ id: 'old-item', parentId: null, index: 0 },
				{ id: 'old-row-only', parentId: null, index: 1 },
			],
		});

		store.actions.applyReviewSourceUpdateFact({
			completeItemIds: ['item-1', 'row-only-item'],
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			resetComplete: false,
			rows: [
				{ id: 'item-1', parentId: null, index: 0 },
				{ id: 'row-only-item', parentId: null, index: 1 },
			],
		});

		expect(store.getState().rowById.has('row-only-item')).toBe(true);
		expect(store.getState().contentMetadataByItemId.has('row-only-item')).toBe(false);
		expect(store.getState().rowById.has('old-row-only')).toBe(false);
		expect(store.getState().contentMetadataByItemId.has('old-item')).toBe(false);
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

	test('worker-local store owns file metadata content cache demand and protocol truth', () => {
		const fileContentMetadata = makeWorkerFileViewContentMetadata('file-text');
		const binaryMetadata = makeWorkerFileViewContentMetadata('file-binary', {
			canFetchContent: false,
			isBinary: true,
		});
		const store = createBridgeCommWorkerStore({
			contentItems: [fileContentMetadata, binaryMetadata],
			rows: [
				{ id: 'file-text', parentId: null, index: 0 },
				{ id: 'file-binary', parentId: null, index: 1 },
			],
		});

		store.actions.applySelectedFact({ itemId: 'file-text', epoch: 4 });
		store.actions.applyViewportFact({
			visibleItemIds: ['file-text', 'file-binary'],
			firstVisibleIndex: 0,
			lastVisibleIndex: 1,
		});
		store.actions.applyContentReady({
			itemId: 'file-text',
			contentCacheKey: fileContentMetadata.cacheKey,
		});
		const firstPatchEvent = store.actions.takePendingSlicePatchEvent({ epoch: 4, sequence: 1 });
		const sourceUpdateResult = store.actions.applyFileViewSourceUpdateFact({
			contentItems: [
				makeWorkerFileViewContentMetadata('file-text', {
					path: 'Sources/App/FileViewRenamed.swift',
				}),
			],
			epoch: 5,
			rows: [{ id: 'file-text', parentId: null, index: 0 }],
		});
		const nextState = store.getState();

		expect(Object.fromEntries(nextState.contentMetadataByItemId)).toEqual({
			'file-text': makeWorkerFileViewContentMetadata('file-text', {
				path: 'Sources/App/FileViewRenamed.swift',
			}),
		});
		expect(Object.fromEntries(nextState.demandByKey)).toEqual({
			'file-text': 'selected:5',
		});
		expect(firstPatchEvent?.patches).toContainEqual({
			slice: 'contentAvailability',
			operation: 'upsert',
			itemId: 'file-binary',
			payload: { state: 'unavailable' },
		});
		expect(sourceUpdateResult.touchedKeys).toEqual([
			'sourceRows',
			'sourceContentMetadata',
			'contentMetadata:file-text',
			'demand:file-text',
		]);
		expect(JSON.stringify(firstPatchEvent)).not.toMatch(/contentHandle|resourceUrl|contents|body/i);
	});

	test('file view source updates repair selected unavailable content into loading demand', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});
		store.actions.applySelectedFact({ itemId: 'file-1', epoch: 9 });
		store.actions.takePendingSlicePatchEvent({ epoch: 9, sequence: 1 });

		const sourceUpdateResult = store.actions.applyFileViewSourceUpdateFact({
			contentItems: [makeWorkerFileViewContentMetadata('file-1')],
			epoch: 10,
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});

		expect(store.getState().availabilityByItemId.get('file-1')).toBe('loading');
		expect(Object.fromEntries(store.getState().demandByKey)).toEqual({
			'file-1': 'selected:10',
		});
		expect(sourceUpdateResult.touchedKeys).toEqual([
			'sourceRows',
			'sourceContentMetadata',
			'contentMetadata:file-1',
			'availability:file-1',
			'demand:file-1',
		]);
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 10, sequence: 2 })?.patches).toEqual([
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'file-1',
				payload: { state: 'loading' },
			},
		]);
	});

	test('file view source updates retain selected stale paint when metadata is temporarily absent', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerFileViewContentMetadata('file-1')],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});
		store.actions.applySelectedFact({ itemId: 'file-1', epoch: 13 });
		store.actions.applyContentReady({
			itemId: 'file-1',
			contentCacheKey: 'file-view:sha256:file-1',
		});
		store.actions.takePendingSlicePatchEvent({ epoch: 13, sequence: 1 });

		const sourceUpdateResult = store.actions.applyFileViewSourceUpdateFact({
			contentItems: [],
			epoch: 14,
			rows: [],
		});

		expect(store.getState().paintReadyByItemId.get('file-1')).toBe('file-view:sha256:file-1');
		expect(store.getState().byteCache.get('file-view:sha256:file-1')).toBe('file-1');
		expect(store.getState().availabilityByItemId.get('file-1')).toBe('stale');
		expect(Object.fromEntries(store.getState().demandByKey)).toEqual({});
		expect(sourceUpdateResult.touchedKeys).toEqual([
			'sourceRows',
			'sourceContentMetadata',
			'availability:file-1',
			'demand:file-1',
		]);
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 14, sequence: 2 })?.patches).toEqual([
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'file-1',
				payload: { state: 'stale' },
			},
		]);
	});

	test('file view source updates remove ready paint when content becomes unavailable', () => {
		const store = createBridgeCommWorkerStore({
			contentItems: [makeWorkerFileViewContentMetadata('file-1')],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});
		store.actions.applySelectedFact({ itemId: 'file-1', epoch: 11 });
		store.actions.applyContentReady({
			itemId: 'file-1',
			contentCacheKey: 'file-view:sha256:file-1',
		});
		store.actions.takePendingSlicePatchEvent({ epoch: 11, sequence: 1 });

		const sourceUpdateResult = store.actions.applyFileViewSourceUpdateFact({
			contentItems: [
				makeWorkerFileViewContentMetadata('file-1', {
					canFetchContent: false,
					isBinary: true,
				}),
			],
			epoch: 12,
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});

		expect(store.getState().paintReadyByItemId.has('file-1')).toBe(false);
		expect(store.getState().byteCache.has('file-view:sha256:file-1')).toBe(false);
		expect(store.getState().availabilityByItemId.get('file-1')).toBe('unavailable');
		expect(Object.fromEntries(store.getState().demandByKey)).toEqual({});
		expect(sourceUpdateResult.touchedKeys).toEqual([
			'sourceRows',
			'sourceContentMetadata',
			'contentMetadata:file-1',
			'paintReady:file-1',
			'byteCache:file-view:sha256:file-1',
			'availability:file-1',
			'demand:file-1',
		]);
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 12, sequence: 2 })?.patches).toEqual([
			{ slice: 'rowPaint', operation: 'delete', itemId: 'file-1' },
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'file-1',
				payload: { state: 'unavailable' },
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

function makeWorkerFileViewContentMetadata(
	itemId: string,
	props: {
		readonly canFetchContent?: boolean;
		readonly isBinary?: boolean;
		readonly path?: string;
	} = {},
): BridgeWorkerFileViewContentMetadata {
	return {
		itemId,
		path: props.path ?? `Sources/App/${itemId}.swift`,
		language: 'swift',
		cacheKey: `file-view:sha256:${itemId}`,
		sizeBytes: 128,
		contentHandle: `handle-${itemId}`,
		descriptorId: `descriptor-${itemId}`,
		contentHash: `sha256:${itemId}`,
		virtualizedExtentKind: 'exactLineCount',
		lineCount: 7,
		isBinary: props.isBinary ?? false,
		canFetchContent: props.canFetchContent ?? true,
	};
}
