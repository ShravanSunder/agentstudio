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
	readonly forceAuthoritativeReplacement?: boolean;
	readonly getCurrentItem: (itemId: string) => CodeViewItem | undefined;
	readonly getCurrentItemTop?: (itemId: string) => number | undefined;
}

export interface RunBridgeCodeViewMetadataReconciliationInChunksProps extends RunBridgeCodeViewMetadataApplyInChunksProps {
	readonly currentItems: readonly BridgeCodeViewItem[];
	readonly forceAuthoritativeReplacement?: boolean;
	readonly getCurrentItem: (itemId: string) => CodeViewItem | undefined;
	readonly getCurrentItemTop?: (itemId: string) => number | undefined;
	readonly isTaskStale: () => boolean;
}

export interface BridgeCodeViewManifestReconciliationDecisionProps {
	readonly authoritativeIndexByItemId: ReadonlyMap<string, number>;
	readonly authoritativeItemIds: readonly string[];
	readonly getCurrentItem: (itemId: string) => CodeViewItem | undefined;
	readonly getCurrentItemTop?: (itemId: string) => number | undefined;
	readonly manifestChanged: boolean;
	readonly metadataDeltaItems: readonly BridgeCodeViewItem[];
	readonly sourceReset: boolean;
}

export function bridgeCodeViewMetadataRequiresManifestReconciliation(
	props: BridgeCodeViewManifestReconciliationDecisionProps,
): boolean {
	if (props.sourceReset || props.manifestChanged) {
		return true;
	}
	for (const metadataDeltaItem of props.metadataDeltaItems) {
		const authoritativeIndex = props.authoritativeIndexByItemId.get(metadataDeltaItem.id);
		if (authoritativeIndex === undefined) {
			continue;
		}
		if (
			liveBridgeCodeViewManifestNeighborhoodDiffers({
				authoritativeIndex,
				authoritativeItemIds: props.authoritativeItemIds,
				getCurrentItem: props.getCurrentItem,
				...(props.getCurrentItemTop === undefined
					? {}
					: { getCurrentItemTop: props.getCurrentItemTop }),
			})
		) {
			return true;
		}
	}
	return false;
}

export function planBridgeCodeViewManifestReconciliation(
	props: PlanBridgeCodeViewManifestReconciliationProps,
): BridgeCodeViewManifestReconciliationPlan {
	if (props.forceAuthoritativeReplacement === true) {
		return { items: props.authoritativeItems, kind: 'replace' };
	}
	if (
		liveBridgeCodeViewManifestDiffers({
			authoritativeItemIds: props.authoritativeItems.map((item): string => item.id),
			getCurrentItem: props.getCurrentItem,
			...(props.getCurrentItemTop === undefined
				? {}
				: { getCurrentItemTop: props.getCurrentItemTop }),
		})
	) {
		return { items: props.authoritativeItems, kind: 'replace' };
	}
	for (const authoritativeItem of props.authoritativeItems) {
		const liveItem = props.getCurrentItem(authoritativeItem.id);
		if (liveItem?.type !== authoritativeItem.type) {
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
		...(props.forceAuthoritativeReplacement === undefined
			? {}
			: { forceAuthoritativeReplacement: props.forceAuthoritativeReplacement }),
		getCurrentItem: props.getCurrentItem,
		...(props.getCurrentItemTop === undefined
			? {}
			: { getCurrentItemTop: props.getCurrentItemTop }),
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

function liveBridgeCodeViewManifestNeighborhoodDiffers(props: {
	readonly authoritativeIndex: number;
	readonly authoritativeItemIds: readonly string[];
	readonly getCurrentItem: (itemId: string) => CodeViewItem | undefined;
	readonly getCurrentItemTop?: (itemId: string) => number | undefined;
}): boolean {
	const finalIndex = props.authoritativeItemIds.length - 1;
	const probeIndexes = new Set([
		0,
		props.authoritativeIndex - 1,
		props.authoritativeIndex,
		props.authoritativeIndex + 1,
		finalIndex,
	]);
	let previousItemTop: number | null = null;
	for (const probeIndex of [...probeIndexes].toSorted((left, right): number => left - right)) {
		if (probeIndex < 0 || probeIndex > finalIndex) {
			continue;
		}
		const itemId = props.authoritativeItemIds[probeIndex];
		if (itemId === undefined || props.getCurrentItem(itemId) === undefined) {
			return true;
		}
		if (props.getCurrentItemTop === undefined) {
			continue;
		}
		const itemTop = props.getCurrentItemTop(itemId);
		if (itemTop === undefined || (previousItemTop !== null && itemTop <= previousItemTop)) {
			return true;
		}
		previousItemTop = itemTop;
	}
	return false;
}

function liveBridgeCodeViewManifestDiffers(props: {
	readonly authoritativeItemIds: readonly string[];
	readonly getCurrentItem: (itemId: string) => CodeViewItem | undefined;
	readonly getCurrentItemTop?: (itemId: string) => number | undefined;
}): boolean {
	let previousItemTop: number | null = null;
	for (const itemId of props.authoritativeItemIds) {
		if (props.getCurrentItem(itemId) === undefined) {
			return true;
		}
		if (props.getCurrentItemTop === undefined) {
			continue;
		}
		const itemTop = props.getCurrentItemTop(itemId);
		if (itemTop === undefined || (previousItemTop !== null && itemTop <= previousItemTop)) {
			return true;
		}
		previousItemTop = itemTop;
	}
	return false;
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
