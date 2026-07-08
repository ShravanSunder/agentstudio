import type { CodeViewItem } from '@pierre/diffs';

import {
	runBridgeFrameApplyPump,
	type BridgeFrameApplyUnitRank,
} from '../../core/rendering/bridge-frame-apply-pump.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';

export interface BridgeCodeViewMetadataReconcileProps {
	readonly forceReplaceItemIds?: readonly string[];
	readonly getCurrentItem: (itemId: string) => CodeViewItem | undefined;
	readonly metadataItems: readonly BridgeCodeViewItem[];
	readonly preserveItemIds?: readonly string[];
}

export interface RunBridgeCodeViewMetadataApplyInChunksProps {
	readonly applyItemUpdate: (item: BridgeCodeViewItem) => void;
	readonly frameBudgetMilliseconds: number;
	readonly isStale: (item: BridgeCodeViewItem) => boolean;
	readonly items: readonly BridgeCodeViewItem[];
	readonly maxUnitsPerFrame: number;
	readonly noStarvationSelectedBatchLimit: number;
	readonly now: () => number;
	readonly onComplete: () => void;
	readonly rankForItem: (item: BridgeCodeViewItem) => BridgeFrameApplyUnitRank;
	readonly replacementItemsForItem?: (
		item: BridgeCodeViewItem,
	) => readonly BridgeCodeViewItem[] | null;
	readonly scheduleNextTurn: (callback: () => void) => void;
	readonly setItems: (items: readonly BridgeCodeViewItem[]) => void;
	readonly shouldSkipItem?: (item: BridgeCodeViewItem) => boolean;
	readonly sourceReset: boolean;
	readonly staleScanLimit: number;
}

export function runBridgeCodeViewMetadataApplyInChunks(
	props: RunBridgeCodeViewMetadataApplyInChunksProps,
): void {
	if (props.sourceReset) {
		const sourceResetSeedItems = sourceResetSeedItemsForApply({
			items: props.items,
			rankForItem: props.rankForItem,
		});
		props.setItems(sourceResetSeedItems);
		const seedItemIds = new Set(sourceResetSeedItems.map((item) => item.id));
		const remainingItems = props.items.filter((item): boolean => !seedItemIds.has(item.id));
		if (remainingItems.length === 0) {
			props.onComplete();
			return;
		}
		runBridgeCodeViewMetadataApplyPump({
			...props,
			items: remainingItems,
		});
		return;
	}

	const applyItems =
		props.shouldSkipItem === undefined
			? props.items
			: props.items.filter((item): boolean => !props.shouldSkipItem?.(item));

	runBridgeCodeViewMetadataApplyPump({
		...props,
		items: applyItems,
	});
}

function sourceResetSeedItemsForApply(props: {
	readonly items: readonly BridgeCodeViewItem[];
	readonly rankForItem: (item: BridgeCodeViewItem) => BridgeFrameApplyUnitRank;
}): readonly BridgeCodeViewItem[] {
	const selectedItems = props.items.filter(
		(item): boolean => props.rankForItem(item) === 'selected',
	);
	return selectedItems.length === 0 ? props.items.slice(0, 1) : selectedItems;
}

function runBridgeCodeViewMetadataApplyPump(
	props: RunBridgeCodeViewMetadataApplyInChunksProps,
): void {
	runBridgeFrameApplyPump({
		frameBudgetMilliseconds: props.frameBudgetMilliseconds,
		isStale: (unit): boolean => props.isStale(unit.item),
		maxUnitsPerFrame: props.maxUnitsPerFrame,
		noStarvationSelectedBatchLimit: props.noStarvationSelectedBatchLimit,
		now: props.now,
		onDrained: props.onComplete,
		scheduleNextTurn: props.scheduleNextTurn,
		staleScanLimit: props.staleScanLimit,
		units: props.items.map((item) => ({
			id: item.id,
			item,
			rank: props.rankForItem(item),
			run: (): void => {
				const replacementItems = props.replacementItemsForItem?.(item) ?? null;
				if (replacementItems !== null) {
					props.setItems(replacementItems);
					return;
				}
				props.applyItemUpdate(item);
			},
		})),
	});
}
