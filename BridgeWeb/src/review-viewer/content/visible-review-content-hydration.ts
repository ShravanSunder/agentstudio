import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Dispatch, SetStateAction } from 'react';

import {
	reconcileBridgeContentDemand,
	type BridgeContentDemandCandidate,
	type BridgeContentDemandPlan,
	type BridgeContentDemandPlanEntry,
} from '../../core/demand/bridge-content-demand-reconciler.js';
import type { BridgeContentDemandRole } from '../../core/models/bridge-demand-models.js';
import type { BridgeDescriptorRef } from '../../core/models/bridge-resource-descriptor.js';
import { mapReviewDemandStimulusToContentDemandCandidates } from '../../features/review/demand/review-demand-policy.js';
import type {
	BridgeContentHandle,
	BridgeReviewItemDescriptor,
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
import {
	demandFreshnessKeyForReviewDescriptorRef,
	demandKeysForPlan,
	demandPlansForReviewItem,
} from './review-content-demand-policy.js';
import type { LoadReviewItemContentResourcesProps } from './review-content-loader.js';
import type { BridgeReviewContentRegistry } from './review-content-registry.js';
import {
	deriveVisibleHydrationStateProbe,
	pruneVisibleReviewContentHydrationCaches,
	publishVisibleHydrationStateProbe,
	recordVisibleHydrationReadyResultDiscard,
	shouldAcceptVisibleReviewContentReadyResult,
	type VisibleContentResourcesState,
} from './visible-review-content-hydration-support.js';

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
	const [abortedRearmVersion, setAbortedRearmVersion] = useState(0);
	const abortedRearmScheduledRef = useRef(false);
	const visibleHydrationSnapshotRef = useRef<VisibleReviewContentAbortRearmSnapshot>({
		contentInvalidationVersion: props.contentInvalidationVersion,
		reviewPackage: props.reviewPackage,
		visibleHydrationPaused: props.visibleHydrationPaused,
		visibleItemIds,
	});
	visibleHydrationSnapshotRef.current = {
		contentInvalidationVersion: props.contentInvalidationVersion,
		reviewPackage: props.reviewPackage,
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
								nextStateByItemId.set(loadPlan.itemId, {
									contentKey: loadPlan.contentKey,
									itemId: loadPlan.itemId,
									status: normalizedLoadResult.status,
								});
								return nextStateByItemId;
							},
						);
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

	return useMemo(
		(): UseVisibleReviewContentHydrationResult =>
			createVisibleReviewContentHydrationResult({
				contentStateByItemId,
				resourcesByItemId: resourcesByItemIdRef.current,
				setVisibleItemIds,
				visibleHydrationPaused: props.visibleHydrationPaused,
				visibleItemIds,
			}),
		[contentStateByItemId, props.visibleHydrationPaused, setVisibleItemIds, visibleItemIds],
	);
}

export interface DeriveVisibleReviewContentLoadPlansProps {
	readonly contentInvalidationVersion: number;
	readonly contentRegistry: Pick<BridgeReviewContentRegistry, 'peekResource'>;
	readonly contentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>;
	readonly generation: number;
	readonly paused: boolean;
	readonly previousEntries: readonly BridgeContentDemandPlanEntry[];
	readonly reviewPackage: BridgeReviewPackage;
	readonly resolveDescriptorRef: (handle: BridgeContentHandle) => BridgeDescriptorRef | null;
	readonly scheduledContentKeys: ReadonlySet<string>;
	readonly selectedItemId: string | null;
	readonly visibleItemIds: readonly string[];
}

export interface DerivedVisibleReviewContentLoadPlans {
	readonly loadPlans: readonly VisibleReviewContentLoadPlan[];
	readonly reconciledPlan: BridgeContentDemandPlan;
}

