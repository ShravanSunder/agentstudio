import { describe, expect, test } from 'vitest';

import type {
	BridgeMainReviewCatalogChange,
	BridgeMainReviewCatalogSnapshot,
	BridgeMainReviewSourceDisplaySlice,
	BridgeMainReviewTreeDisplayRow,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgeWorkerReviewDisplayItem } from '../core/comm-worker/bridge-worker-contracts.js';
import { bridgeReviewPresentationSnapshotForDisplay } from './bridge-app-review-presentation-adapter.js';
import type { BridgeReviewDirectDisplayStore } from './bridge-app-review-render-snapshot-controller.js';

describe('Bridge Review presentation adapter', () => {
	test('projects a ready worker display into a correlated recovered-shell snapshot', () => {
		// Arrange
		const displayItem = reviewDisplayItem('item-source', 'Sources/App/Feature.swift');
		const rawTreeRows: readonly BridgeMainReviewTreeDisplayRow[] = [
			{
				depth: 0,
				isDirectory: true,
				itemId: null,
				path: 'Sources/App',
				rowId: 'row-directory',
			},
			{
				depth: 1,
				isDirectory: false,
				itemId: 'item-source',
				path: 'Sources/App/Feature.swift',
				rowId: 'row-item-source',
			},
		];

		// Act
		const presentationSnapshot = bridgeReviewPresentationSnapshotForDisplay({
			catalogSnapshot: catalogSnapshot({ itemCount: 1, revision: 7, treeRowCount: 2 }),
			displayStore: displayStore({ items: [displayItem], rawTreeRows }),
			reviewSourceSlice: readyReviewSourceSlice({ itemCount: 1, treeRowCount: 2 }),
		});

		// Assert
		expect(presentationSnapshot).not.toBeNull();
		expect(presentationSnapshot?.reviewTreeRows).toEqual([
			{
				depth: 0,
				isDirectory: true,
				path: 'Sources/App',
				rowId: 'row-directory',
			},
			{
				depth: 1,
				isDirectory: false,
				itemId: 'item-source',
				path: 'Sources/App/Feature.swift',
				rowId: 'row-item-source',
			},
		]);
		expect(presentationSnapshot?.reviewPackage.orderedItemIds).toEqual(['item-source']);
		expect(Object.keys(presentationSnapshot?.reviewPackage.itemsById ?? {})).toEqual([
			'item-source',
		]);
		expect(presentationSnapshot?.projection).toMatchObject({
			candidatePathsByItemId: {
				'item-source': ['Sources/App/Feature.swift'],
			},
			itemIdsByDisplayPath: {
				'Sources/App/Feature.swift': ['item-source'],
			},
			orderedItemIds: ['item-source'],
			orderedPaths: ['Sources/App', 'Sources/App/Feature.swift'],
			primaryDisplayPathByItemId: {
				'item-source': 'Sources/App/Feature.swift',
			},
			primaryItemIdByTreePath: {
				'Sources/App/Feature.swift': 'item-source',
			},
		});
		expect(presentationSnapshot?.projection.projectionId).toBe(
			presentationSnapshot?.presentationKey,
		);
		expect(presentationSnapshot?.reviewPackage.packageId).toBe(
			presentationSnapshot?.presentationKey,
		);
	});

	test.each([
		['absent', null],
		[
			'loading',
			{
				metadataWindowIdentity: 'review-window-loading',
				status: 'loading',
				summary: null,
				totalItemCount: null,
				totalTreeRowCount: null,
			},
		],
		['failed', { error: 'metadataUnavailable', status: 'failed' }],
	] satisfies readonly (
		| readonly ['absent', null]
		| readonly ['loading' | 'failed', BridgeMainReviewSourceDisplaySlice]
	)[])(
		'returns no recovered-shell snapshot for a %s display source',
		(_name, reviewSourceSlice) => {
			// Arrange
			const item = reviewDisplayItem('item-source', 'Sources/App/Feature.swift');

			// Act
			const presentationSnapshot = bridgeReviewPresentationSnapshotForDisplay({
				catalogSnapshot: catalogSnapshot({ itemCount: 1, revision: 1, treeRowCount: 1 }),
				displayStore: displayStore({
					items: [item],
					rawTreeRows: [
						{
							depth: 0,
							isDirectory: false,
							itemId: item.metadata.itemId,
							path: item.metadata.headPath ?? item.metadata.itemId,
							rowId: 'row-item-source',
						},
					],
				}),
				reviewSourceSlice,
			});

			// Assert
			expect(presentationSnapshot).toBeNull();
		},
	);

	test('returns no recovered-shell snapshot for a ready but empty display', () => {
		// Arrange / Act
		const presentationSnapshot = bridgeReviewPresentationSnapshotForDisplay({
			catalogSnapshot: catalogSnapshot({ itemCount: 0, revision: 1, treeRowCount: 0 }),
			displayStore: displayStore({ items: [], rawTreeRows: [] }),
			reviewSourceSlice: readyReviewSourceSlice({ itemCount: 0, treeRowCount: 0 }),
		});

		// Assert
		expect(presentationSnapshot).toBeNull();
	});

	test('propagates the worker catalog epoch as the Review reset generation', () => {
		// Arrange
		const item = reviewDisplayItem('item-source', 'Sources/App/Feature.swift');
		const rawTreeRows: readonly BridgeMainReviewTreeDisplayRow[] = [
			{
				depth: 0,
				isDirectory: false,
				itemId: item.metadata.itemId,
				path: item.metadata.headPath ?? item.metadata.itemId,
				rowId: 'row-item-source',
			},
		];
		const store = displayStore({ items: [item], rawTreeRows });

		// Act
		const firstEpochPresentation = bridgeReviewPresentationSnapshotForDisplay({
			catalogSnapshot: catalogSnapshot({
				epoch: 7,
				itemCount: 1,
				revision: 1,
				treeRowCount: 1,
			}),
			displayStore: store,
			reviewSourceSlice: readyReviewSourceSlice({ itemCount: 1, treeRowCount: 1 }),
		});
		const secondEpochPresentation = bridgeReviewPresentationSnapshotForDisplay({
			catalogSnapshot: catalogSnapshot({
				epoch: 8,
				itemCount: 1,
				revision: 1,
				treeRowCount: 1,
			}),
			displayStore: store,
			reviewSourceSlice: readyReviewSourceSlice({ itemCount: 1, treeRowCount: 1 }),
		});

		// Assert
		expect(firstEpochPresentation?.reviewPackage.reviewGeneration).toBe(7);
		expect(secondEpochPresentation?.reviewPackage.reviewGeneration).toBe(8);
		expect(secondEpochPresentation?.presentationKey).not.toBe(
			firstEpochPresentation?.presentationKey,
		);
	});

	test('keeps presentation identity across same-epoch resets and rotates it for a new epoch', () => {
		// Arrange
		const item = reviewDisplayItem(reviewItemId(0), 'Sources/App/Feature.swift');
		const items = [item];
		const rawTreeRows: BridgeMainReviewTreeDisplayRow[] = [
			{
				depth: 0,
				isDirectory: false,
				itemId: item.metadata.itemId,
				path: item.metadata.headPath ?? item.metadata.itemId,
				rowId: 'row-item-source',
			},
		];
		const changesByCursor = new Map<number, readonly BridgeMainReviewCatalogChange[]>([
			[
				1,
				[
					{
						cursor: 2,
						itemIds: [item.metadata.itemId],
						itemOrderMutations: [{ kind: 'replace', length: 1 }],
						reset: true,
						treeRowIds: ['row-item-source'],
						treeRowOrderMutations: [{ kind: 'replace', length: 1 }],
					},
				],
			],
		]);
		const store = instrumentedDisplayStore({
			accessCounts: { itemAtIndex: 0, itemById: 0, treeRowAtIndex: 0 },
			changesByCursor,
			items,
			rawTreeRows,
		});

		// Act
		const initialPresentation = bridgeReviewPresentationSnapshotForDisplay({
			catalogSnapshot: {
				changeCursor: 1,
				epoch: 7,
				itemOrderLength: 1,
				revision: 1,
				treeRowOrderLength: 1,
			},
			displayStore: store,
			reviewSourceSlice: readyReviewSourceSlice({
				itemCount: 1,
				metadataWindowIdentity: 'review-window-source-revision-1',
				treeRowCount: 1,
			}),
		});
		const sameEpochResetPresentation = bridgeReviewPresentationSnapshotForDisplay({
			catalogSnapshot: {
				changeCursor: 2,
				epoch: 7,
				itemOrderLength: 1,
				revision: 2,
				treeRowOrderLength: 1,
			},
			displayStore: store,
			reviewSourceSlice: readyReviewSourceSlice({
				itemCount: 1,
				metadataWindowIdentity: 'review-window-source-revision-2',
				treeRowCount: 1,
			}),
		});
		const nextEpochPresentation = bridgeReviewPresentationSnapshotForDisplay({
			catalogSnapshot: {
				changeCursor: 3,
				epoch: 8,
				itemOrderLength: 1,
				revision: 1,
				treeRowOrderLength: 1,
			},
			displayStore: store,
			reviewSourceSlice: readyReviewSourceSlice({
				itemCount: 1,
				metadataWindowIdentity: 'review-window-source-revision-2',
				treeRowCount: 1,
			}),
		});

		// Assert
		expect(sameEpochResetPresentation?.presentationKey).toBe(initialPresentation?.presentationKey);
		expect(nextEpochPresentation?.presentationKey).not.toBe(
			sameEpochResetPresentation?.presentationKey,
		);
	});

	test('keeps presentation identity stable and reads only a bounded appended catalog window', () => {
		// Arrange
		const initialItemCount = 4_096;
		const appendedItemCount = 64;
		const items = Array.from({ length: initialItemCount }, (_, itemIndex) =>
			reviewDisplayItem(reviewItemId(itemIndex), `Sources/File-${itemIndex}.swift`),
		);
		const rawTreeRows = items.map(
			(item, itemIndex): BridgeMainReviewTreeDisplayRow => ({
				depth: 0,
				isDirectory: false,
				itemId: item.metadata.itemId,
				path: item.metadata.headPath ?? item.metadata.itemId,
				rowId: `row-${itemIndex}`,
			}),
		);
		const accessCounts = { itemAtIndex: 0, itemById: 0, treeRowAtIndex: 0 };
		const changesByCursor = new Map<number, readonly BridgeMainReviewCatalogChange[]>();
		const store = instrumentedDisplayStore({ accessCounts, changesByCursor, items, rawTreeRows });
		const initialCatalogSnapshot = incrementalCatalogSnapshot({
			changeCursor: 1,
			itemCount: initialItemCount,
			revision: 1,
			treeRowCount: initialItemCount,
		});

		// Act: the initial/reset build may read the complete catalog.
		const initialPresentation = bridgeReviewPresentationSnapshotForDisplay({
			catalogSnapshot: initialCatalogSnapshot,
			displayStore: store,
			reviewSourceSlice: readyReviewSourceSlice({
				itemCount: initialItemCount,
				metadataWindowIdentity: 'review-window-source-revision-1',
				treeRowCount: initialItemCount,
			}),
		});
		expect(initialPresentation).not.toBeNull();
		accessCounts.itemAtIndex = 0;
		accessCounts.itemById = 0;
		accessCounts.treeRowAtIndex = 0;
		const appendedItems = Array.from({ length: appendedItemCount }, (_, itemOffset) => {
			const itemIndex = initialItemCount + itemOffset;
			return reviewDisplayItem(reviewItemId(itemIndex), `Sources/File-${itemIndex}.swift`);
		});
		const appendedRows = appendedItems.map(
			(item, itemOffset): BridgeMainReviewTreeDisplayRow => ({
				depth: 0,
				isDirectory: false,
				itemId: item.metadata.itemId,
				path: item.metadata.headPath ?? item.metadata.itemId,
				rowId: `row-${initialItemCount + itemOffset}`,
			}),
		);
		items.push(...appendedItems);
		rawTreeRows.push(...appendedRows);
		changesByCursor.set(1, [
			{
				cursor: 2,
				itemIds: appendedItems.map((item) => item.metadata.itemId),
				itemOrderMutations: [
					{ kind: 'setRange', length: appendedItemCount, startIndex: initialItemCount },
				],
				reset: false,
				treeRowIds: appendedRows.map((row) => row.rowId),
				treeRowOrderMutations: [
					{ kind: 'setRange', length: appendedItemCount, startIndex: initialItemCount },
				],
			},
		]);
		const appendedPresentation = bridgeReviewPresentationSnapshotForDisplay({
			catalogSnapshot: incrementalCatalogSnapshot({
				changeCursor: 2,
				itemCount: initialItemCount + appendedItemCount,
				revision: 2,
				treeRowCount: initialItemCount + appendedItemCount,
			}),
			displayStore: store,
			reviewSourceSlice: readyReviewSourceSlice({
				itemCount: initialItemCount + appendedItemCount,
				metadataWindowIdentity: 'review-window-source-revision-2',
				treeRowCount: initialItemCount + appendedItemCount,
			}),
		});

		// Assert
		expect(appendedPresentation?.presentationKey).toBe(initialPresentation?.presentationKey);
		expect(appendedPresentation?.projection.projectionId).toBe(
			initialPresentation?.projection.projectionId,
		);
		expect(appendedPresentation?.reviewPackage.packageId).toBe(
			initialPresentation?.reviewPackage.packageId,
		);
		expect(appendedPresentation?.reviewPackage.orderedItemIds).toHaveLength(
			initialItemCount + appendedItemCount,
		);
		expect(accessCounts).toEqual({
			itemAtIndex: appendedItemCount,
			itemById: appendedItemCount,
			treeRowAtIndex: appendedItemCount,
		});
	});
});

