import { describe, expect, test } from 'vitest';

import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import { materializeBridgeCodeViewLoadingItem } from './bridge-code-view-materialization.js';
import { createBridgeCodeViewMetadataDeltaItemsForPanelSelector } from './bridge-code-view-worker-prepared-items.js';

describe('Bridge CodeView worker-prepared item selector', () => {
	test('promotes selected demand rank without replacing the exact worker-prepared object', () => {
		// Arrange
		const fixture = makeSelectorFixture();
		const selectedPayload =
			fixture.selectedCodeViewItem.type === 'file'
				? fixture.selectedCodeViewItem.file
				: fixture.selectedCodeViewItem.fileDiff;
		Object.assign(selectedPayload, { bridgeDemandRank: 1 });
		const selector = createBridgeCodeViewMetadataDeltaItemsForPanelSelector();

		// Act
		const selectedItems = selectFixtureItems({ fixture, selector });

		// Assert
		const selectedItem = selectedItems.find(
			(item): boolean => item.id === fixture.selectedCodeViewItem.id,
		);
		expect(selectedItem).toBe(fixture.selectedCodeViewItem);
		expect(
			selectedItem?.type === 'file'
				? selectedItem.file.bridgeDemandRank
				: selectedItem?.fileDiff.bridgeDemandRank,
		).toBe(0);
	});

	test('retains the cached result for the exact same selected and visible worker objects', () => {
		const fixture = makeSelectorFixture();
		const selector = createBridgeCodeViewMetadataDeltaItemsForPanelSelector();
		const firstItems = selectFixtureItems({ fixture, selector });
		const secondItems = selectFixtureItems({ fixture, selector });

		expect(secondItems).toBe(firstItems);
		expect(firstItems.find((item) => item.id === fixture.selectedCodeViewItem.id)).toBe(
			fixture.selectedCodeViewItem,
		);
		expect(firstItems.find((item) => item.id === fixture.visibleCodeViewItem.id)).toBe(
			fixture.visibleCodeViewItem,
		);
	});

	test('returns a fresh result containing a fresh equivalent selected worker object', () => {
		const fixture = makeSelectorFixture();
		const selector = createBridgeCodeViewMetadataDeltaItemsForPanelSelector();
		const firstItems = selectFixtureItems({ fixture, selector });
		const freshSelectedCodeViewItem = cloneBridgeMainCodeViewItem(fixture.selectedCodeViewItem);
		const secondItems = selectFixtureItems({
			fixture: { ...fixture, selectedCodeViewItem: freshSelectedCodeViewItem },
			selector,
		});

		expect(freshSelectedCodeViewItem).not.toBe(fixture.selectedCodeViewItem);
		expect(secondItems).not.toBe(firstItems);
		expect(secondItems.find((item) => item.id === freshSelectedCodeViewItem.id)).toBe(
			freshSelectedCodeViewItem,
		);
		expect(secondItems.find((item) => item.id === fixture.visibleCodeViewItem.id)).toBe(
			fixture.visibleCodeViewItem,
		);
	});

	test('returns a fresh result containing a fresh equivalent visible worker object', () => {
		const fixture = makeSelectorFixture();
		const selector = createBridgeCodeViewMetadataDeltaItemsForPanelSelector();
		const firstItems = selectFixtureItems({ fixture, selector });
		const freshVisibleCodeViewItem = cloneBridgeMainCodeViewItem(fixture.visibleCodeViewItem);
		const secondItems = selectFixtureItems({
			fixture: { ...fixture, visibleCodeViewItem: freshVisibleCodeViewItem },
			selector,
		});

		expect(freshVisibleCodeViewItem).not.toBe(fixture.visibleCodeViewItem);
		expect(secondItems).not.toBe(firstItems);
		expect(secondItems.find((item) => item.id === fixture.selectedCodeViewItem.id)).toBe(
			fixture.selectedCodeViewItem,
		);
		expect(secondItems.find((item) => item.id === freshVisibleCodeViewItem.id)).toBe(
			freshVisibleCodeViewItem,
		);
	});
});

interface SelectorFixture {
	readonly reviewPackage: ReturnType<typeof makeBridgeViewerProjectionFixture>;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem;
	readonly selectedItemId: string;
	readonly visibleCodeViewItem: BridgeMainCodeViewItem;
}

function makeSelectorFixture(): SelectorFixture {
	const reviewPackage = makeBridgeViewerProjectionFixture();
	const sourceItem = reviewPackage.itemsById['source-high'];
	const visibleItem = reviewPackage.itemsById['docs-plan'];
	if (sourceItem === undefined || visibleItem === undefined) {
		throw new Error('expected projection fixture items');
	}
	return {
		reviewPackage,
		selectedCodeViewItem: workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(sourceItem),
		),
		selectedItemId: sourceItem.itemId,
		visibleCodeViewItem: workerPreparedCodeViewItem(
			materializeBridgeCodeViewLoadingItem(visibleItem),
		),
	};
}

function selectFixtureItems(props: {
	readonly fixture: SelectorFixture;
	readonly selector: ReturnType<typeof createBridgeCodeViewMetadataDeltaItemsForPanelSelector>;
}): readonly BridgeCodeViewItem[] {
	return props.selector({
		reviewPackage: props.fixture.reviewPackage,
		selectedCodeViewItem: props.fixture.selectedCodeViewItem,
		selectedItemId: props.fixture.selectedItemId,
		selectedItemPresentation: null,
		sourceKey: 'source-a',
		visibleCodeViewItems: [props.fixture.visibleCodeViewItem],
	});
}

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
