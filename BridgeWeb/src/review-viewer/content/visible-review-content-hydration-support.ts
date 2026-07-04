import type { BridgeCodeViewContentResources } from '../code-view/bridge-code-view-materialization.js';

export interface VisibleContentResourcesState {
	readonly contentKey: string;
	readonly itemId: string;
	readonly retryAfterVersion?: number;
	readonly status: 'aborted' | 'deferred' | 'loading' | 'ready' | 'failed';
}

export interface BridgeVisibleHydrationDiscardProbeRecord {
	readonly hadState: boolean;
	readonly pausedNow: boolean;
}

export interface BridgeVisibleHydrationDiscardProbe {
	readyResultDiscardCount: number;
	records: BridgeVisibleHydrationDiscardProbeRecord[];
}

declare global {
	interface Window {
		__bridgeVisibleHydrationDiscardProbe?: BridgeVisibleHydrationDiscardProbe;
	}
}

export function shouldAcceptVisibleReviewContentReadyResult(props: {
	readonly contentKey: string;
	readonly currentState: VisibleContentResourcesState | undefined;
}): boolean {
	return props.currentState === undefined || props.currentState.contentKey === props.contentKey;
}

export function pruneVisibleReviewContentHydrationCaches(props: {
	readonly contentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>;
	readonly maxReadyResourceCount: number;
	readonly resourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>;
	readonly retainedContentKeys: ReadonlySet<string>;
	readonly visibleItemIds: readonly string[];
}): {
	readonly contentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>;
	readonly resourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>;
} {
	const visibleItemIdSet = new Set(props.visibleItemIds);
	const visibleReadyEntries: [string, BridgeCodeViewContentResources][] = [];
	const retainedReadyEntries: [string, BridgeCodeViewContentResources][] = [];
	for (const [itemId, resources] of props.resourcesByItemId) {
		const state = props.contentStateByItemId.get(itemId);
		if (state?.status !== 'ready' || !props.retainedContentKeys.has(state.contentKey)) {
			continue;
		}
		if (visibleItemIdSet.has(itemId)) {
			visibleReadyEntries.push([itemId, resources]);
			continue;
		}
		retainedReadyEntries.push([itemId, resources]);
	}
	const nextResourcesByItemId = new Map<string, BridgeCodeViewContentResources>();
	for (const [itemId, resources] of visibleReadyEntries) {
		nextResourcesByItemId.set(itemId, resources);
	}
	for (const [itemId, resources] of retainedReadyEntries.toReversed()) {
		if (nextResourcesByItemId.size >= props.maxReadyResourceCount) {
			break;
		}
		nextResourcesByItemId.set(itemId, resources);
	}

	const nextStateByItemId = new Map<string, VisibleContentResourcesState>();
	for (const [itemId, state] of props.contentStateByItemId) {
		if (!props.retainedContentKeys.has(state.contentKey)) {
			continue;
		}
		switch (state.status) {
			case 'loading':
			case 'deferred':
				nextStateByItemId.set(itemId, state);
				break;
			case 'ready':
				if (nextResourcesByItemId.has(itemId)) {
					nextStateByItemId.set(itemId, state);
				}
				break;
			case 'aborted':
			case 'failed':
				if (visibleItemIdSet.has(itemId)) {
					nextStateByItemId.set(itemId, state);
				}
				break;
		}
	}
	return {
		contentStateByItemId: nextStateByItemId,
		resourcesByItemId: nextResourcesByItemId,
	};
}

export function recordVisibleHydrationReadyResultDiscard(
	record: BridgeVisibleHydrationDiscardProbeRecord,
): void {
	const probeWindow = (globalThis as typeof globalThis & { readonly window?: Window }).window;
	if (probeWindow === undefined || typeof probeWindow !== 'object') {
		return;
	}
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	probeWindow.__bridgeVisibleHydrationDiscardProbe ??= {
		readyResultDiscardCount: 0,
		records: [],
	};
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	probeWindow.__bridgeVisibleHydrationDiscardProbe.readyResultDiscardCount += 1;
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	probeWindow.__bridgeVisibleHydrationDiscardProbe.records.push(record);
}