function catalogSnapshot(props: {
	readonly epoch?: number;
	readonly itemCount: number;
	readonly revision: number;
	readonly treeRowCount: number;
}): BridgeMainReviewCatalogSnapshot {
	return {
		changeCursor: 0,
		epoch: props.epoch ?? 1,
		itemOrderLength: props.itemCount,
		revision: props.revision,
		treeRowOrderLength: props.treeRowCount,
	};
}

function displayStore(props: {
	readonly items: readonly BridgeWorkerReviewDisplayItem[];
	readonly rawTreeRows: readonly BridgeMainReviewTreeDisplayRow[];
}): BridgeReviewDirectDisplayStore {
	const itemsById = new Map(props.items.map((item) => [item.metadata.itemId, item]));
	const rowsById = new Map(props.rawTreeRows.map((row) => [row.rowId, row]));
	return {
		getReviewItemIdAtIndex: (itemIndex): string | undefined =>
			props.items[itemIndex]?.metadata.itemId,
		getReviewCodeViewItemSnapshot: (): undefined => undefined,
		getReviewItemSnapshot: (itemId): BridgeWorkerReviewDisplayItem | undefined =>
			itemsById.get(itemId),
		getReviewTreeRowAtIndex: (treeRowIndex): BridgeMainReviewTreeDisplayRow | undefined =>
			props.rawTreeRows[treeRowIndex],
		getReviewTreeRowSnapshot: (rowId): BridgeMainReviewTreeDisplayRow | undefined =>
			rowsById.get(rowId),
		readReviewCatalogChangesAfter: (): {
			readonly changes: readonly BridgeMainReviewCatalogChange[];
			readonly resetRequired: boolean;
		} => ({ changes: [], resetRequired: false }),
		reviewCatalogContainsItem: (itemId): boolean => itemsById.has(itemId),
		subscribeReviewItem: (): (() => void) => (): void => {},
		subscribeReviewCodeViewItem: (): (() => void) => (): void => {},
		subscribeReviewTreeRow: (): (() => void) => (): void => {},
	};
}