export function deriveVisibleReviewContentLoadPlans(
	props: DeriveVisibleReviewContentLoadPlansProps,
): DerivedVisibleReviewContentLoadPlans {
	const itemContexts = visibleReviewContentDemandItemContexts(props);
	const demandCandidates: BridgeContentDemandCandidate[] = [];
	const loadedDedupeKeys = new Set<string>();
	const inFlightDedupeKeys = new Set<string>();
	const contextByDedupeKey = new Map<string, VisibleReviewContentDemandItemContext>();
	for (const itemContext of itemContexts) {
		const candidateResult = contentDemandCandidatesForItemContext({
			contentRegistry: props.contentRegistry,
			itemContext,
			resolveDescriptorRef: props.resolveDescriptorRef,
		});
		for (const loadedDedupeKey of candidateResult.loadedDedupeKeys) {
			loadedDedupeKeys.add(loadedDedupeKey);
		}
		for (const candidate of candidateResult.candidates) {
			demandCandidates.push(candidate);
			contextByDedupeKey.set(candidate.intent.dedupeKey, itemContext);
			if (
				props.scheduledContentKeys.has(itemContext.contentKey) ||
				props.contentStateByItemId.get(itemContext.itemId)?.status === 'loading'
			) {
				inFlightDedupeKeys.add(candidate.intent.dedupeKey);
			}
		}
	}
	const reconciledPlan = reconcileBridgeContentDemand({
		candidates: demandCandidates,
		generation: props.generation,
		inFlightDedupeKeys,
		loadedDedupeKeys,
		paused: props.paused,
		previousEntries: props.previousEntries,
	});
	const loadPlans = loadPlansForReconciledEntries({
		contextByDedupeKey,
		entries: reconciledPlan.entries,
	});
	return { loadPlans, reconciledPlan };
}

interface VisibleReviewContentDemandItemContext {
	readonly contentKey: string;
	readonly interest: VisibleReviewContentDemandInterest | 'selected';
	readonly item: BridgeReviewItemDescriptor;
	readonly itemId: string;
}

function visibleReviewContentDemandItemContexts(
	props: DeriveVisibleReviewContentLoadPlansProps,
): readonly VisibleReviewContentDemandItemContext[] {
	const itemContexts: VisibleReviewContentDemandItemContext[] = [];
	const seenItemIds = new Set<string>();
	const selectedItem =
		props.selectedItemId === null ? undefined : props.reviewPackage.itemsById[props.selectedItemId];
	if (selectedItem !== undefined && props.selectedItemId !== null) {
		itemContexts.push({
			contentKey: makeVisibleReviewItemContentResourcesKey({
				contentInvalidationVersion: props.contentInvalidationVersion,
				item: selectedItem,
				reviewPackage: props.reviewPackage,
			}),
			interest: 'selected',
			item: selectedItem,
			itemId: props.selectedItemId,
		});
		seenItemIds.add(props.selectedItemId);
	}
	const selectedAdjacentItemIds = new Set(
		selectedAdjacentReviewItemIds({
			reviewPackage: props.reviewPackage,
			selectedItemId: props.selectedItemId,
		}),
	);
	for (const itemId of props.visibleItemIds) {
		if (seenItemIds.has(itemId)) {
			continue;
		}
		const item = props.reviewPackage.itemsById[itemId];
		if (item === undefined) {
			continue;
		}
		itemContexts.push({
			contentKey: makeVisibleReviewItemContentResourcesKey({
				contentInvalidationVersion: props.contentInvalidationVersion,
				item,
				reviewPackage: props.reviewPackage,
			}),
			interest: selectedAdjacentItemIds.has(itemId) ? 'nearby' : 'visible',
			item,
			itemId,
		});
		seenItemIds.add(itemId);
	}
	return itemContexts;
}

function contentDemandCandidatesForItemContext(props: {
	readonly contentRegistry: Pick<BridgeReviewContentRegistry, 'peekResource'>;
	readonly itemContext: VisibleReviewContentDemandItemContext;
	readonly resolveDescriptorRef: (handle: BridgeContentHandle) => BridgeDescriptorRef | null;
}): {
	readonly candidates: readonly BridgeContentDemandCandidate[];
	readonly loadedDedupeKeys: readonly string[];
} {
	const plans = demandPlansForReviewItem({
		item: props.itemContext.item,
		interest: props.itemContext.interest,
		presentation: null,
		resolveDescriptorRef: props.resolveDescriptorRef,
	});
	if (plans === null) {
		return { candidates: [], loadedDedupeKeys: [] };
	}
	const candidates: BridgeContentDemandCandidate[] = [];
	const loadedDedupeKeys: string[] = [];
	for (const plan of plans) {
		const planCandidates = mapReviewDemandStimulusToContentDemandCandidates({
			stimulus: { kind: 'reviewDescriptorInvalidated', descriptorRef: plan.descriptorRef },
			readContext: {
				getDescriptorState: () => ({
					kind: 'valid',
					freshnessKey: demandFreshnessKeyForReviewDescriptorRef(plan.descriptorRef),
					needsBodyOrWindow: true,
				}),
				getViewInterest: () => ({ kind: props.itemContext.interest }),
				buildDemandKeys: () => demandKeysForPlan(plan, props.itemContext.interest),
			},
		});
		const cachedResource = props.contentRegistry.peekResource(plan.handle);
		for (const candidate of planCandidates) {
			if (cachedResource === null) {
				candidates.push(candidate);
				continue;
			}
			loadedDedupeKeys.push(candidate.intent.dedupeKey);
		}
	}
	return { candidates, loadedDedupeKeys };
}

