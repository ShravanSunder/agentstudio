import type { MutableRefObject } from 'react';
import { useEffect, useRef } from 'react';

import type { BridgeDemandScheduler } from '../core/demand/bridge-demand-scheduler.js';
import type { BridgeResourceExecutor } from '../core/demand/bridge-resource-executor.js';
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type { BridgeTextResourceStreamResult } from '../core/resources/bridge-resource-stream.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import { loadReviewItemContentResourcesThroughDemandResult } from '../review-viewer/content/review-content-demand-loader.js';
import {
	reviewContentPrefetchCandidateItemIds,
	shouldRunReviewContentPrefetch,
} from '../review-viewer/content/review-content-prefetch-policy.js';
import type { BridgeReviewContentRegistry } from '../review-viewer/content/review-content-registry.js';

export interface UseBridgeReviewContentPrefetchControllerProps {
	readonly contentRegistry: BridgeReviewContentRegistry;
	readonly isActive: boolean;
	readonly isCodeViewScrollActive: boolean;
	readonly resourceExecutor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
	readonly reviewContentDescriptorRefsByHandleIdRef: MutableRefObject<
		ReadonlyMap<string, BridgeDescriptorRef>
	>;
	readonly reviewContentInvalidationVersion: number;
	readonly reviewDemandScheduler: BridgeDemandScheduler;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedContentLoading: boolean;
	readonly selectedItemId: string | null;
	readonly visibleOwnedItemIds: ReadonlySet<string>;
	readonly visibleLoadingItemCount: number;
}

/** Background content prefetch pump: once selected and visible demand are
 * settled, warms the registry outward from the cursor (ring order) through
 * the same demand loader, one sequential load at a time. Registry peeks make
 * already-warm items free, so the pump converges and stops on its own. */
export function useBridgeReviewContentPrefetchController(
	props: UseBridgeReviewContentPrefetchControllerProps,
): void {
	const {
		contentRegistry,
		isActive,
		isCodeViewScrollActive,
		resourceExecutor,
		reviewContentDescriptorRefsByHandleIdRef,
		reviewContentInvalidationVersion,
		reviewDemandScheduler,
		reviewPackage,
		selectedContentLoading,
		selectedItemId,
		visibleOwnedItemIds,
		visibleLoadingItemCount,
	} = props;
	const reviewPackageRef = useRef<BridgeReviewPackage | null>(reviewPackage);
	reviewPackageRef.current = reviewPackage;
	const visibleOwnedItemIdsRef = useRef<ReadonlySet<string>>(visibleOwnedItemIds);
	visibleOwnedItemIdsRef.current = visibleOwnedItemIds;
	const failedItemIdsRef = useRef<Set<string>>(new Set<string>());
	const attemptedItemIdsRef = useRef<Set<string>>(new Set<string>());

	const packageIdentityKey =
		reviewPackage === null
			? null
			: [
					reviewPackage.packageId,
					String(reviewPackage.reviewGeneration),
					String(reviewPackage.revision),
				].join(':');
	const prefetchGateOpen = shouldRunReviewContentPrefetch({
		isActive,
		isCodeViewScrollActive,
		reviewPackage,
		selectedContentLoading,
		visibleLoadingItemCount,
	});

	useEffect((): void => {
		failedItemIdsRef.current = new Set<string>();
		attemptedItemIdsRef.current = new Set<string>();
	}, [packageIdentityKey, reviewContentInvalidationVersion]);

	useEffect((): (() => void) | undefined => {
		if (!prefetchGateOpen || packageIdentityKey === null) {
			return undefined;
		}
		const abortController = new AbortController();
		const pump = async (): Promise<void> => {
			while (!abortController.signal.aborted) {
				const currentReviewPackage = reviewPackageRef.current;
				if (currentReviewPackage === null) {
					return;
				}
				const candidateItemIds = reviewContentPrefetchCandidateItemIds({
					reviewPackage: currentReviewPackage,
					selectedItemId,
					cachedResourceKeys: new Set(contentRegistry.snapshot().cachedResourceKeys),
					excludedItemIds: new Set([
						...failedItemIdsRef.current,
						...attemptedItemIdsRef.current,
						...visibleOwnedItemIdsRef.current,
					]),
				});
				const nextItemId = candidateItemIds[0];
				if (nextItemId === undefined) {
					return;
				}
				attemptedItemIdsRef.current.add(nextItemId);
				// oxlint-disable-next-line no-await-in-loop -- The pump is sequential by contract (reviewContentPrefetchMaxConcurrentLoads = 1): each candidate is re-chosen from live cache state after the previous load settles.
				const loadResult = await loadReviewItemContentResourcesThroughDemandResult({
					reviewPackage: currentReviewPackage,
					itemId: nextItemId,
					interest: 'background',
					resolveDescriptorRef: (handle): BridgeDescriptorRef | null =>
						reviewContentDescriptorRefsByHandleIdRef.current.get(handle.handleId) ?? null,
					scheduler: reviewDemandScheduler,
					executor: resourceExecutor,
					contentRegistry,
					signal: abortController.signal,
				});
				if (abortController.signal.aborted) {
					return;
				}
				if (loadResult.status === 'failed') {
					// Exclude broken items for this generation so the pump
					// cannot spin on them; invalidation clears the exclusions.
					failedItemIdsRef.current.add(nextItemId);
					continue;
				}
				if (loadResult.status === 'deferred') {
					// Executor or scheduler pressure: yield until the next
					// gate change re-arms the pump instead of busy-waiting.
					return;
				}
			}
		};
		void pump();
		return (): void => {
			abortController.abort();
		};
	}, [
		contentRegistry,
		packageIdentityKey,
		prefetchGateOpen,
		resourceExecutor,
		reviewContentDescriptorRefsByHandleIdRef,
		reviewContentInvalidationVersion,
		reviewDemandScheduler,
		selectedItemId,
	]);
}
