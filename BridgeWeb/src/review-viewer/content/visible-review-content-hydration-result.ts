import type { BridgeCodeViewContentResources } from '../code-view/bridge-code-view-materialization.js';
import type { VisibleContentResourcesState } from './visible-review-content-hydration-support.js';
import type { UseVisibleReviewContentHydrationResult } from './visible-review-content-hydration.js';

export function createVisibleReviewContentHydrationResult(props: {
	readonly contentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>;
	readonly previousResult?: UseVisibleReviewContentHydrationResult | null;
	readonly resourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>;
	readonly setVisibleItemIds: (itemIds: readonly string[]) => void;
	readonly visibleItemIds: readonly string[];
}): UseVisibleReviewContentHydrationResult {
	const visibleContentResourcesByItemId = new Map<string, BridgeCodeViewContentResources>();
	const visibleFailedItemIds = new Set<string>();
	const visibleLoadingItemIds = new Set<string>();
	for (const itemId of props.visibleItemIds) {
		const currentState = props.contentStateByItemId.get(itemId);
		if (currentState?.status === 'loading') {
			visibleLoadingItemIds.add(itemId);
			continue;
		}
		if (currentState?.status === 'failed') {
			visibleFailedItemIds.add(itemId);
			continue;
		}
		const resources = props.resourcesByItemId.get(itemId);
		if (currentState?.status === 'ready' && resources !== undefined) {
			visibleContentResourcesByItemId.set(itemId, resources);
		}
	}
	const previousResult = props.previousResult ?? null;
	return {
		setVisibleItemIds: props.setVisibleItemIds,
		visibleContentResourcesByItemId: stableEqualValue(
			previousResult?.visibleContentResourcesByItemId,
			visibleContentResourcesByItemId,
			mapEntriesEqual,
		),
		visibleFailedItemIds,
		visibleItemIds: props.visibleItemIds,
		visibleLoadingItemIds: stableEqualValue(
			previousResult?.visibleLoadingItemIds,
			visibleLoadingItemIds,
			setEntriesEqual,
		),
		visibleLoadingItemCount: visibleLoadingItemIds.size,
		visibleReadyItemCount: visibleContentResourcesByItemId.size,
	};
}

export function countVisibleContentStatesWithStatus(props: {
	readonly contentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>;
	readonly status: VisibleContentResourcesState['status'];
}): number {
	let stateCount = 0;
	for (const state of props.contentStateByItemId.values()) {
		stateCount += state.status === props.status ? 1 : 0;
	}
	return stateCount;
}

export function mapEntriesEqual<TKey, TValue>(
	left: ReadonlyMap<TKey, TValue>,
	right: ReadonlyMap<TKey, TValue>,
): boolean {
	if (left.size !== right.size) {
		return false;
	}
	for (const [key, value] of left) {
		if (right.get(key) !== value) {
			return false;
		}
	}
	return true;
}

function stableEqualValue<TValue>(
	previousValue: TValue | undefined,
	nextValue: TValue,
	isEqual: (left: TValue, right: TValue) => boolean,
): TValue {
	return previousValue !== undefined && isEqual(previousValue, nextValue)
		? previousValue
		: nextValue;
}

function setEntriesEqual<TValue>(left: ReadonlySet<TValue>, right: ReadonlySet<TValue>): boolean {
	return left.size === right.size && [...left].every((value): boolean => right.has(value));
}
