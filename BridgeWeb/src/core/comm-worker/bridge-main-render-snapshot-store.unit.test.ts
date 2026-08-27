import { describe, expect, test } from 'vitest';

import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainCodeViewItem,
} from './bridge-main-render-snapshot-store.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerReviewDisplayItem,
	type BridgeWorkerReviewDisplayPatchEvent,
} from './bridge-worker-contracts.js';
import { bridgeWorkerReviewSourceContext } from './bridge-worker-review-display.test-support.js';

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

	test('drops deleted CodeView items while keeping them across row-paint resets', () => {
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

		expect(store.getSnapshot().codeViewItemsById).toEqual({ 'item-1': item });
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

	test('applies batched record patches without mutating previous snapshots', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const firstItem = makeBridgeMainCodeViewItem('item-1');
		const secondItem = makeBridgeMainCodeViewItem('item-2');
		store.applySnapshotUpdate({
			codeViewItemPatches: [{ operation: 'upsert', itemId: 'item-1', item: firstItem }],
			workerPatches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { contentCacheKey: 'paint:item-1', status: 'ready' },
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'ready' },
				},
			],
		});
		const previousSnapshot = store.getSnapshot();

		store.applySnapshotUpdate({
			codeViewItemPatches: [
				{ operation: 'upsert', itemId: 'item-2', item: secondItem },
				{ operation: 'delete', itemId: 'item-1' },
			],
			workerPatches: [
				{
					slice: 'rowPaint',
					operation: 'upsert',
					itemId: 'item-2',
					payload: { contentCacheKey: 'paint:item-2', status: 'ready' },
				},
				{ slice: 'rowPaint', operation: 'delete', itemId: 'item-1' },
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-2',
					payload: { state: 'ready' },
				},
				{ slice: 'contentAvailability', operation: 'delete', itemId: 'item-1' },
			],
		});

		expect(previousSnapshot.codeViewItemsById).toEqual({ 'item-1': firstItem });
		expect(previousSnapshot.rowPaintById).toEqual({
			'item-1': { contentCacheKey: 'paint:item-1', status: 'ready' },
		});
		expect(previousSnapshot.contentAvailabilityById).toEqual({
			'item-1': { state: 'ready' },
		});
		const nextSnapshot = store.getSnapshot();
		expect(nextSnapshot.codeViewItemsById).toEqual({ 'item-2': secondItem });
		expect(nextSnapshot.rowPaintById).toEqual({
			'item-2': { contentCacheKey: 'paint:item-2', status: 'ready' },
		});
		expect(nextSnapshot.contentAvailabilityById).toEqual({
			'item-2': { state: 'ready' },
		});
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

	test('atomically applies bounded Review display state and rejects stale publications', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const event = makeReviewDisplayPatchEvent();
		let publishCount = 0;
		const unsubscribe = store.subscribe(() => {
			publishCount += 1;
		});

		store.applyReviewDisplayPatchEvent(event);

		const acceptedSnapshot = store.getSnapshot();
		expect(publishCount).toBe(1);
		expect(acceptedSnapshot.reviewDisplayFreshness).toEqual({
			epoch: 2,
			projectionRevision: 3,
			sequence: 5,
		});
		expect(acceptedSnapshot.reviewSourceSlice).toMatchObject({
			baseEndpoint: { endpointId: 'package-1-base' },
			headEndpoint: { endpointId: 'package-1-head' },
			metadataWindowIdentity: 'metadata-window-package-1-r11',
			query: { queryId: 'package-1-query' },
			status: 'loading',
		});
		expect(acceptedSnapshot.reviewItemIdsByIndex).toEqual(['item-1']);
		expect(acceptedSnapshot.reviewItemById['item-1']?.metadata.headPath).toBe('Sources/App.swift');
		expect(acceptedSnapshot.reviewTreeRowsByIndex).toMatchObject([
			{ itemId: 'item-1', path: 'Sources/App.swift', rowId: 'row-item-1' },
		]);

		for (const staleEvent of [
			{ ...event, epoch: 1, projectionRevision: 99, sequence: 99 },
			{ ...event, projectionRevision: event.projectionRevision, sequence: 6 },
			{ ...event, projectionRevision: 4, sequence: event.sequence },
		]) {
			store.applyReviewDisplayPatchEvent(staleEvent);
			expect(store.getSnapshot()).toBe(acceptedSnapshot);
		}

		store.applyReviewDisplayPatchEvent({
			...event,
			epoch: 3,
			patches: [
				{
					operation: 'failed',
					payload: { error: 'metadataUnavailable', status: 'failed' },
					slice: 'reviewSource',
				},
			],
			projectionRevision: 1,
			sequence: 6,
		});
		expect(store.getSnapshot()).toMatchObject({
			reviewDisplayFreshness: { epoch: 3, projectionRevision: 1, sequence: 6 },
			reviewItemById: {},
			reviewItemIdsByIndex: [],
			reviewSourceSlice: { error: 'metadataUnavailable', status: 'failed' },
			reviewTreeRowsByIndex: [],
		});

		unsubscribe();
	});

	test('preserves local Review selection when a catalog reset reintroduces the selected item', () => {
		// Arrange
		const store = createBridgeMainRenderSnapshotStore();
		const initialEvent = makeReviewDisplayPatchEvent();
		store.applyReviewDisplayPatchEvent(initialEvent);
		store.setLocalSelection({ selectedItemId: 'item-1', source: 'user' });

		// Act
		store.applyReviewDisplayPatchEvent({
			...initialEvent,
			projectionRevision: initialEvent.projectionRevision + 1,
			sequence: initialEvent.sequence + 1,
		});

		// Assert
		expect(store.getSnapshot().selectionSlice).toEqual({
			selectedItemId: 'item-1',
			source: 'user',
		});
	});

	test('preserves unchanged ready Review render copies while invalidating removed or semantically changed copies', () => {
		// Arrange
		const store = createBridgeMainRenderSnapshotStore();
		const initialEvent = makeReviewDisplayPatchEvent();
		const initialItemPatch = initialEvent.patches[1];
		if (initialItemPatch?.slice !== 'reviewItem' || initialItemPatch.operation !== 'batch') {
			throw new Error('expected Review fixture item batch');
		}
		const initialCatalogItem = initialItemPatch.payload.items[0];
		if (initialCatalogItem === undefined) {
			throw new Error('expected retained Review fixture item');
		}
		const retainedCatalogItem: BridgeWorkerReviewDisplayItem = {
			...initialCatalogItem,
			contentFacts: [
				{
					contentDigest: {
						algorithm: 'sha256',
						authority: 'authoritative',
						value: 'a'.repeat(64),
					},
					role: 'file',
					semanticDocumentRevision: 'semantic-item-1',
				},
			],
			metadata: {
				...initialCatalogItem.metadata,
				contentDescriptorIdsByRole: { file: 'descriptor-item-1-a' },
				contentRoles: ['file'],
			},
		};
		const removedCatalogItem: BridgeWorkerReviewDisplayItem = {
			...retainedCatalogItem,
			metadata: {
				...retainedCatalogItem.metadata,
				basePath: 'Sources/Removed.swift',
				headPath: 'Sources/Removed.swift',
				itemId: 'item-removed',
			},
			metadataWindowIdentity: 'metadata-window-item-removed-r11',
		};
		store.applyReviewDisplayPatchEvent({
			...initialEvent,
			patches: [
				{
					...initialItemPatch,
					payload: {
						...initialItemPatch.payload,
						items: [retainedCatalogItem, removedCatalogItem],
					},
				},
			],
		});
		const retainedCodeViewItem: BridgeMainCodeViewItem = {
			...makeBridgeMainCodeViewItem('item-1'),
			bridgeMetadata: {
				...makeBridgeMainCodeViewItem('item-1').bridgeMetadata,
				sourceDescriptorIdsByRole: {
					base: null,
					diff: null,
					file: 'descriptor-item-1-a',
					head: null,
				},
			},
		};
		const removedCodeViewItem = makeBridgeMainCodeViewItem('item-removed');
		const retainedRowPaint = {
			contentCacheKey: 'pierre-content:item-1',
			status: 'ready',
		};
		store.applySnapshotUpdate({
			codeViewItemPatches: [
				{ operation: 'upsert', itemId: 'item-1', item: retainedCodeViewItem },
				{ operation: 'upsert', itemId: 'item-removed', item: removedCodeViewItem },
			],
			workerPatches: [
				{
					itemId: 'item-1',
					operation: 'upsert',
					payload: retainedRowPaint,
					slice: 'rowPaint',
				},
				{
					itemId: 'item-1',
					operation: 'upsert',
					payload: { state: 'ready' },
					slice: 'contentAvailability',
				},
				{
					itemId: 'item-removed',
					operation: 'upsert',
					payload: { contentCacheKey: 'pierre-content:item-removed', status: 'ready' },
					slice: 'rowPaint',
				},
				{
					itemId: 'item-removed',
					operation: 'upsert',
					payload: { state: 'ready' },
					slice: 'contentAvailability',
				},
			],
		});
		const addedCatalogItem: BridgeWorkerReviewDisplayItem = {
			...retainedCatalogItem,
			metadata: {
				...retainedCatalogItem.metadata,
				basePath: 'Sources/Added.swift',
				headPath: 'Sources/Added.swift',
				itemId: 'item-added',
			},
			metadataWindowIdentity: 'metadata-window-item-added-r12',
		};
		const changedRetainedCatalogItem: BridgeWorkerReviewDisplayItem = {
			...retainedCatalogItem,
			contentFacts: [
				{
					contentDigest: {
						algorithm: 'sha256',
						authority: 'authoritative',
						value: 'b'.repeat(64),
					},
					role: 'file',
					semanticDocumentRevision: 'semantic-item-1-changed',
				},
			],
		};

		// Act
		store.applyReviewDisplayPatchEvent({
			...initialEvent,
			patches: [
				{
					...initialItemPatch,
					payload: {
						...initialItemPatch.payload,
						items: [retainedCatalogItem, addedCatalogItem],
					},
				},
			],
			projectionRevision: initialEvent.projectionRevision + 1,
			sequence: initialEvent.sequence + 1,
		});

		// Assert
		const snapshot = store.getSnapshot();
		expect(snapshot.reviewItemIdsByIndex).toEqual(['item-1', 'item-added']);
		expect(snapshot.codeViewItemsById['item-1']).toBe(retainedCodeViewItem);
		expect(snapshot.contentAvailabilityById['item-1']).toEqual({ state: 'ready' });
		expect(snapshot.rowPaintById['item-1']).toEqual(retainedRowPaint);
		expect(snapshot.codeViewItemsById['item-removed']).toBeUndefined();
		expect(snapshot.contentAvailabilityById['item-removed']).toBeUndefined();
		expect(snapshot.rowPaintById['item-removed']).toBeUndefined();

		// Act: identical content retained under a successor descriptor must carry successor
		// source authority before a newly opened annotation composer captures its origin.
		const successorDescriptorCatalogItem: BridgeWorkerReviewDisplayItem = {
			...retainedCatalogItem,
			metadata: {
				...retainedCatalogItem.metadata,
				contentDescriptorIdsByRole: { file: 'descriptor-item-1-b' },
			},
			metadataWindowIdentity: 'metadata-window-item-1-successor-r13',
		};
		store.applyReviewDisplayPatchEvent({
			...initialEvent,
			patches: [
				{
					...initialItemPatch,
					payload: {
						...initialItemPatch.payload,
						items: [successorDescriptorCatalogItem, addedCatalogItem],
					},
				},
			],
			projectionRevision: initialEvent.projectionRevision + 2,
			sequence: initialEvent.sequence + 2,
		});

		// Assert
		const successorDescriptorCodeViewItem = store.getSnapshot().codeViewItemsById['item-1'];
		expect(successorDescriptorCodeViewItem).not.toBe(retainedCodeViewItem);
		expect(successorDescriptorCodeViewItem?.bridgeMetadata.sourceDescriptorIdsByRole).toEqual({
			base: null,
			diff: null,
			file: 'descriptor-item-1-b',
			head: null,
		});

		// Act: unchanged complete content is retained while its same-epoch display path changes.
		const renamedRetainedCatalogItem: BridgeWorkerReviewDisplayItem = {
			...retainedCatalogItem,
			metadata: {
				...retainedCatalogItem.metadata,
				basePath: 'Sources/Renamed.swift',
				headPath: 'Sources/Renamed.swift',
			},
			metadataWindowIdentity: 'metadata-window-item-1-renamed-r13',
		};
		store.applyReviewDisplayPatchEvent({
			...initialEvent,
			patches: [
				{
					...initialItemPatch,
					payload: {
						...initialItemPatch.payload,
						items: [renamedRetainedCatalogItem, addedCatalogItem],
					},
				},
			],
			projectionRevision: initialEvent.projectionRevision + 3,
			sequence: initialEvent.sequence + 3,
		});

		// Assert
		const renamedSnapshot = store.getSnapshot();
		const renamedCodeViewItem = renamedSnapshot.codeViewItemsById['item-1'];
		expect(renamedCodeViewItem).not.toBe(retainedCodeViewItem);
		expect(renamedCodeViewItem).toMatchObject({
			bridgeMetadata: {
				contentState: 'hydrated',
				displayPath: 'Sources/Renamed.swift',
			},
			file: {
				contents: retainedCodeViewItem.type === 'file' ? retainedCodeViewItem.file.contents : '',
				name: 'Sources/Renamed.swift',
			},
			type: 'file',
		});
		expect(renamedCodeViewItem?.version).toBeGreaterThan(retainedCodeViewItem.version ?? 0);
		expect(renamedSnapshot.contentAvailabilityById['item-1']).toEqual({ state: 'ready' });
		expect(renamedSnapshot.rowPaintById['item-1']).toEqual(retainedRowPaint);

		// Act: the same catalog identity now names different authoritative content.
		store.applyReviewDisplayPatchEvent({
			...initialEvent,
			patches: [
				{
					...initialItemPatch,
					payload: {
						...initialItemPatch.payload,
						items: [
							{
								...changedRetainedCatalogItem,
								metadata: renamedRetainedCatalogItem.metadata,
							},
							addedCatalogItem,
						],
					},
				},
			],
			projectionRevision: initialEvent.projectionRevision + 4,
			sequence: initialEvent.sequence + 4,
		});

		// Assert
		expect(store.getSnapshot().codeViewItemsById['item-1']).toBeUndefined();
		expect(store.getSnapshot().contentAvailabilityById['item-1']).toBeUndefined();
		expect(store.getSnapshot().rowPaintById['item-1']).toBeUndefined();
	});
});

