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
	readonly staleScanLimit: number;
}

export type BridgeCodeViewManifestReconciliationPlan =
	| { readonly kind: 'none' }
	| {
			readonly appendedItems: readonly BridgeCodeViewItem[];
			readonly kind: 'appendOnly';
	  }
	| {
			readonly items: readonly BridgeCodeViewItem[];
			readonly kind: 'replace';
	  };

export interface PlanBridgeCodeViewManifestReconciliationProps {
	readonly authoritativeItems: readonly BridgeCodeViewItem[];
	readonly currentItems: readonly BridgeCodeViewItem[];
	readonly getCurrentItem: (itemId: string) => CodeViewItem | undefined;
}

export interface RunBridgeCodeViewMetadataReconciliationInChunksProps extends RunBridgeCodeViewMetadataApplyInChunksProps {
	readonly currentItems: readonly BridgeCodeViewItem[];
	readonly getCurrentItem: (itemId: string) => CodeViewItem | undefined;
	readonly isTaskStale: () => boolean;
}

export interface BridgeCodeViewManifestReconciliationDecisionProps {
	readonly authoritativeItemIds: ReadonlySet<string>;
	readonly getCurrentItem: (itemId: string) => CodeViewItem | undefined;
	readonly manifestChanged: boolean;
	readonly metadataDeltaItems: readonly BridgeCodeViewItem[];
	readonly sourceReset: boolean;
}

export function bridgeCodeViewMetadataRequiresManifestReconciliation(
	props: BridgeCodeViewManifestReconciliationDecisionProps,
): boolean {
	return (
		props.sourceReset ||
		props.manifestChanged ||
		props.metadataDeltaItems.some(
			(item): boolean =>
				props.authoritativeItemIds.has(item.id) && props.getCurrentItem(item.id) === undefined,
		)
	);
}

export function planBridgeCodeViewManifestReconciliation(
	props: PlanBridgeCodeViewManifestReconciliationProps,
): BridgeCodeViewManifestReconciliationPlan {
	for (const authoritativeItem of props.authoritativeItems) {
		const liveItem = props.getCurrentItem(authoritativeItem.id);
		if (liveItem === undefined || liveItem.type !== authoritativeItem.type) {
			return { items: props.authoritativeItems, kind: 'replace' };
		}
	}
	const sharedItemCount = Math.min(props.currentItems.length, props.authoritativeItems.length);
	for (let index = 0; index < sharedItemCount; index += 1) {
		const currentItem = props.currentItems[index];
		const authoritativeItem = props.authoritativeItems[index];
		if (
			currentItem === undefined ||
			authoritativeItem === undefined ||
			currentItem.id !== authoritativeItem.id ||
			currentItem.type !== authoritativeItem.type
		) {
			return { items: props.authoritativeItems, kind: 'replace' };
		}
	}
	if (props.currentItems.length === props.authoritativeItems.length) {
		return { kind: 'none' };
	}
	if (props.currentItems.length < props.authoritativeItems.length) {
		return {
			appendedItems: props.authoritativeItems.slice(props.currentItems.length),
			kind: 'appendOnly',
		};
	}
	return { items: props.authoritativeItems, kind: 'replace' };
}

export function runBridgeCodeViewMetadataReconciliationInChunks(
	props: RunBridgeCodeViewMetadataReconciliationInChunksProps,
): void {
	const reconciliationPlan = planBridgeCodeViewManifestReconciliation({
		authoritativeItems: props.items,
		currentItems: props.currentItems,
		getCurrentItem: props.getCurrentItem,
	});
	if (reconciliationPlan.kind !== 'replace') {
		runBridgeCodeViewMetadataApplyInChunks(props);
		return;
	}
	props.scheduleNextTurn((): void => {
		if (props.isTaskStale()) {
			return;
		}
		props.setItems(reconciliationPlan.items);
		props.onComplete();
	});
}

export function runBridgeCodeViewMetadataApplyInChunks(
	props: RunBridgeCodeViewMetadataApplyInChunksProps,
): void {
	const applyItems =
		props.shouldSkipItem === undefined
			? props.items
			: props.items.filter((item): boolean => !props.shouldSkipItem?.(item));

	runBridgeCodeViewMetadataApplyPump({
		...props,
		items: applyItems,
	});
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
