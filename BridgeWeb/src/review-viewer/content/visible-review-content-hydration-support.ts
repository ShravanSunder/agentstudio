import type { BridgeCodeViewContentResources } from '../code-view/bridge-code-view-materialization.js';

export interface VisibleContentResourcesState {
	readonly contentKey: string;
	readonly itemId: string;
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

export interface BridgeVisibleHydrationStateProbe {
	readonly reportedVisibleItemCount: number;
	readonly trackedVisibleItemCount: number;
	readonly truncatedVisibleItemCount: number;
	readonly untrackedItemCount: number;
	readonly loadingItemCount: number;
	readonly readyItemCount: number;
	readonly failedItemCount: number;
	readonly deferredItemCount: number;
	readonly abortedItemCount: number;
	readonly pausedNow: boolean;
}

declare global {
	interface Window {
		__bridgeVisibleHydrationDiscardProbe?: BridgeVisibleHydrationDiscardProbe;
		__bridgeVisibleHydrationStateProbe?: BridgeVisibleHydrationStateProbe;
	}
}

export function deriveVisibleHydrationStateProbe(props: {
	readonly contentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>;
	readonly pausedNow: boolean;
	readonly reportedVisibleItemCount: number;
	readonly trackedVisibleItemIds: readonly string[];
}): BridgeVisibleHydrationStateProbe {
	let loadingItemCount = 0;
	let readyItemCount = 0;
	let failedItemCount = 0;
	let deferredItemCount = 0;
	let abortedItemCount = 0;
	let untrackedItemCount = 0;
	for (const itemId of props.trackedVisibleItemIds) {
		const state = props.contentStateByItemId.get(itemId);
		switch (state?.status) {
			case 'loading':
				loadingItemCount += 1;
				break;
			case 'ready':
				readyItemCount += 1;
				break;
			case 'failed':
				failedItemCount += 1;
				break;
			case 'deferred':
				deferredItemCount += 1;
				break;
			case 'aborted':
				abortedItemCount += 1;
				break;
			case undefined:
				untrackedItemCount += 1;
				break;
		}
	}
	return {
		abortedItemCount,
		deferredItemCount,
		failedItemCount,
		loadingItemCount,
		pausedNow: props.pausedNow,
		readyItemCount,
		reportedVisibleItemCount: props.reportedVisibleItemCount,
		trackedVisibleItemCount: props.trackedVisibleItemIds.length,
		truncatedVisibleItemCount: Math.max(
			0,
			props.reportedVisibleItemCount - props.trackedVisibleItemIds.length,
		),
		untrackedItemCount,
	};
}

export function publishVisibleHydrationStateProbe(probe: BridgeVisibleHydrationStateProbe): void {
	const probeWindow = (globalThis as typeof globalThis & { readonly window?: Window }).window;
	if (probeWindow === undefined || typeof probeWindow !== 'object') {
		return;
	}
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	probeWindow.__bridgeVisibleHydrationStateProbe = probe;
}

export function shouldAcceptVisibleReviewContentReadyResult(props: {
	readonly contentKey: string;
	readonly currentState: VisibleContentResourcesState | undefined;
}): boolean {
	return props.currentState === undefined || props.currentState.contentKey === props.contentKey;
}

export function pruneVisibleReviewContentHydrationCaches(props: {
	readonly contentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>;
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