function makeReviewDisplayPatchEvent(): BridgeWorkerReviewDisplayPatchEvent {
	return {
		direction: 'serverWorkerToMain',
		epoch: 2,
		kind: 'reviewDisplayPatch',
		reviewPublicationIdentity: null,
		patches: [
			{
				operation: 'upsert',
				payload: {
					...bridgeWorkerReviewSourceContext('package-1'),
					metadataSourceId: 'review-source-package-1',
					metadataWindowIdentity: 'metadata-window-package-1-r11',
					packageId: 'package-1',
					reviewGeneration: 1,
					revision: 11,
					status: 'loading',
					summary: null,
					totalItemCount: 1,
					totalTreeRowCount: 1,
				},
				slice: 'reviewSource',
			},
			{
				operation: 'batch',
				payload: {
					items: [
						{
							contentFacts: [],
							extentFacts: [],
							metadata: {
								additions: 1,
								deletions: 1,
								basePath: 'Sources/App.swift',
								changeKind: 'modified',
								contentDescriptorIdsByRole: {},
								contentHashesByRole: {},
								contentRoles: [],
								extension: 'swift',
								fileClass: 'source',
								headPath: 'Sources/App.swift',
								isHiddenByDefault: false,
								itemId: 'item-1',
								language: 'swift',
								mimeTypes: ['text/plain'],
								provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
								reviewPriority: 'normal',
								reviewState: 'unreviewed',
							},
							metadataWindowIdentity: 'metadata-window-item-1-r11',
						},
					],
					operations: [],
					reset: true,
					startIndex: 0,
				},
				slice: 'reviewItem',
			},
			{
				operation: 'batch',
				payload: {
					reset: true,
					windows: [
						{
							rows: [
								{
									depth: 1,
									isDirectory: false,
									itemId: 'item-1',
									path: 'Sources/App.swift',
									rowId: 'row-item-1',
								},
							],
							startIndex: 0,
						},
					],
				},
				slice: 'reviewTree',
			},
		],
		projectionRevision: 3,
		sequence: 5,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
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
