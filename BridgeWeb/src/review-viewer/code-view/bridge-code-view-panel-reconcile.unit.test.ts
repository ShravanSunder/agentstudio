import type { CodeViewLineSelection, CodeViewScrollTarget } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	BridgeCodeViewController,
	type BridgeCodeViewModel,
	type ApplyBridgeCodeViewItemUpdateResult,
} from './bridge-code-view-controller.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import { materializeBridgeCodeViewLoadingItem } from './bridge-code-view-materialization.js';
import { runBridgeCodeViewMetadataApplyInChunks } from './bridge-code-view-metadata-apply.js';
import {
	bridgeCodeViewInitialItemsWithWorkerPreparedCodeViewItems,
	nextCodeViewItemForCollapse,
	reconcileBridgeCodeViewMetadataItems,
} from './bridge-code-view-panel-support.js';

describe('BridgeCodeViewPanel reconcile apply path', () => {
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
		sourceReset: false,
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
