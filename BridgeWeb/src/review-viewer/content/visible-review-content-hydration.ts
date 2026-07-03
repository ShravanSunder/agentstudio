import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Dispatch, SetStateAction } from 'react';

import type {
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
import type { ReviewContentDemandLoadResult } from './review-content-demand-loader.js';
import type { LoadReviewItemContentResourcesProps } from './review-content-loader.js';
import type { BridgeReviewContentRegistry } from './review-content-registry.js';

export interface UseVisibleReviewContentHydrationProps {
	readonly contentRegistry: BridgeReviewContentRegistry;
	readonly loadContentResources: (
		props: LoadReviewItemContentResourcesProps,
	) => Promise<VisibleReviewContentLoadResult>;
	readonly reviewPackage: BridgeReviewPackage | null;
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

export interface VisibleContentResourcesState {
	readonly contentKey: string;
	readonly itemId: string;
	readonly retryAfterVersion?: number;
	readonly status: 'deferred' | 'loading' | 'ready' | 'failed';
}

export const visibleContentHydrationItemLimit = 12;
export const visibleContentHydrationConcurrentLoadLimit = 2;
export const visibleContentHydrationDispatchDelayMilliseconds = 64;
const maxVisibleContentDeferredRetries = 1;
const exhaustedVisibleContentRetryVersion = Number.MAX_SAFE_INTEGER;

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
	const deferredRetryCountByContentKeyRef = useRef<Map<string, number>>(new Map());
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
		deferredRetryCountByContentKeyRef.current.clear();
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

	useEffect(
		(): (() => void) => () => {
			abortVisibleContentLoads(loadAbortControllersByContentKeyRef.current);
		},
		[],
	);
	useEffect(() => {
		if (!props.visibleHydrationPaused) {
			return;
		}
		if (shouldAbortVisibleContentLoadsForPause()) {
			abortVisibleContentLoads(loadAbortControllersByContentKeyRef.current);
		}
		scheduledContentKeysRef.current.clear();
		setContentStateByItemId(
			(currentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>) => {
				const nextStateByItemId = new Map<string, VisibleContentResourcesState>();
				for (const [itemId, state] of currentStateByItemId) {
					if (state.status === 'ready' || state.status === 'failed') {
						nextStateByItemId.set(itemId, state);
					}
				}
				return mapEntriesEqual(currentStateByItemId, nextStateByItemId)
					? currentStateByItemId
					: nextStateByItemId;
			},
		);
	}, [props.visibleHydrationPaused]);
	const [deferredRetryVersion, setDeferredRetryVersion] = useState(0);
	const deferredRetryScheduledRef = useRef(false);

	useEffect((): (() => void) | void => {
		if (
			props.reviewPackage === null ||
			props.visibleHydrationPaused ||
			visibleItemIds.length === 0
		) {
			return;
		}
		const currentReviewPackage = props.reviewPackage;
		const loadPlans = visibleItemIds.flatMap((itemId): readonly VisibleReviewContentLoadPlan[] => {
			const item = currentReviewPackage.itemsById[itemId];
			if (item === undefined) {
				return [];
			}
			const contentKey = makeVisibleReviewItemContentResourcesKey({
				contentInvalidationVersion: props.contentInvalidationVersion,
				item,
				reviewPackage: currentReviewPackage,
			});
			const currentState = contentStateByItemId.get(itemId);
			if (
				scheduledContentKeysRef.current.has(contentKey) ||
				(currentState?.contentKey === contentKey &&
					(currentState.status === 'loading' ||
						currentState.status === 'ready' ||
						currentState.status === 'failed' ||
						(currentState.status === 'deferred' &&
							currentState.retryAfterVersion !== undefined &&
							currentState.retryAfterVersion > deferredRetryVersion)))
			) {
				return [];
			}
			return [{ contentKey, item, itemId }];
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
				recordBridgeViewerContentQueueTelemetry({
					telemetryRecorder: props.telemetryRecorder,
					parentTraceContext: props.telemetryParentTraceContext,
					item: loadPlan.item,
					interest: 'visible',
				});
				const traceContext =
					props.telemetryRecorder.isEnabled('web') && props.telemetryParentTraceContext !== null
						? createBridgeChildTraceContext(props.telemetryParentTraceContext)
						: null;
				void loadContentResources({
					reviewPackage: currentReviewPackage,
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
						let shouldScheduleDeferredRetry = false;
						setContentStateByItemId(
							(currentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>) => {
								const currentState = currentStateByItemId.get(loadPlan.itemId);
								if (currentState?.contentKey !== loadPlan.contentKey) {
									return currentStateByItemId;
								}
								if (normalizedLoadResult.status === 'ready') {
									deferredRetryCountByContentKeyRef.current.delete(loadPlan.contentKey);
									const nextResourcesByItemId = new Map(resourcesByItemIdRef.current);
									nextResourcesByItemId.set(loadPlan.itemId, normalizedLoadResult.resources);
									resourcesByItemIdRef.current = nextResourcesByItemId;
								}
								if (normalizedLoadResult.status === 'failed') {
									deferredRetryCountByContentKeyRef.current.delete(loadPlan.contentKey);
								}
								const deferredRetryDecision =
									normalizedLoadResult.status === 'deferred'
										? nextDeferredVisibleContentRetryDecision({
												contentKey: loadPlan.contentKey,
												currentRetryVersion: deferredRetryVersion,
												retryCountsByContentKey: deferredRetryCountByContentKeyRef.current,
											})
										: null;
								shouldScheduleDeferredRetry = deferredRetryDecision?.kind === 'scheduled';
								const nextStateByItemId = new Map(currentStateByItemId);
								nextStateByItemId.set(loadPlan.itemId, {
									contentKey: loadPlan.contentKey,
									itemId: loadPlan.itemId,
									...(normalizedLoadResult.status === 'deferred'
										? {
												retryAfterVersion:
													deferredRetryDecision?.retryAfterVersion ??
													exhaustedVisibleContentRetryVersion,
											}
										: {}),
									status: normalizedLoadResult.status,
								});
								return nextStateByItemId;
							},
						);
						if (shouldScheduleDeferredRetry) {
							scheduleVisibleHydrationRetry({
								scheduledRef: deferredRetryScheduledRef,
								setDeferredRetryVersion,
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
						scheduledContentKeysRef.current.delete(loadPlan.contentKey);
						const currentController = loadAbortControllersByContentKeyRef.current.get(
							loadPlan.contentKey,
						);
						if (currentController === loadAbortController) {
							loadAbortControllersByContentKeyRef.current.delete(loadPlan.contentKey);
						}
					});
			}
		}, visibleContentHydrationDispatchDelayMilliseconds);
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
		contentStateByItemId,
		deferredRetryVersion,
		setDeferredRetryVersion,
		props.contentRegistry,
		props.contentInvalidationVersion,
		loadContentResources,
		props.reviewPackage,
		props.telemetryParentTraceContext,
		props.telemetryRecorder,
		props.visibleHydrationPaused,
		visibleItemIds,
	]);

	useEffect((): void => {
		const visibleItemIdSet = new Set(visibleItemIds);
		const retainedContentKeys = new Set<string>();
		if (props.reviewPackage !== null) {
			for (const itemId of visibleItemIds) {
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
		pruneDeferredRetryCountsExcept(deferredRetryCountByContentKeyRef.current, retainedContentKeys);
		setContentStateByItemId(
			(currentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>) => {
				const nextStateByItemId = new Map<string, VisibleContentResourcesState>();
				for (const [itemId, state] of currentStateByItemId) {
					if (visibleItemIdSet.has(itemId)) {
						nextStateByItemId.set(itemId, state);
					}
				}
				return mapEntriesEqual(currentStateByItemId, nextStateByItemId)
					? currentStateByItemId
					: nextStateByItemId;
			},
		);
		const nextResourcesByItemId = new Map<string, BridgeCodeViewContentResources>();
		for (const [itemId, resources] of resourcesByItemIdRef.current) {
			if (visibleItemIdSet.has(itemId)) {
				nextResourcesByItemId.set(itemId, resources);
			}
		}
		if (!mapEntriesEqual(resourcesByItemIdRef.current, nextResourcesByItemId)) {
			resourcesByItemIdRef.current = nextResourcesByItemId;
		}
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

export function createVisibleReviewContentHydrationResult(props: {
	readonly contentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>;
	readonly resourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>;
	readonly setVisibleItemIds: (itemIds: readonly string[]) => void;
	readonly visibleHydrationPaused: boolean;
	readonly visibleItemIds: readonly string[];
}): UseVisibleReviewContentHydrationResult {
	if (props.visibleHydrationPaused) {
		return {
			setVisibleItemIds: props.setVisibleItemIds,
			visibleContentResourcesByItemId: new Map<string, BridgeCodeViewContentResources>(),
			visibleFailedItemIds: new Set<string>(),
			visibleItemIds: [],
			visibleLoadingItemIds: new Set<string>(),
			visibleLoadingItemCount: 0,
			visibleReadyItemCount: 0,
		};
	}
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
	readonly item: BridgeReviewItemDescriptor;
	readonly itemId: string;
}

type DeferredVisibleContentRetryDecision =
	| {
			readonly kind: 'scheduled';
			readonly retryAfterVersion: number;
	  }
	| {
			readonly kind: 'exhausted';
			readonly retryAfterVersion: number;
	  };

export function makeReviewItemContentResourcesKey(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly reviewPackage: BridgeReviewPackage;
}): string {
	const roleKeys = [
		props.item.contentRoles.base,
		props.item.contentRoles.head,
		props.item.contentRoles.diff,
		props.item.contentRoles.file,
	]
		.map((handle): string => handle?.cacheKey ?? 'none')
		.join('|');
	return [
		props.reviewPackage.packageId,
		String(props.reviewPackage.reviewGeneration),
		String(props.reviewPackage.revision),
		props.item.itemId,
		String(props.item.itemVersion),
		props.item.cacheKey,
		roleKeys,
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
		if (uniqueItemIds.length >= visibleContentHydrationItemLimit) {
			break;
		}
	}
	return uniqueItemIds;
}

export function visibleReviewContentLoadPlanCount(props: {
	readonly loadingCount: number;
	readonly requestedLoadCount: number;
	readonly scheduledCount?: number;
}): number {
	const availableLoadSlots = Math.max(
		0,
		visibleContentHydrationConcurrentLoadLimit - props.loadingCount - (props.scheduledCount ?? 0),
	);
	return Math.min(props.requestedLoadCount, availableLoadSlots);
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

function nextDeferredVisibleContentRetryDecision(props: {
	readonly contentKey: string;
	readonly currentRetryVersion: number;
	readonly retryCountsByContentKey: Map<string, number>;
}): DeferredVisibleContentRetryDecision {
	const retryCount = (props.retryCountsByContentKey.get(props.contentKey) ?? 0) + 1;
	props.retryCountsByContentKey.set(props.contentKey, retryCount);
	if (retryCount <= maxVisibleContentDeferredRetries) {
		return {
			kind: 'scheduled',
			retryAfterVersion: props.currentRetryVersion + 1,
		};
	}
	return {
		kind: 'exhausted',
		retryAfterVersion: exhaustedVisibleContentRetryVersion,
	};
}

function pruneDeferredRetryCountsExcept(
	deferredRetryCountsByContentKey: Map<string, number>,
	retainedContentKeys: ReadonlySet<string>,
): void {
	for (const contentKey of deferredRetryCountsByContentKey.keys()) {
		if (retainedContentKeys.has(contentKey)) {
			continue;
		}
		deferredRetryCountsByContentKey.delete(contentKey);
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
	readonly setDeferredRetryVersion: Dispatch<SetStateAction<number>>;
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
		props.setDeferredRetryVersion((currentVersion: number): number => currentVersion + 1);
	});
}
