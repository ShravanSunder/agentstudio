import type { Dispatch, SetStateAction } from 'react';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { ReviewContentDemandLoadResult } from './review-content-demand-loader.js';
import { makeVisibleReviewItemContentResourcesKey } from './visible-review-content-hydration-identity.js';
import type { VisibleContentResourcesState } from './visible-review-content-hydration-support.js';
import type { VisibleReviewContentLoadResult } from './visible-review-content-hydration.js';

export interface VisibleReviewContentAbortRearmSnapshot {
	readonly contentInvalidationVersion: number;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId?: string | null;
	readonly visibleHydrationPaused: boolean;
	readonly visibleItemIds: readonly string[];
}

export function shouldApplyVisibleContentStateImmediately(props: {
	readonly itemId: string;
	readonly pausedNow: boolean;
	readonly selectedItemId: string | null;
}): boolean {
	return !props.pausedNow || props.itemId === props.selectedItemId;
}

export function visibleContentStateForAcceptedReadyResult(props: {
	readonly contentKey: string;
	readonly itemId: string;
	readonly pausedNow: boolean;
	readonly selectedItemId: string | null;
}): VisibleContentResourcesState {
	return {
		contentKey: props.contentKey,
		itemId: props.itemId,
		status: shouldApplyVisibleContentStateImmediately(props) ? 'ready' : 'deferred',
	};
}

export function promoteDeferredVisibleContentStates(
	contentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>,
): ReadonlyMap<string, VisibleContentResourcesState> {
	let didPromoteState = false;
	const nextStateByItemId = new Map(contentStateByItemId);
	for (const [itemId, state] of contentStateByItemId) {
		if (state.status !== 'deferred') {
			continue;
		}
		didPromoteState = true;
		nextStateByItemId.set(itemId, {
			contentKey: state.contentKey,
			itemId,
			status: 'ready',
		});
	}
	return didPromoteState ? nextStateByItemId : contentStateByItemId;
}

export function visibleReviewContentLoadPlanCount(props: {
	readonly loadingCount: number;
	readonly requestedLoadCount: number;
	readonly scheduledCount?: number;
	readonly concurrentLoadLimit?: number;
}): number {
	const concurrentLoadLimit = props.concurrentLoadLimit ?? 4;
	const scheduledCount = props.scheduledCount ?? 0;
	const scheduledButNotLoadingCount = Math.max(0, scheduledCount - props.loadingCount);
	const availableLoadSlots = Math.max(
		0,
		concurrentLoadLimit - props.loadingCount - scheduledButNotLoadingCount,
	);
	return Math.min(props.requestedLoadCount, availableLoadSlots);
}

export function recoverAbortedVisibleContentLoadState(props: {
	readonly contentKey: string;
	readonly currentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>;
	readonly itemId: string;
}): ReadonlyMap<string, VisibleContentResourcesState> {
	const currentState = props.currentStateByItemId.get(props.itemId);
	if (currentState?.contentKey !== props.contentKey || currentState.status !== 'loading') {
		return props.currentStateByItemId;
	}
	const nextStateByItemId = new Map(props.currentStateByItemId);
	nextStateByItemId.set(props.itemId, {
		contentKey: props.contentKey,
		itemId: props.itemId,
		status: 'aborted',
	});
	return nextStateByItemId;
}

export function shouldRearmAbortedVisibleContentLoad(
	props: VisibleReviewContentAbortRearmSnapshot & {
		readonly contentKey: string;
		readonly itemId: string;
	},
): boolean {
	if (
		props.visibleHydrationPaused ||
		props.reviewPackage === null ||
		!props.visibleItemIds.includes(props.itemId)
	) {
		return false;
	}
	const item = props.reviewPackage.itemsById[props.itemId];
	if (item === undefined) {
		return false;
	}
	return (
		makeVisibleReviewItemContentResourcesKey({
			contentInvalidationVersion: props.contentInvalidationVersion,
			item,
			reviewPackage: props.reviewPackage,
		}) === props.contentKey
	);
}

export function shouldSweepVisibleContentAfterAbortedLoad(
	props: VisibleReviewContentAbortRearmSnapshot,
): boolean {
	return (
		!props.visibleHydrationPaused && props.reviewPackage !== null && props.visibleItemIds.length > 0
	);
}

export const shouldAbortVisibleContentLoadsForPause = (): boolean => false;

export function abortVisibleContentLoads(
	loadAbortControllersByContentKey: Map<string, AbortController>,
): void {
	for (const loadAbortController of loadAbortControllersByContentKey.values()) {
		loadAbortController.abort();
	}
	loadAbortControllersByContentKey.clear();
}

export function abortVisibleContentLoadsExcept(
	loadAbortControllersByContentKey: Map<string, AbortController>,
	retainedContentKeys: ReadonlySet<string>,
): void {
	for (const [contentKey, loadAbortController] of loadAbortControllersByContentKey) {
		if (retainedContentKeys.has(contentKey)) {
			continue;
		}
		loadAbortController.abort();
		loadAbortControllersByContentKey.delete(contentKey);
	}
}

export function normalizeVisibleReviewContentLoadResult(
	result: VisibleReviewContentLoadResult,
): ReviewContentDemandLoadResult {
	if (result === null) {
		return { status: 'failed', reason: 'load_failed' };
	}
	if ('status' in result) {
		return result;
	}
	return { status: 'ready', resources: result };
}

export function scheduleVisibleHydrationRetry(props: {
	readonly scheduledRef: { current: boolean };
	readonly setRetryVersion: Dispatch<SetStateAction<number>>;
}): void {
	if (props.scheduledRef.current) {
		return;
	}
	props.scheduledRef.current = true;
	const scheduleRetry =
		typeof requestAnimationFrame === 'function'
			? (callback: () => void): void => {
					requestAnimationFrame(callback);
				}
			: (callback: () => void): void => {
					queueMicrotask(callback);
				};
	scheduleRetry((): void => {
		props.scheduledRef.current = false;
		props.setRetryVersion((currentVersion: number): number => currentVersion + 1);
	});
}
