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
		props.setItems(props.items);
		props.onComplete();
		return;
	}
	const applyItems =
		props.shouldSkipItem === undefined
			? props.items
			: props.items.filter((item): boolean => !props.shouldSkipItem?.(item));

	runBridgeFrameApplyPump({
		frameBudgetMilliseconds: props.frameBudgetMilliseconds,
		isStale: (unit): boolean => props.isStale(unit.item),
		maxUnitsPerFrame: props.maxUnitsPerFrame,
		noStarvationSelectedBatchLimit: props.noStarvationSelectedBatchLimit,
		now: props.now,
		onDrained: props.onComplete,
		scheduleNextTurn: props.scheduleNextTurn,
		staleScanLimit: props.staleScanLimit,
		units: applyItems.map((item) => ({
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
