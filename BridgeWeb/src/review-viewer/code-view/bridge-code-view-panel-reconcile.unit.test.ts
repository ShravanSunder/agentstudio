import type { CodeViewLineSelection, CodeViewScrollTarget } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	BridgeCodeViewController,
	type BridgeCodeViewModel,
	type ApplyBridgeCodeViewItemUpdateResult,
} from './bridge-code-view-controller.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import { materializeBridgeCodeViewLoadingItem } from './bridge-code-view-materialization.js';
import {
	bridgeCodeViewMetadataRequiresManifestReconciliation,
	planBridgeCodeViewManifestReconciliation,
	runBridgeCodeViewMetadataApplyInChunks,
	runBridgeCodeViewMetadataReconciliationInChunks,
} from './bridge-code-view-metadata-apply.js';
import {
	bridgeCodeViewInitialItemsWithWorkerPreparedCodeViewItems,
	createBridgeCodeViewInitialItemsForPanel,
	nextCodeViewItemForCollapse,
	reconcileBridgeCodeViewMetadataItems,
} from './bridge-code-view-panel-support.js';
import { createBridgeCodeViewMetadataDeltaItemsForPanel } from './bridge-code-view-worker-prepared-items.js';

describe('BridgeCodeViewPanel reconcile apply path', () => {
	test('replaces a retained selected-only model with the authoritative ordered manifest', () => {
		// Arrange
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const authoritativeItems = createBridgeCodeViewInitialItemsForPanel({
			projection,
			reviewPackage,
		});
		const selectedPlaceholder = authoritativeItems[1];
		if (selectedPlaceholder === undefined) {
			throw new Error('expected middle selected placeholder');
		}
		const hydratedSelectedItem: BridgeCodeViewItem = {
			...selectedPlaceholder,
			bridgeMetadata: {
				...selectedPlaceholder.bridgeMetadata,
				contentState: 'hydrated',
			},
			version: (selectedPlaceholder.version ?? 0) + 1,
		};
		const reconciledAuthoritativeItems = reconcileBridgeCodeViewMetadataItems({
			getCurrentItem: (itemId: string) =>
				itemId === hydratedSelectedItem.id ? hydratedSelectedItem : undefined,
			metadataItems: authoritativeItems,
		});

		// Act
		const plan = planBridgeCodeViewManifestReconciliation({
			authoritativeItems: reconciledAuthoritativeItems,
			currentItems: [hydratedSelectedItem],
			getCurrentItem: (itemId: string): BridgeCodeViewItem | undefined =>
				itemId === hydratedSelectedItem.id ? hydratedSelectedItem : undefined,
		});

		// Assert
		expect(plan.kind).toBe('replace');
		if (plan.kind !== 'replace') {
			throw new Error('expected authoritative replacement plan');
		}
		expect(plan.items.map((item) => item.id)).toEqual(projection.orderedItemIds);
		expect(plan.items[1]).toBe(hydratedSelectedItem);
	});

	test('applies retained selected-only recovery as one authoritative replacement', () => {
		// Arrange
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const authoritativeItems = createBridgeCodeViewInitialItemsForPanel({
			projection,
			reviewPackage,
		});
		const retainedSelectedItem = authoritativeItems[2];
		if (retainedSelectedItem === undefined) {
			throw new Error('expected retained middle selected item');
		}
		let currentItems: readonly BridgeCodeViewItem[] = [retainedSelectedItem];
		const appliedItemIds: string[] = [];
		const scheduledTurns: Array<() => void> = [];
		let completionCount = 0;
		let setItemsCount = 0;

		// Act
		runBridgeCodeViewMetadataReconciliationInChunks({
			applyItemUpdate: (item): void => {
				appliedItemIds.push(item.id);
			},
			currentItems,
			frameBudgetMilliseconds: 8,
			getCurrentItem: (itemId: string): BridgeCodeViewItem | undefined =>
				currentItems.find((item): boolean => item.id === itemId),
			isStale: (): boolean => false,
			isTaskStale: (): boolean => false,
			items: authoritativeItems,
			maxUnitsPerFrame: 8,
			noStarvationSelectedBatchLimit: 4,
			now: (): number => 0,
			onComplete: (): void => {
				completionCount += 1;
			},
			rankForItem: (): 'visible' => 'visible',
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
			setItems: (items): void => {
				setItemsCount += 1;
				currentItems = items;
			},
			staleScanLimit: 50,
		});
		flushScheduledTurns(scheduledTurns);

		// Assert
		expect(currentItems.map((item) => item.id)).toEqual(projection.orderedItemIds);
		expect(setItemsCount).toBe(1);
		expect(appliedItemIds).toEqual([]);
		expect(completionCount).toBe(1);
	});

	test('repairs a stale selected-only Pierre model when the tracked manifest already claims every item', () => {
		// Arrange: this is the long-lived/HMR failure shape. React retained the complete
		// intended manifest, while the live Pierre model still contains only the old selection.
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const authoritativeItems = createBridgeCodeViewInitialItemsForPanel({
			projection,
			reviewPackage,
		});
		const retainedSelectedItem = authoritativeItems[2];
		if (retainedSelectedItem === undefined) {
			throw new Error('expected retained selected item');
		}
		let livePierreItems: readonly BridgeCodeViewItem[] = [retainedSelectedItem];
		const scheduledTurns: Array<() => void> = [];
		let setItemsCount = 0;
		const reconciliationProps = {
			applyItemUpdate: (item: BridgeCodeViewItem): void => {
				const existingIndex = livePierreItems.findIndex(
					(currentItem): boolean => currentItem.id === item.id,
				);
				livePierreItems =
					existingIndex === -1
						? [...livePierreItems, item]
						: livePierreItems.with(existingIndex, item);
			},
			currentItems: authoritativeItems,
			frameBudgetMilliseconds: 8,
			getCurrentItem: (itemId: string): BridgeCodeViewItem | undefined =>
				livePierreItems.find((item): boolean => item.id === itemId),
			isStale: (): boolean => false,
			isTaskStale: (): boolean => false,
			items: authoritativeItems,
			maxUnitsPerFrame: 8,
			noStarvationSelectedBatchLimit: 4,
			now: (): number => 0,
			onComplete: (): void => {},
			rankForItem: (): 'visible' => 'visible',
			scheduleNextTurn: (callback: () => void): void => {
				scheduledTurns.push(callback);
			},
			setItems: (items: readonly BridgeCodeViewItem[]): void => {
				setItemsCount += 1;
				livePierreItems = items;
			},
			shouldSkipItem: (item: BridgeCodeViewItem): boolean =>
				livePierreItems.find((currentItem): boolean => currentItem.id === item.id) === item,
			staleScanLimit: 50,
		};

		// Act
		runBridgeCodeViewMetadataReconciliationInChunks(reconciliationProps);
		flushScheduledTurns(scheduledTurns);

		// Assert: missing public-model membership forces one ordered replacement instead of
		// appending each later clicked/visible item behind the retained selection.
		expect(setItemsCount).toBe(1);
		expect(livePierreItems.map((item): string => item.id)).toEqual(projection.orderedItemIds);
	});

	test('routes a same-manifest delta through authoritative reconciliation when Pierre lost that item', () => {
		// Arrange: React still owns the complete manifest, but Pierre retained only the old
		// selected item. The next visible/selected delta must repair membership, not append.
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const authoritativeItems = createBridgeCodeViewInitialItemsForPanel({
			projection,
			reviewPackage,
		});
		const retainedSelectedItem = authoritativeItems[0];
		const laterVisibleItem = authoritativeItems[2];
		if (retainedSelectedItem === undefined || laterVisibleItem === undefined) {
			throw new Error('expected retained and later visible Review items');
		}

		// Act
		const requiresManifestReconciliation = bridgeCodeViewMetadataRequiresManifestReconciliation({
			authoritativeIndexByItemId: indexBridgeCodeViewItemsById(authoritativeItems),
			authoritativeItemIds: authoritativeItems.map((item): string => item.id),
			getCurrentItem: (itemId: string): BridgeCodeViewItem | undefined =>
				itemId === retainedSelectedItem.id ? retainedSelectedItem : undefined,
			manifestChanged: false,
			metadataDeltaItems: [laterVisibleItem],
			sourceReset: false,
		});

		// Assert
		expect(
			requiresManifestReconciliation,
			'REVIEW_SAME_MANIFEST_APPEND: a missing live Pierre item must trigger one ordered manifest replacement before the delta can append.',
		).toBe(true);
	});

	test('routes an already-present selected delta through reconciliation when other manifest items are missing', () => {
		// Arrange: React tracks the complete authoritative order, while live Pierre retained only
		// the selected loading item. The next selected delta is present, but the document is not.
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const authoritativeItems = createBridgeCodeViewInitialItemsForPanel({
			projection,
			reviewPackage,
		});
		const retainedSelectedItem = authoritativeItems[2];
		if (retainedSelectedItem === undefined) {
			throw new Error('expected retained selected Review item');
		}

		// Act
		const requiresManifestReconciliation = bridgeCodeViewMetadataRequiresManifestReconciliation({
			authoritativeIndexByItemId: indexBridgeCodeViewItemsById(authoritativeItems),
			authoritativeItemIds: authoritativeItems.map((item): string => item.id),
			getCurrentItem: (itemId: string): BridgeCodeViewItem | undefined =>
				itemId === retainedSelectedItem.id ? retainedSelectedItem : undefined,
			manifestChanged: false,
			metadataDeltaItems: [retainedSelectedItem],
			sourceReset: false,
		});

		// Assert
		expect(
			requiresManifestReconciliation,
			'REVIEW_SAME_IDENTITY_SELECTED_DELTA: one present selected item cannot prove complete live membership.',
		).toBe(true);
	});

	test('keeps a complete ordered live manifest on the metadata-only apply path', () => {
		// Arrange
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const authoritativeItems = createBridgeCodeViewInitialItemsForPanel({
			projection,
			reviewPackage,
		});
		const selectedItem = authoritativeItems[1];
		if (selectedItem === undefined) {
			throw new Error('expected selected Review item');
		}
		const itemById = new Map(authoritativeItems.map((item) => [item.id, item]));
		const itemTopById = new Map(
			authoritativeItems.map((item, index): readonly [string, number] => [item.id, index * 100]),
		);

		// Act
		const requiresManifestReconciliation = bridgeCodeViewMetadataRequiresManifestReconciliation({
			authoritativeIndexByItemId: indexBridgeCodeViewItemsById(authoritativeItems),
			authoritativeItemIds: authoritativeItems.map((item): string => item.id),
			getCurrentItem: (itemId: string): BridgeCodeViewItem | undefined => itemById.get(itemId),
			getCurrentItemTop: (itemId: string): number | undefined => itemTopById.get(itemId),
			manifestChanged: false,
			metadataDeltaItems: [selectedItem],
			sourceReset: false,
		});

		// Assert
		expect(requiresManifestReconciliation).toBe(false);
	});

	test('replaces a complete live manifest whose public item geometry is out of order', () => {
		// Arrange
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const authoritativeItems = createBridgeCodeViewInitialItemsForPanel({
			projection,
			reviewPackage,
		});
		const selectedItem = authoritativeItems[1];
		if (selectedItem === undefined) {
			throw new Error('expected selected Review item');
		}
		const itemById = new Map(authoritativeItems.map((item) => [item.id, item]));
		const reversedItemTopById = new Map(
			authoritativeItems.map((item, index): readonly [string, number] => [
				item.id,
				(authoritativeItems.length - index) * 100,
			]),
		);

		// Act
		const requiresManifestReconciliation = bridgeCodeViewMetadataRequiresManifestReconciliation({
			authoritativeIndexByItemId: indexBridgeCodeViewItemsById(authoritativeItems),
			authoritativeItemIds: authoritativeItems.map((item): string => item.id),
			getCurrentItem: (itemId: string): BridgeCodeViewItem | undefined => itemById.get(itemId),
			getCurrentItemTop: (itemId: string): number | undefined => reversedItemTopById.get(itemId),
			manifestChanged: false,
			metadataDeltaItems: [selectedItem],
			sourceReset: false,
		});
		const plan = planBridgeCodeViewManifestReconciliation({
			authoritativeItems,
			currentItems: authoritativeItems,
			getCurrentItem: (itemId: string): BridgeCodeViewItem | undefined => itemById.get(itemId),
			getCurrentItemTop: (itemId: string): number | undefined => reversedItemTopById.get(itemId),
		});

		// Assert
		expect(requiresManifestReconciliation).toBe(true);
		expect(plan).toEqual({ items: authoritativeItems, kind: 'replace' });
	});

	test('recovers the complete manifest before applying selected loading without a presentation', () => {
		// Arrange: React still owns the complete authoritative manifest, while the live Pierre
		// model retained only the first item. This is the long-lived Review failure where clicking
		// another file enters selected loading before a presentation or prepared item exists.
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const authoritativeItems = createBridgeCodeViewInitialItemsForPanel({
			projection,
			reviewPackage,
		});
		const retainedItem = authoritativeItems[0];
		const selectedLoadingItem = authoritativeItems[2];
		if (retainedItem === undefined || selectedLoadingItem === undefined) {
			throw new Error('expected retained and selected loading Review items');
		}
		const metadataDeltaItems = createBridgeCodeViewMetadataDeltaItemsForPanel({
			reviewPackage,
			selectedCodeViewItem: null,
			selectedContentLoadingItemId: selectedLoadingItem.id,
			selectedItemId: selectedLoadingItem.id,
			selectedItemPresentation: null,
			visibleCodeViewItems: [],
		});

		// Act
		const requiresManifestReconciliation = bridgeCodeViewMetadataRequiresManifestReconciliation({
			authoritativeIndexByItemId: indexBridgeCodeViewItemsById(authoritativeItems),
			authoritativeItemIds: authoritativeItems.map((item): string => item.id),
			getCurrentItem: (itemId: string): BridgeCodeViewItem | undefined =>
				itemId === retainedItem.id ? retainedItem : undefined,
			manifestChanged: false,
			metadataDeltaItems,
			sourceReset: false,
		});

		// Assert: selected loading must enter the metadata reconciliation lane. Otherwise the
		// loading-only effect calls Pierre addItems and appends the clicked file behind the first.
		expect(metadataDeltaItems).toHaveLength(1);
		expect(metadataDeltaItems[0]?.id).toBe(selectedLoadingItem.id);
		expect(metadataDeltaItems[0]?.bridgeMetadata.contentState).toBe('loading');
		expect(
			requiresManifestReconciliation,
			'REVIEW_SELECTED_LOADING_APPEND: selected loading must recover authoritative membership before any item update can append.',
		).toBe(true);
	});

	test('does not classify a delta outside the authoritative projection as manifest drift', () => {
		// Arrange
		const outsideProjectionDescriptor = makeBridgeViewerProjectionFixture().itemsById['docs-plan'];
		if (outsideProjectionDescriptor === undefined) {
			throw new Error('expected outside-projection Review item');
		}
		const outsideProjectionItem = materializeBridgeCodeViewLoadingItem(outsideProjectionDescriptor);

		// Act
		const requiresManifestReconciliation = bridgeCodeViewMetadataRequiresManifestReconciliation({
			authoritativeIndexByItemId: new Map([['source-high', 0]]),
			authoritativeItemIds: ['source-high'],
			getCurrentItem: (): BridgeCodeViewItem | undefined => undefined,
			manifestChanged: false,
			metadataDeltaItems: [outsideProjectionItem],
			sourceReset: false,
		});

		// Assert
		expect(requiresManifestReconciliation).toBe(false);
	});

	test('keeps one healthy metadata delta bounded for a 3,420-item live manifest', () => {
		// Arrange
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const templateItem = createBridgeCodeViewInitialItemsForPanel({
			projection,
			reviewPackage,
		})[0];
		if (templateItem === undefined) {
			throw new Error('expected a template Review item');
		}
		const authoritativeItems = Array.from(
			{ length: 3_420 },
			(_, index): BridgeCodeViewItem => ({
				...templateItem,
				id: `bounded-manifest-${String(index).padStart(4, '0')}`,
			}),
		);
		const itemById = new Map(authoritativeItems.map((item) => [item.id, item]));
		const itemTopById = new Map(
			authoritativeItems.map((item, index): readonly [string, number] => [item.id, index * 100]),
		);
		const selectedItem = authoritativeItems[1_710];
		if (selectedItem === undefined) {
			throw new Error('expected a middle Review item');
		}
		let getCurrentItemCallCount = 0;
		let getCurrentItemTopCallCount = 0;

		// Act
		const requiresManifestReconciliation = bridgeCodeViewMetadataRequiresManifestReconciliation({
			authoritativeIndexByItemId: indexBridgeCodeViewItemsById(authoritativeItems),
			authoritativeItemIds: authoritativeItems.map((item): string => item.id),
			getCurrentItem: (itemId: string): BridgeCodeViewItem | undefined => {
				getCurrentItemCallCount += 1;
				return itemById.get(itemId);
			},
			getCurrentItemTop: (itemId: string): number | undefined => {
				getCurrentItemTopCallCount += 1;
				return itemTopById.get(itemId);
			},
			manifestChanged: false,
			metadataDeltaItems: [selectedItem],
			sourceReset: false,
		});

		// Assert
		expect(requiresManifestReconciliation).toBe(false);
		expect(getCurrentItemCallCount).toBeLessThanOrEqual(12);
		expect(getCurrentItemTopCallCount).toBeLessThanOrEqual(12);
	});

	test('forces one exact authoritative replacement when a retained policy epoch may contain extras', () => {
		// Arrange: public item lookup can prove known authoritative IDs but cannot enumerate an
		// unknown retained extra. Policy adoption therefore requires one exact setItems call.
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const authoritativeItems = createBridgeCodeViewInitialItemsForPanel({
			projection,
			reviewPackage,
		});
		const itemById = new Map(authoritativeItems.map((item) => [item.id, item]));

		// Act
		const reconciliationPlan = planBridgeCodeViewManifestReconciliation({
			authoritativeItems,
			currentItems: authoritativeItems,
			forceAuthoritativeReplacement: true,
			getCurrentItem: (itemId: string): BridgeCodeViewItem | undefined => itemById.get(itemId),
		});

		// Assert
		expect(reconciliationPlan).toEqual({ items: authoritativeItems, kind: 'replace' });
	});

	test('reconciles selected presentation loading deltas over hydrated selected item', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const currentSelectedItem = materializeBridgeCodeViewLoadingItem(sourceItem, {
			kind: 'file',
			version: 'base',
		});
		const hydratedSelectedItem: BridgeCodeViewItem = {
			...currentSelectedItem,
			bridgeMetadata: {
				...currentSelectedItem.bridgeMetadata,
				contentRoles: ['base'],
				contentState: 'hydrated',
			},
			version: (currentSelectedItem.version ?? 0) + 1,
		};
		const presentationDeltaItem = materializeBridgeCodeViewLoadingItem(sourceItem, {
			kind: 'file',
			version: 'head',
		});

		const reconciledItems = reconcileBridgeCodeViewMetadataItems({
			forceReplaceItemIds: [sourceItem.itemId],
			getCurrentItem: (itemId: string) =>
				itemId === sourceItem.itemId ? hydratedSelectedItem : undefined,
			metadataItems: [presentationDeltaItem],
			preserveItemIds: [sourceItem.itemId],
		});

		expect(reconciledItems).toHaveLength(1);
		expect(reconciledItems[0]).toMatchObject({
			id: sourceItem.itemId,
			type: 'file',
			bridgeMetadata: {
				contentRoles: [],
				contentState: 'loading',
			},
		});
		expect(reconciledItems[0]?.version).toBeGreaterThan(hydratedSelectedItem.version ?? 0);
	});

	test('does not preserve stale selected item during source reset reconciliation', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		const staleSelectedItem = reviewPackage.itemsById['docs-plan'];
		if (sourceItem === undefined || staleSelectedItem === undefined) {
			throw new Error('expected fixture items');
		}
		const sourceResetItem = materializeBridgeCodeViewLoadingItem(sourceItem);
		const oldSourceSelectedItem = {
			...materializeBridgeCodeViewLoadingItem(staleSelectedItem),
			bridgeMetadata: {
				...materializeBridgeCodeViewLoadingItem(staleSelectedItem).bridgeMetadata,
				contentState: 'hydrated' as const,
			},
		};

		const reconciledItems = reconcileBridgeCodeViewMetadataItems({
			getCurrentItem: (itemId: string) =>
				itemId === staleSelectedItem.itemId ? oldSourceSelectedItem : undefined,
			metadataItems: [sourceResetItem],
			preserveItemIds: [],
		});

		expect(reconciledItems.map((item) => item.id)).toEqual([sourceItem.itemId]);
	});

	test('paints worker-prepared visible content over expanded loading item', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const visibleItem = reviewPackage.itemsById['docs-plan'];
		if (visibleItem === undefined) {
			throw new Error('expected visible fixture item');
		}
		const visiblePlaceholderItem = materializeBridgeCodeViewLoadingItem(visibleItem);
		const visibleWorkerPreparedItem: BridgeCodeViewItem = {
			...visiblePlaceholderItem,
			bridgeMetadata: {
				...visiblePlaceholderItem.bridgeMetadata,
				contentState: 'hydrated',
			},
			version: (visiblePlaceholderItem.version ?? 0) + 1,
		};
		const visibleLoadingItem = nextCodeViewItemForCollapse({
			collapsed: false,
			currentItem: { ...visiblePlaceholderItem, collapsed: true },
			itemDescriptor: visibleItem,
		});
		const metadataItems = bridgeCodeViewInitialItemsWithWorkerPreparedCodeViewItems({
			initialItems: [visiblePlaceholderItem],
			selectedCodeViewItem: null,
			selectedItemId: 'source-high',
			visibleCodeViewItems: [visibleWorkerPreparedItem],
		});

		const expandedApply = applyMetadataWithCurrentItem({
			currentItem: visibleLoadingItem,
			itemId: visibleItem.itemId,
			metadataItems,
		});
		const collapsedApply = applyMetadataWithCurrentItem({
			currentItem: {
				...visibleLoadingItem,
				collapsed: true,
				version: visibleWorkerPreparedItem.version ?? 0,
			},
			itemId: visibleItem.itemId,
			metadataItems,
		});

		expect(expandedApply).toMatchObject({
			item: { bridgeMetadata: { contentState: 'hydrated' }, collapsed: false },
			result: 'updated',
		});
		expect(collapsedApply).toMatchObject({
			item: {
				bridgeMetadata: { contentState: 'hydrated' },
				collapsed: true,
				version: (visibleWorkerPreparedItem.version ?? 0) + 1,
			},
			result: 'updated',
		});
	});
});