function readyReviewSourceSlice(props: {
	readonly itemCount: number;
	readonly metadataWindowIdentity?: string;
	readonly treeRowCount: number;
}): BridgeMainReviewSourceDisplaySlice {
	return {
		metadataWindowIdentity: props.metadataWindowIdentity ?? 'review-window-ready',
		status: 'ready',
		summary: {
			additions: 1,
			deletions: 0,
			filesChanged: props.itemCount,
			hiddenFileCount: 0,
			visibleFileCount: props.itemCount,
		},
		totalItemCount: props.itemCount,
		totalTreeRowCount: props.treeRowCount,
	};
}

function incrementalCatalogSnapshot(props: {
	readonly changeCursor: number;
	readonly itemCount: number;
	readonly revision: number;
	readonly treeRowCount: number;
}): BridgeMainReviewCatalogSnapshot {
	return {
		changeCursor: props.changeCursor,
		epoch: 1,
		itemOrderLength: props.itemCount,
		revision: props.revision,
		treeRowOrderLength: props.treeRowCount,
	};
}

function instrumentedDisplayStore(props: {
	readonly accessCounts: { itemAtIndex: number; itemById: number; treeRowAtIndex: number };
	readonly changesByCursor: ReadonlyMap<number, readonly BridgeMainReviewCatalogChange[]>;
	readonly items: readonly BridgeWorkerReviewDisplayItem[];
	readonly rawTreeRows: readonly BridgeMainReviewTreeDisplayRow[];
}): BridgeReviewDirectDisplayStore {
	const itemAtIndex = (itemIndex: number): BridgeWorkerReviewDisplayItem | undefined =>
		props.items[itemIndex];
	const itemForId = (itemId: string): BridgeWorkerReviewDisplayItem | undefined => {
		const itemIndex = Number.parseInt(itemId.slice('item-'.length), 10);
		const item = Number.isNaN(itemIndex) ? undefined : itemAtIndex(itemIndex);
		return item?.metadata.itemId === itemId ? item : undefined;
	};
	const store = {
		getReviewItemIdAtIndex: (itemIndex: number): string | undefined => {
			props.accessCounts.itemAtIndex += 1;
			return itemAtIndex(itemIndex)?.metadata.itemId;
		},
		getReviewItemSnapshot: (itemId: string): BridgeWorkerReviewDisplayItem | undefined => {
			props.accessCounts.itemById += 1;
			return itemForId(itemId);
		},
		getReviewCodeViewItemSnapshot: (): undefined => undefined,
		getReviewTreeRowAtIndex: (treeRowIndex: number): BridgeMainReviewTreeDisplayRow | undefined => {
			props.accessCounts.treeRowAtIndex += 1;
			return props.rawTreeRows[treeRowIndex];
		},
		getReviewTreeRowSnapshot: (rowId: string): BridgeMainReviewTreeDisplayRow | undefined =>
			props.rawTreeRows.find((row) => row.rowId === rowId),
		readReviewCatalogChangesAfter: (cursor: number) => ({
			changes: props.changesByCursor.get(cursor) ?? [],
			resetRequired: false,
		}),
		reviewCatalogContainsItem: (itemId: string): boolean => itemForId(itemId) !== undefined,
		subscribeReviewItem: (): (() => void) => (): void => {},
		subscribeReviewCodeViewItem: (): (() => void) => (): void => {},
		subscribeReviewTreeRow: (): (() => void) => (): void => {},
	};
	return store;
}

function reviewItemId(itemIndex: number): string {
	return `item-${itemIndex.toString().padStart(4, '0')}`;
}

function reviewDisplayItem(itemId: string, path: string): BridgeWorkerReviewDisplayItem {
	return {
		contentFacts: [],
		extentFacts: [],
		metadata: {
			basePath: path,
			changeKind: 'modified',
			contentDescriptorIdsByRole: {},
			contentHashesByRole: {},
			contentRoles: [],
			extension: 'swift',
			fileClass: 'source',
			headPath: path,
			isHiddenByDefault: false,
			itemId,
			language: 'swift',
			mimeTypes: ['text/plain'],
			provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
			reviewPriority: 'normal',
			reviewState: 'unreviewed',
		},
		metadataWindowIdentity: `review-window-${itemId}`,
	};
}