function loadPlansForReconciledEntries(props: {
	readonly contextByDedupeKey: ReadonlyMap<string, VisibleReviewContentDemandItemContext>;
	readonly entries: readonly BridgeContentDemandPlanEntry[];
}): readonly VisibleReviewContentLoadPlan[] {
	const plannedItemIds = new Set<string>();
	const loadPlans: VisibleReviewContentLoadPlan[] = [];
	for (const entry of props.entries) {
		if (!entry.startEligible) {
			continue;
		}
		const interest = visibleReviewContentDemandInterestForRole(entry.role);
		if (interest === null) {
			continue;
		}
		const itemContext = props.contextByDedupeKey.get(entry.intent.dedupeKey);
		if (itemContext === undefined || plannedItemIds.has(itemContext.itemId)) {
			continue;
		}
		plannedItemIds.add(itemContext.itemId);
		loadPlans.push({
			contentKey: itemContext.contentKey,
			interest,
			item: itemContext.item,
			itemId: itemContext.itemId,
		});
	}
	return loadPlans;
}

function visibleReviewContentDemandInterestForRole(
	role: BridgeContentDemandRole,
): VisibleReviewContentDemandInterest | null {
	switch (role) {
		case 'visible':
			return 'visible';
		case 'nearby':
			return 'nearby';
		case 'selected':
		case 'speculative':
		case 'background':
			return null;
	}
	return null;
}

export function createVisibleReviewContentHydrationResult(props: {
	readonly contentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>;
	readonly resourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>;
	readonly setVisibleItemIds: (itemIds: readonly string[]) => void;
	readonly visibleHydrationPaused: boolean;
	readonly visibleItemIds: readonly string[];
}): UseVisibleReviewContentHydrationResult {
	const visibleContentResourcesByItemId = new Map<string, BridgeCodeViewContentResources>();
	const visibleFailedItemIds = new Set<string>();
	const visibleLoadingItemIds = new Set<string>();
	let visibleLoadingItemCount = 0;
	let visibleReadyItemCount = 0;
	for (const itemId of props.visibleItemIds) {
		const currentState = props.contentStateByItemId.get(itemId);
		if (currentState?.status === 'loading') {
			visibleLoadingItemIds.add(itemId);
			visibleLoadingItemCount += 1;
			continue;
		}
		if (currentState?.status === 'failed') {
			visibleFailedItemIds.add(itemId);
			continue;
		}
		const resources = props.resourcesByItemId.get(itemId);
		if (currentState?.status === 'ready' && resources !== undefined) {
			visibleReadyItemCount += 1;
			visibleContentResourcesByItemId.set(itemId, resources);
		}
	}
	return {
		setVisibleItemIds: props.setVisibleItemIds,
		visibleContentResourcesByItemId,
		visibleFailedItemIds,
		visibleItemIds: props.visibleItemIds,
		visibleLoadingItemIds,
		visibleLoadingItemCount,
		visibleReadyItemCount,
	};
}

interface VisibleReviewContentLoadPlan {
	readonly contentKey: string;
	readonly interest: VisibleReviewContentDemandInterest;
	readonly item: BridgeReviewItemDescriptor;
	readonly itemId: string;
}

interface VisibleReviewContentAbortRearmSnapshot {
	readonly contentInvalidationVersion: number;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly visibleHydrationPaused: boolean;
	readonly visibleItemIds: readonly string[];
}

