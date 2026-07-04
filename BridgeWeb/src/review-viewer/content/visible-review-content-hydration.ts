import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type { BridgeContentDemandPlanEntry } from '../../core/demand/bridge-content-demand-reconciler.js';
import type { BridgeDescriptorRef } from '../../core/models/bridge-resource-descriptor.js';
import type {
	BridgeContentHandle,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	createBridgeChildTraceContext,
	type BridgeTraceContext,
} from '../../foundation/telemetry/bridge-trace-context.js';
import type { BridgeCodeViewContentResources } from '../code-view/bridge-code-view-materialization.js';
import { recordBridgeViewerContentQueueTelemetry } from '../telemetry/bridge-review-viewer-telemetry.js';
import type {
	ReviewContentDemandInterest,
	ReviewContentDemandLoadResult,
} from './review-content-demand-loader.js';
import type { LoadReviewItemContentResourcesProps } from './review-content-loader.js';
import type { BridgeReviewContentRegistry } from './review-content-registry.js';
import { deriveVisibleReviewContentLoadPlans } from './visible-review-content-hydration-demand.js';
import {
	makeVisibleReviewItemContentResourcesKey,
	normalizeVisibleReviewItemIds,
} from './visible-review-content-hydration-identity.js';
import {
	abortVisibleContentLoads,
	abortVisibleContentLoadsExcept,
	normalizeVisibleReviewContentLoadResult,
	promoteDeferredVisibleContentStates,
	recoverAbortedVisibleContentLoadState,
	scheduleVisibleHydrationRetry,
	shouldAbortVisibleContentLoadsForPause,
	shouldSweepVisibleContentAfterAbortedLoad,
	visibleContentStateForAcceptedReadyResult,
	visibleReviewContentLoadPlanCount,
	type VisibleReviewContentAbortRearmSnapshot,
} from './visible-review-content-hydration-load-state.js';
import {
	countVisibleContentStatesWithStatus,
	createVisibleReviewContentHydrationResult,
	mapEntriesEqual,
} from './visible-review-content-hydration-result.js';
import {
	deriveVisibleHydrationStateProbe,
	pruneVisibleReviewContentHydrationCaches,
	publishVisibleHydrationStateProbe,
	recordVisibleHydrationReadyResultDiscard,
	shouldAcceptVisibleReviewContentReadyResult,
	type VisibleContentResourcesState,
} from './visible-review-content-hydration-support.js';

export { deriveVisibleReviewContentLoadPlans } from './visible-review-content-hydration-demand.js';
export {
	makeReviewItemContentResourcesKey,
	normalizeVisibleReviewItemIds,
	selectedAdjacentReviewItemIds,
} from './visible-review-content-hydration-identity.js';
export {
	recoverAbortedVisibleContentLoadState,
	shouldApplyVisibleContentStateImmediately,
	shouldAbortVisibleContentLoadsForPause,
	shouldRearmAbortedVisibleContentLoad,
	visibleContentStateForAcceptedReadyResult,
	visibleReviewContentLoadPlanCount,
} from './visible-review-content-hydration-load-state.js';
export { createVisibleReviewContentHydrationResult } from './visible-review-content-hydration-result.js';
export {
	pruneVisibleReviewContentHydrationCaches,
	shouldAcceptVisibleReviewContentReadyResult,
} from './visible-review-content-hydration-support.js';
export type {
	BridgeVisibleHydrationDiscardProbe,
	BridgeVisibleHydrationDiscardProbeRecord,
	VisibleContentResourcesState,
} from './visible-review-content-hydration-support.js';

type VisibleReviewContentDemandInterest = Extract<
	ReviewContentDemandInterest,
	'nearby' | 'visible'
>;

export interface VisibleReviewContentLoadProps extends LoadReviewItemContentResourcesProps {
	readonly interest: VisibleReviewContentDemandInterest;
}

export interface UseVisibleReviewContentHydrationProps {
	readonly contentRegistry: BridgeReviewContentRegistry;
	readonly loadContentResources: (
		props: VisibleReviewContentLoadProps,
	) => Promise<VisibleReviewContentLoadResult>;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly resolveDescriptorRef: (handle: BridgeContentHandle) => BridgeDescriptorRef | null;
	readonly selectedItemId: string | null;
	readonly telemetryParentTraceContext: BridgeTraceContext | null;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly contentInvalidationVersion: number;
	readonly visibleHydrationPaused: boolean;
}

