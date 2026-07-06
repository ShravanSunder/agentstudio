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
import { applyBridgeCodeViewMetadataItems } from './bridge-code-view-metadata-apply.js';
import {
	bridgeCodeViewInitialItemsWithWorkerPreparedCodeViewItems,
	nextCodeViewItemForCollapse,
	reconcileBridgeCodeViewMetadataItems,
} from './bridge-code-view-panel-support.js';

describe('BridgeCodeViewPanel reconcile apply path', () => {
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
	applyBridgeCodeViewMetadataItems({
		applyItemUpdate: (item): void => {
			result = controller.applyItemUpdate(item);
		},
		getCurrentItem: (itemId: string) => model.getItem(itemId),
		items: reconcileBridgeCodeViewMetadataItems({
			getCurrentItem: (itemId: string) => model.getItem(itemId),
			metadataItems: props.metadataItems,
		}),
		setItems: (items): void => {
			model.addItems(items);
		},
		sourceReset: false,
	});
	return { item: model.getItem(props.itemId), result };
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
