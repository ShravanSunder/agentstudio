import { describe, expect, test } from 'vitest';

import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import { materializeBridgeCodeViewLoadingItem } from './bridge-code-view-materialization.js';
import { createBridgeCodeViewMetadataDeltaItemsForPanelSelector } from './bridge-code-view-worker-prepared-items.js';

describe('Bridge CodeView worker-prepared item selector', () => {
	test('keeps metadata deltas stable across selected worker item payload clones', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		const visibleItem = reviewPackage.itemsById['docs-plan'];
		if (sourceItem === undefined || visibleItem === undefined) {
			throw new Error('expected projection fixture items');
		}
		const selectedCodeViewItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(sourceItem),
		);
		const visibleCodeViewItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(visibleItem),
		);
		const selector = createBridgeCodeViewMetadataDeltaItemsForPanelSelector();

		const firstItems = selector({
			reviewPackage,
			selectedCodeViewItem,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: null,
			sourceKey: 'source-a',
			visibleCodeViewItems: [visibleCodeViewItem],
		});
		const secondItems = selector({
			reviewPackage,
			selectedCodeViewItem: cloneBridgeMainCodeViewItem(selectedCodeViewItem),
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: null,
			sourceKey: 'source-a',
			visibleCodeViewItems: [visibleCodeViewItem],
		});

		expect(secondItems).toBe(firstItems);
	});

	test('keeps metadata deltas stable across visible worker item payload clones', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		const visibleItem = reviewPackage.itemsById['docs-plan'];
		if (sourceItem === undefined || visibleItem === undefined) {
			throw new Error('expected projection fixture items');
		}
		const selectedCodeViewItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(sourceItem),
		);
		const visibleCodeViewItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(visibleItem),
		);
		const selector = createBridgeCodeViewMetadataDeltaItemsForPanelSelector();

		const firstItems = selector({
			reviewPackage,
			selectedCodeViewItem,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: null,
			sourceKey: 'source-a',
			visibleCodeViewItems: [visibleCodeViewItem],
		});
		const secondItems = selector({
			reviewPackage,
			selectedCodeViewItem,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: null,
			sourceKey: 'source-a',
			visibleCodeViewItems: [cloneBridgeMainCodeViewItem(visibleCodeViewItem)],
		});

		expect(secondItems).toBe(firstItems);
	});

	test('keeps metadata deltas stable across normalization-equivalent worker languages', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		const visibleItem = reviewPackage.itemsById['docs-plan'];
		if (sourceItem === undefined || visibleItem === undefined) {
			throw new Error('expected projection fixture items');
		}
		const selectedCodeViewItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(sourceItem),
		);
		const visibleCodeViewItem = workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(visibleItem),
		);
		if (visibleCodeViewItem.type !== 'diff') {
			throw new Error('expected visible diff fixture item');
		}
		const selector = createBridgeCodeViewMetadataDeltaItemsForPanelSelector();

		const firstItems = selector({
			reviewPackage,
			selectedCodeViewItem,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: null,
			sourceKey: 'source-a',
			visibleCodeViewItems: [
				{
					...visibleCodeViewItem,
					fileDiff: { ...visibleCodeViewItem.fileDiff, lang: ' TypeScript ' },
				},
			],
		});
		const secondItems = selector({
			reviewPackage,
			selectedCodeViewItem,
			selectedItemId: sourceItem.itemId,
			selectedItemPresentation: null,
			sourceKey: 'source-a',
			visibleCodeViewItems: [
				{
					...visibleCodeViewItem,
					fileDiff: { ...visibleCodeViewItem.fileDiff, lang: 'typescript' },
				},
			],
		});

		expect(secondItems).toBe(firstItems);
	});
});

function workerPreparedCodeViewItem(item: BridgeCodeViewItem): BridgeMainCodeViewItem {
	return {
		...item,
		bridgeMetadata: {
			...item.bridgeMetadata,
			contentState: 'hydrated',
		},
		version: (item.version ?? 0) + 1,
	} satisfies BridgeMainCodeViewItem;
}

function cloneBridgeMainCodeViewItem(item: BridgeMainCodeViewItem): BridgeMainCodeViewItem {
	if (item.type === 'file') {
		return {
			...item,
			bridgeMetadata: {
				...item.bridgeMetadata,
				contentRoles: [...item.bridgeMetadata.contentRoles],
			},
			file: { ...item.file },
		};
	}
	return {
		...item,
		bridgeMetadata: {
			...item.bridgeMetadata,
			contentRoles: [...item.bridgeMetadata.contentRoles],
		},
		fileDiff: { ...item.fileDiff },
	};
}