export interface UseVisibleReviewContentHydrationResult {
	readonly setVisibleItemIds: (itemIds: readonly string[]) => void;
	readonly visibleContentResourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>;
	readonly visibleFailedItemIds: ReadonlySet<string>;
	readonly visibleItemIds: readonly string[];
	readonly visibleLoadingItemIds: ReadonlySet<string>;
	readonly visibleLoadingItemCount: number;
	readonly visibleReadyItemCount: number;
}

// Live scroll evidence: macOS momentum keeps the Review CodeView scroll-active pause true
// after finger lift, so dispatch must not add another 64ms tail before visible loads start.
export const visibleContentHydrationConcurrentLoadLimit = 4;
export const visibleContentHydrationDispatchDelayMilliseconds = 0;

export type VisibleReviewContentLoadResult =
	| ReviewContentDemandLoadResult
	| BridgeCodeViewContentResources
	| null;

export function shouldRetryVisibleContentAfterDeferredLoad(props: {
	readonly loadResult: ReviewContentDemandLoadResult;
	readonly snapshot: VisibleReviewContentAbortRearmSnapshot;
}): boolean {
	return (
		props.loadResult.status === 'deferred' &&
		shouldSweepVisibleContentAfterAbortedLoad(props.snapshot)
	);
}

export function useVisibleReviewContentHydration(
	props: UseVisibleReviewContentHydrationProps,
): UseVisibleReviewContentHydrationResult {
	const [visibleItemIds, setVisibleItemIdsState] = useState<readonly string[]>([]);
	const [contentStateByItemId, setContentStateByItemId] = useState<
		ReadonlyMap<string, VisibleContentResourcesState>
	>(() => new Map<string, VisibleContentResourcesState>());
	const resourcesByItemIdRef = useRef<ReadonlyMap<string, BridgeCodeViewContentResources>>(
		new Map<string, BridgeCodeViewContentResources>(),
	);
	const reportedVisibleItemIdsRef = useRef<readonly string[]>([]);
	const loadAbortControllersByContentKeyRef = useRef<Map<string, AbortController>>(
		new Map<string, AbortController>(),
	);
	const scheduledContentKeysRef = useRef<Set<string>>(new Set<string>());
	const previousDemandPlanEntriesRef = useRef<readonly BridgeContentDemandPlanEntry[]>([]);
	const previousHydrationResultRef = useRef<UseVisibleReviewContentHydrationResult | null>(null);
	const isMountedRef = useRef(true);
	const loadContentResources = props.loadContentResources;

	const packageIdentityKey =
		props.reviewPackage === null
			? null
			: [
					props.reviewPackage.packageId,
					String(props.reviewPackage.reviewGeneration),
					String(props.reviewPackage.revision),
				].join(':');

	useEffect(() => {
		reportedVisibleItemIdsRef.current = [];
		abortVisibleContentLoads(loadAbortControllersByContentKeyRef.current);
		scheduledContentKeysRef.current.clear();
		previousDemandPlanEntriesRef.current = [];
		setVisibleItemIdsState([]);
		setContentStateByItemId(new Map<string, VisibleContentResourcesState>());
		resourcesByItemIdRef.current = new Map<string, BridgeCodeViewContentResources>();
	}, [packageIdentityKey]);

	const setVisibleItemIds = useCallback(
		(itemIds: readonly string[]): void => {
			reportedVisibleItemIdsRef.current = itemIds;
			const nextItemIds = normalizeVisibleReviewItemIds({
				itemIds,
				reviewPackage: props.reviewPackage,
				selectedItemId: props.selectedItemId,
			});
			setVisibleItemIdsState((currentItemIds: readonly string[]): readonly string[] =>
				stringArraysEqual(currentItemIds, nextItemIds) ? currentItemIds : nextItemIds,
			);
		},
		[props.reviewPackage, props.selectedItemId],
	);

	useEffect((): (() => void) | void => {
		const nextItemIds = normalizeVisibleReviewItemIds({
			itemIds: reportedVisibleItemIdsRef.current,
			reviewPackage: props.reviewPackage,
			selectedItemId: props.selectedItemId,
		});
		setVisibleItemIdsState((currentItemIds: readonly string[]): readonly string[] =>
			stringArraysEqual(currentItemIds, nextItemIds) ? currentItemIds : nextItemIds,
		);
	}, [props.reviewPackage, props.selectedItemId]);

	useEffect((): (() => void) => {
		isMountedRef.current = true;
		const loadAbortControllersByContentKey = loadAbortControllersByContentKeyRef.current;
		return (): void => {
			isMountedRef.current = false;
			abortVisibleContentLoads(loadAbortControllersByContentKey);
		};
	}, []);
	useEffect(() => {
		if (!props.visibleHydrationPaused) {
			return;
		}
		if (shouldAbortVisibleContentLoadsForPause()) {
			abortVisibleContentLoads(loadAbortControllersByContentKeyRef.current);
		}
		scheduledContentKeysRef.current.clear();
	}, [props.visibleHydrationPaused]);
	useEffect((): void => {
		if (props.visibleHydrationPaused) {
			return;
		}
		setContentStateByItemId(
			(currentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>) =>
				promoteDeferredVisibleContentStates(currentStateByItemId),
		);
	}, [props.visibleHydrationPaused]);
	const [abortedRearmVersion, setAbortedRearmVersion] = useState(0);
	const abortedRearmScheduledRef = useRef(false);
	const visibleHydrationSnapshotRef = useRef<VisibleReviewContentAbortRearmSnapshot>({
		contentInvalidationVersion: props.contentInvalidationVersion,
		reviewPackage: props.reviewPackage,
		selectedItemId: props.selectedItemId,
		visibleHydrationPaused: props.visibleHydrationPaused,
		visibleItemIds,
	});
	visibleHydrationSnapshotRef.current = {
		contentInvalidationVersion: props.contentInvalidationVersion,
		reviewPackage: props.reviewPackage,
		selectedItemId: props.selectedItemId,
		visibleHydrationPaused: props.visibleHydrationPaused,
		visibleItemIds,
	};
	publishVisibleHydrationStateProbe(
		deriveVisibleHydrationStateProbe({
			contentStateByItemId,
			pausedNow: props.visibleHydrationPaused,
			reportedVisibleItemCount: reportedVisibleItemIdsRef.current.length,
			trackedVisibleItemIds: visibleItemIds,
		}),
	);

	useEffect((): (() => void) | void => {
		if (props.reviewPackage === null) {
			return;
		}
		const currentReviewPackage = props.reviewPackage;
		const derivedDemand = deriveVisibleReviewContentLoadPlans({
			contentInvalidationVersion: props.contentInvalidationVersion,
			contentRegistry: props.contentRegistry,
			contentStateByItemId,
			generation: currentReviewPackage.reviewGeneration,
			paused: props.visibleHydrationPaused,
			previousEntries: previousDemandPlanEntriesRef.current,
			reviewPackage: currentReviewPackage,
			resolveDescriptorRef: props.resolveDescriptorRef,
			scheduledContentKeys: scheduledContentKeysRef.current,
			selectedItemId: props.selectedItemId,
			visibleItemIds,
		});
		previousDemandPlanEntriesRef.current = derivedDemand.reconciledPlan.entries;
		const loadPlans = derivedDemand.loadPlans.filter((loadPlan): boolean => {
			const currentState = contentStateByItemId.get(loadPlan.itemId);
			return !(
				scheduledContentKeysRef.current.has(loadPlan.contentKey) ||
				(currentState?.contentKey === loadPlan.contentKey &&
					(currentState.status === 'loading' || currentState.status === 'ready'))
			);
		});
		const visibleLoadingCount = countVisibleContentStatesWithStatus({
			contentStateByItemId,
			status: 'loading',
		});
		const loadPlanCount = visibleReviewContentLoadPlanCount({
			concurrentLoadLimit: visibleContentHydrationConcurrentLoadLimit,
			loadingCount: visibleLoadingCount,
			requestedLoadCount: loadPlans.length,
			scheduledCount: scheduledContentKeysRef.current.size,
		});
		if (loadPlanCount === 0) {
			return;
		}
		const boundedLoadPlans = loadPlans.slice(0, loadPlanCount);
		for (const loadPlan of boundedLoadPlans) {
			scheduledContentKeysRef.current.add(loadPlan.contentKey);
		}
		const dispatchDelayMilliseconds = boundedLoadPlans.every(
			(loadPlan): boolean => loadPlan.interest === 'nearby',
		)
			? 0
			: visibleContentHydrationDispatchDelayMilliseconds;
		const dispatchTimeoutId = setTimeout((): void => {
			setContentStateByItemId(
				(currentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>) => {
					const nextStateByItemId = new Map(currentStateByItemId);
					for (const loadPlan of boundedLoadPlans) {
						nextStateByItemId.set(loadPlan.itemId, {
							contentKey: loadPlan.contentKey,
							itemId: loadPlan.itemId,
							status: 'loading',
						});
					}
					return nextStateByItemId;
				},
			);
			for (const loadPlan of boundedLoadPlans) {
				const loadAbortController = new AbortController();
				loadAbortControllersByContentKeyRef.current.set(loadPlan.contentKey, loadAbortController);
				const recoverAbortedLoadState = (): void => {
					if (!isMountedRef.current) {
						return;
					}
					setContentStateByItemId(
						(currentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>) =>
							recoverAbortedVisibleContentLoadState({
								contentKey: loadPlan.contentKey,
								currentStateByItemId,
								itemId: loadPlan.itemId,
							}),
					);
				};
				loadAbortController.signal.addEventListener('abort', recoverAbortedLoadState, {
					once: true,
				});
				recordBridgeViewerContentQueueTelemetry({
					telemetryRecorder: props.telemetryRecorder,
					parentTraceContext: props.telemetryParentTraceContext,
					item: loadPlan.item,
					interest: loadPlan.interest,
				});
				const traceContext =
					props.telemetryRecorder.isEnabled('web') && props.telemetryParentTraceContext !== null
						? createBridgeChildTraceContext(props.telemetryParentTraceContext)
						: null;
				void loadContentResources({
					reviewPackage: currentReviewPackage,
					interest: loadPlan.interest,
					itemId: loadPlan.itemId,
					signal: loadAbortController.signal,
					traceContext,
					contentRegistry: props.contentRegistry,
					telemetryRecorder: props.telemetryRecorder,
				})
					.then((loadResult): void => {
						if (loadAbortController.signal.aborted) {
							return;
						}
						const normalizedLoadResult = normalizeVisibleReviewContentLoadResult(loadResult);
						setContentStateByItemId(
							(currentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>) => {
								const currentState = currentStateByItemId.get(loadPlan.itemId);
								if (
									!shouldAcceptVisibleReviewContentReadyResult({
										contentKey: loadPlan.contentKey,
										currentState,
									})
								) {
									if (normalizedLoadResult.status === 'ready') {
										recordVisibleHydrationReadyResultDiscard({
											hadState: currentState !== undefined,
											pausedNow: visibleHydrationSnapshotRef.current.visibleHydrationPaused,
										});
									}
									return currentStateByItemId;
								}
								if (currentState === undefined && normalizedLoadResult.status !== 'ready') {
									return currentStateByItemId;
								}
								if (normalizedLoadResult.status === 'ready') {
									const nextResourcesByItemId = new Map(resourcesByItemIdRef.current);
									nextResourcesByItemId.delete(loadPlan.itemId);
									nextResourcesByItemId.set(loadPlan.itemId, normalizedLoadResult.resources);
									resourcesByItemIdRef.current = nextResourcesByItemId;
								}
								const nextStateByItemId = new Map(currentStateByItemId);
								nextStateByItemId.set(
									loadPlan.itemId,
									normalizedLoadResult.status === 'ready'
										? visibleContentStateForAcceptedReadyResult({
												contentKey: loadPlan.contentKey,
												itemId: loadPlan.itemId,
												pausedNow: visibleHydrationSnapshotRef.current.visibleHydrationPaused,
												selectedItemId: visibleHydrationSnapshotRef.current.selectedItemId ?? null,
											})
										: {
												contentKey: loadPlan.contentKey,
												itemId: loadPlan.itemId,
												status: normalizedLoadResult.status,
											},
								);
								return nextStateByItemId;
							},
						);
						if (
							shouldRetryVisibleContentAfterDeferredLoad({
								loadResult: normalizedLoadResult,
								snapshot: visibleHydrationSnapshotRef.current,
							})
						) {
							scheduleVisibleHydrationRetry({
								scheduledRef: abortedRearmScheduledRef,
								setRetryVersion: setAbortedRearmVersion,
							});
						}
					})
					.catch((): void => {
						if (loadAbortController.signal.aborted) {
							return;
						}
						setContentStateByItemId(
							(currentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>) => {
								const currentState = currentStateByItemId.get(loadPlan.itemId);
								if (currentState?.contentKey !== loadPlan.contentKey) {
									return currentStateByItemId;
								}
								const nextStateByItemId = new Map(currentStateByItemId);
								nextStateByItemId.set(loadPlan.itemId, {
									contentKey: loadPlan.contentKey,
									itemId: loadPlan.itemId,
									status: 'failed',
								});
								return nextStateByItemId;
							},
						);
					})
					.finally((): void => {
						const loadWasAborted = loadAbortController.signal.aborted;
						loadAbortController.signal.removeEventListener('abort', recoverAbortedLoadState);
						scheduledContentKeysRef.current.delete(loadPlan.contentKey);
						const currentController = loadAbortControllersByContentKeyRef.current.get(
							loadPlan.contentKey,
						);
						if (currentController === loadAbortController) {
							loadAbortControllersByContentKeyRef.current.delete(loadPlan.contentKey);
						}
						if (
							loadWasAborted &&
							shouldSweepVisibleContentAfterAbortedLoad({
								...visibleHydrationSnapshotRef.current,
							})
						) {
							scheduleVisibleHydrationRetry({
								scheduledRef: abortedRearmScheduledRef,
								setRetryVersion: setAbortedRearmVersion,
							});
						}
					});
			}
		}, dispatchDelayMilliseconds);
		const loadAbortControllersByContentKey = loadAbortControllersByContentKeyRef.current;
		const scheduledContentKeys = scheduledContentKeysRef.current;
		return (): void => {
			clearTimeout(dispatchTimeoutId);
			for (const loadPlan of boundedLoadPlans) {
				if (!loadAbortControllersByContentKey.has(loadPlan.contentKey)) {
					scheduledContentKeys.delete(loadPlan.contentKey);
				}
			}
		};
	}, [
		abortedRearmVersion,
		contentStateByItemId,
		props.contentRegistry,
		props.contentInvalidationVersion,
		loadContentResources,
		props.resolveDescriptorRef,
		props.reviewPackage,
		props.selectedItemId,
		props.telemetryParentTraceContext,
		props.telemetryRecorder,
		props.visibleHydrationPaused,
		visibleItemIds,
	]);

	useEffect((): void => {
		const retainedContentKeys = new Set<string>();
		if (props.reviewPackage !== null) {
			for (const itemId of props.reviewPackage.orderedItemIds) {
				const item = props.reviewPackage.itemsById[itemId];
				if (item !== undefined) {
					retainedContentKeys.add(
						makeVisibleReviewItemContentResourcesKey({
							contentInvalidationVersion: props.contentInvalidationVersion,
							item,
							reviewPackage: props.reviewPackage,
						}),
					);
				}
			}
		}
		abortVisibleContentLoadsExcept(
			loadAbortControllersByContentKeyRef.current,
			retainedContentKeys,
		);
		for (const scheduledContentKey of scheduledContentKeysRef.current) {
			if (!retainedContentKeys.has(scheduledContentKey)) {
				scheduledContentKeysRef.current.delete(scheduledContentKey);
			}
		}
		setContentStateByItemId(
			(currentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>) => {
				const pruned = pruneVisibleReviewContentHydrationCaches({
					contentStateByItemId: currentStateByItemId,
					resourcesByItemId: resourcesByItemIdRef.current,
					retainedContentKeys,
					visibleItemIds,
				});
				if (!mapEntriesEqual(resourcesByItemIdRef.current, pruned.resourcesByItemId)) {
					resourcesByItemIdRef.current = pruned.resourcesByItemId;
				}
				return mapEntriesEqual(currentStateByItemId, pruned.contentStateByItemId)
					? currentStateByItemId
					: pruned.contentStateByItemId;
			},
		);
	}, [props.contentInvalidationVersion, props.reviewPackage, visibleItemIds]);

	return useMemo((): UseVisibleReviewContentHydrationResult => {
		const result = createVisibleReviewContentHydrationResult({
			contentStateByItemId,
			previousResult: previousHydrationResultRef.current,
			resourcesByItemId: resourcesByItemIdRef.current,
			setVisibleItemIds,
			visibleItemIds,
		});
		previousHydrationResultRef.current = result;
		return result;
	}, [contentStateByItemId, setVisibleItemIds, visibleItemIds]);
}

function stringArraysEqual(left: readonly string[], right: readonly string[]): boolean {
	return (
		left.length === right.length && left.every((value, index): boolean => value === right[index])
	);
}