export function makeReviewItemContentResourcesKey(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly reviewPackage: BridgeReviewPackage;
}): string {
	// Content-addressed content-validity key. reviewGeneration is the staleness authority and
	// per-role contentHash carries per-file freshness across revisions. This deliberately EXCLUDES
	// revision, itemVersion, and the revision-stamped item/role cacheKeys: benign metadata
	// re-delivery (extent facts, path/summary/tree updates that bump revision but not content) must
	// NOT churn this key, or it would drop already-loaded content and re-arm the loading placeholder.
	// A genuine contentHash change, a role losing its descriptor ('none'), or a generation rotation
	// still changes the key and correctly invalidates.
	const roleContentHashes = [
		props.item.contentRoles.base,
		props.item.contentRoles.head,
		props.item.contentRoles.diff,
		props.item.contentRoles.file,
	]
		.map((handle): string => handle?.contentHash ?? 'none')
		.join('|');
	return [
		props.reviewPackage.packageId,
		String(props.reviewPackage.reviewGeneration),
		props.item.itemId,
		roleContentHashes,
	].join(':');
}

function makeVisibleReviewItemContentResourcesKey(props: {
	readonly contentInvalidationVersion: number;
	readonly item: BridgeReviewItemDescriptor;
	readonly reviewPackage: BridgeReviewPackage;
}): string {
	return [
		makeReviewItemContentResourcesKey({
			item: props.item,
			reviewPackage: props.reviewPackage,
		}),
		'visibleInvalidation',
		String(props.contentInvalidationVersion),
	].join(':');
}

export function normalizeVisibleReviewItemIds(props: {
	readonly itemIds: readonly string[];
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
}): readonly string[] {
	if (props.reviewPackage === null) {
		return [];
	}
	const normalizedItemIds: string[] = [];
	normalizedItemIds.push(
		...selectedReviewItemNeighborhood(props.reviewPackage, props.selectedItemId),
	);
	normalizedItemIds.push(...props.itemIds);
	const uniqueItemIds: string[] = [];
	const seenItemIds = new Set<string>();
	for (const itemId of normalizedItemIds) {
		if (
			itemId === props.selectedItemId ||
			seenItemIds.has(itemId) ||
			props.reviewPackage.itemsById[itemId] === undefined
		) {
			continue;
		}
		seenItemIds.add(itemId);
		uniqueItemIds.push(itemId);
	}
	return uniqueItemIds;
}

export function selectedAdjacentReviewItemIds(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedItemId: string | null;
}): readonly string[] {
	return selectedReviewItemNeighborhood(props.reviewPackage, props.selectedItemId).filter(
		(itemId): boolean => itemId !== props.selectedItemId,
	);
}

export function visibleReviewContentLoadPlanCount(props: {
	readonly loadingCount: number;
	readonly requestedLoadCount: number;
	readonly scheduledCount?: number;
}): number {
	const scheduledCount = props.scheduledCount ?? 0;
	const scheduledButNotLoadingCount = Math.max(0, scheduledCount - props.loadingCount);
	const availableLoadSlots = Math.max(
		0,
		visibleContentHydrationConcurrentLoadLimit - props.loadingCount - scheduledButNotLoadingCount,
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

export function shouldAbortVisibleContentLoadsForPause(): boolean {
	return false;
}

function selectedReviewItemNeighborhood(
	reviewPackage: BridgeReviewPackage,
	selectedItemId: string | null,
): readonly string[] {
	if (selectedItemId === null) {
		return [];
	}
	const selectedIndex = reviewPackage.orderedItemIds.indexOf(selectedItemId);
	if (selectedIndex < 0) {
		return [selectedItemId];
	}
	return reviewPackage.orderedItemIds.slice(
		Math.max(0, selectedIndex - 2),
		Math.min(reviewPackage.orderedItemIds.length, selectedIndex + 3),
	);
}

function stringArraysEqual(left: readonly string[], right: readonly string[]): boolean {
	if (left.length !== right.length) {
		return false;
	}
	return left.every((value, index): boolean => value === right[index]);
}

function countVisibleContentStatesWithStatus(props: {
	readonly contentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>;
	readonly status: VisibleContentResourcesState['status'];
}): number {
	let stateCount = 0;
	for (const state of props.contentStateByItemId.values()) {
		if (state.status === props.status) {
			stateCount += 1;
		}
	}
	return stateCount;
}

function mapEntriesEqual<TKey, TValue>(
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

function abortVisibleContentLoads(
	loadAbortControllersByContentKey: Map<string, AbortController>,
): void {
	for (const loadAbortController of loadAbortControllersByContentKey.values()) {
		loadAbortController.abort();
	}
	loadAbortControllersByContentKey.clear();
}

function abortVisibleContentLoadsExcept(
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

function normalizeVisibleReviewContentLoadResult(
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

function scheduleVisibleHydrationRetry(props: {
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