function indexBridgeCodeViewItemsById(
	items: readonly BridgeCodeViewItem[],
): ReadonlyMap<string, number> {
	return new Map(items.map((item, index): readonly [string, number] => [item.id, index]));
}

function applyMetadataWithCurrentItem(props: {
	readonly currentItem: BridgeCodeViewItem;
	readonly itemId: string;
	readonly metadataItems: readonly BridgeCodeViewItem[];
}): {
	readonly item: BridgeCodeViewItem | undefined;
	readonly result: ApplyBridgeCodeViewItemUpdateResult | 'not-run';
} {
	const model = new VersionKeyedCodeViewModel();
	const controller = new BridgeCodeViewController({ model });
	let result: ApplyBridgeCodeViewItemUpdateResult | 'not-run' = 'not-run';
	model.addItems([props.currentItem]);
	const scheduledTurns: Array<() => void> = [];
	runBridgeCodeViewMetadataApplyInChunks({
		applyItemUpdate: (item): void => {
			result = controller.applyItemUpdate(item);
		},
		frameBudgetMilliseconds: 8,
		isStale: (): boolean => false,
		items: reconcileBridgeCodeViewMetadataItems({
			getCurrentItem: (itemId: string) => model.getItem(itemId),
			metadataItems: props.metadataItems,
		}),
		maxUnitsPerFrame: 50,
		noStarvationSelectedBatchLimit: 4,
		now: (): number => 0,
		onComplete: (): void => {},
		rankForItem: (): 'visible' => 'visible',
		scheduleNextTurn: (callback): void => {
			scheduledTurns.push(callback);
		},
		setItems: (items): void => {
			model.addItems(items);
		},
		staleScanLimit: 50,
	});
	flushScheduledTurns(scheduledTurns);
	return { item: model.getItem(props.itemId), result };
}

function flushScheduledTurns(scheduledTurns: Array<() => void>): void {
	for (let index = 0; index < 100 && scheduledTurns.length > 0; index += 1) {
		scheduledTurns.shift()?.();
	}
	if (scheduledTurns.length > 0) {
		throw new Error('expected metadata apply pump to drain');
	}
}

class VersionKeyedCodeViewModel implements BridgeCodeViewModel {
	readonly #itemsById = new Map<string, BridgeCodeViewItem>();

	addItems(items: readonly BridgeCodeViewItem[]): void {
		for (const item of items) {
			this.#itemsById.set(item.id, item);
		}
	}

	getItem(id: string): BridgeCodeViewItem | undefined {
		return this.#itemsById.get(id);
	}

	updateItem(item: BridgeCodeViewItem): boolean {
		const previousItem = this.#itemsById.get(item.id);
		this.#itemsById.set(item.id, item);
		return previousItem !== undefined && previousItem.version !== item.version;
	}

	updateItemId(): boolean {
		return true;
	}

	scrollTo(_target: CodeViewScrollTarget): void {}

	setSelectedLines(_selection: CodeViewLineSelection | null): void {}
}
