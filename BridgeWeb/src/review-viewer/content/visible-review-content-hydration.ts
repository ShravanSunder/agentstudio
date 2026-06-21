import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type { BridgeContentFetch } from '../../foundation/content/content-resource-loader.js';
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
import { loadReviewItemContentResources } from './review-content-loader.js';
import type { BridgeReviewContentRegistry } from './review-content-registry.js';

export interface UseVisibleReviewContentHydrationProps {
	readonly contentRegistry: BridgeReviewContentRegistry;
	readonly fetchContent?: BridgeContentFetch;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly telemetryParentTraceContext: BridgeTraceContext | null;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
}

export interface UseVisibleReviewContentHydrationResult {
	readonly setVisibleItemIds: (itemIds: readonly string[]) => void;
	readonly visibleContentResourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>;
	readonly visibleLoadingItemIds: ReadonlySet<string>;
	readonly visibleLoadingItemCount: number;
	readonly visibleReadyItemCount: number;
}

interface VisibleContentResourcesState {
	readonly contentKey: string;
	readonly itemId: string;
	readonly status: 'loading' | 'ready' | 'failed';
}

const visibleContentHydrationItemLimit = 96;

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

	const packageIdentityKey =
		props.reviewPackage === null
			? null
			: [
					props.reviewPackage.packageId,
					String(props.reviewPackage.reviewGeneration),
					String(props.reviewPackage.revision),
				].join(':');

	useEffect((): void => {
		reportedVisibleItemIdsRef.current = [];
		abortVisibleContentLoads(loadAbortControllersByContentKeyRef.current);
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

	useEffect((): void => {
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

	useEffect((): void => {
		if (props.reviewPackage === null || visibleItemIds.length === 0) {
			return;
		}
		const currentReviewPackage = props.reviewPackage;
		const loadPlans = visibleItemIds.flatMap((itemId): readonly VisibleReviewContentLoadPlan[] => {
			const item = currentReviewPackage.itemsById[itemId];
			if (item === undefined) {
				return [];
			}
			const contentKey = makeReviewItemContentResourcesKey({
				item,
				reviewPackage: currentReviewPackage,
			});
			const currentState = contentStateByItemId.get(itemId);
			if (
				currentState?.contentKey === contentKey &&
				(currentState.status === 'loading' ||
					currentState.status === 'ready' ||
					currentState.status === 'failed')
			) {
				return [];
			}
			return [{ contentKey, item, itemId }];
		});
		if (loadPlans.length === 0) {
			return;
		}
		setContentStateByItemId(
			(currentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>) => {
				const nextStateByItemId = new Map(currentStateByItemId);
				for (const loadPlan of loadPlans) {
					nextStateByItemId.set(loadPlan.itemId, {
						contentKey: loadPlan.contentKey,
						itemId: loadPlan.itemId,
						status: 'loading',
					});
				}
				return nextStateByItemId;
			},
		);
		for (const loadPlan of loadPlans) {
			const loadAbortController = new AbortController();
			loadAbortControllersByContentKeyRef.current.set(loadPlan.contentKey, loadAbortController);
			recordBridgeViewerContentQueueTelemetry({
				telemetryRecorder: props.telemetryRecorder,
				parentTraceContext: props.telemetryParentTraceContext,
				item: loadPlan.item,
			});
			const traceContext =
				props.telemetryRecorder.isEnabled('web') && props.telemetryParentTraceContext !== null
					? createBridgeChildTraceContext(props.telemetryParentTraceContext)
					: null;
			const loadProps =
				props.fetchContent === undefined
					? {
							reviewPackage: currentReviewPackage,
							itemId: loadPlan.itemId,
							signal: loadAbortController.signal,
							traceContext,
							contentRegistry: props.contentRegistry,
							telemetryRecorder: props.telemetryRecorder,
						}
					: {
							reviewPackage: currentReviewPackage,
							itemId: loadPlan.itemId,
							fetchContent: props.fetchContent,
							signal: loadAbortController.signal,
							traceContext,
							contentRegistry: props.contentRegistry,
							telemetryRecorder: props.telemetryRecorder,
						};
			void loadReviewItemContentResources(loadProps)
				.then((resources): void => {
					if (loadAbortController.signal.aborted) {
						return;
					}
					setContentStateByItemId(
						(currentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>) => {
							const currentState = currentStateByItemId.get(loadPlan.itemId);
							if (currentState?.contentKey !== loadPlan.contentKey) {
								return currentStateByItemId;
							}
							if (resources !== null) {
								const nextResourcesByItemId = new Map(resourcesByItemIdRef.current);
								nextResourcesByItemId.set(loadPlan.itemId, resources);
								resourcesByItemIdRef.current = nextResourcesByItemId;
							}
							const nextStateByItemId = new Map(currentStateByItemId);
							nextStateByItemId.set(loadPlan.itemId, {
								contentKey: loadPlan.contentKey,
								itemId: loadPlan.itemId,
								status: resources === null ? 'failed' : 'ready',
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
					const currentController = loadAbortControllersByContentKeyRef.current.get(
						loadPlan.contentKey,
					);
					if (currentController === loadAbortController) {
						loadAbortControllersByContentKeyRef.current.delete(loadPlan.contentKey);
					}
				});
		}
	}, [
		contentStateByItemId,
		props.contentRegistry,
		props.fetchContent,
		props.reviewPackage,
		props.telemetryParentTraceContext,
		props.telemetryRecorder,
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
						makeReviewItemContentResourcesKey({
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
	}, [props.reviewPackage, visibleItemIds]);

	return useMemo((): UseVisibleReviewContentHydrationResult => {
		const visibleContentResourcesByItemId = new Map<string, BridgeCodeViewContentResources>();
		const visibleLoadingItemIds = new Set<string>();
		let visibleLoadingItemCount = 0;
		let visibleReadyItemCount = 0;
		for (const itemId of visibleItemIds) {
			const currentState = contentStateByItemId.get(itemId);
			if (currentState?.status === 'loading') {
				visibleLoadingItemIds.add(itemId);
				visibleLoadingItemCount += 1;
				continue;
			}
			const resources = resourcesByItemIdRef.current.get(itemId);
			if (currentState?.status === 'ready' && resources !== undefined) {
				visibleReadyItemCount += 1;
				visibleContentResourcesByItemId.set(itemId, resources);
			}
		}
		return {
			setVisibleItemIds,
			visibleContentResourcesByItemId,
			visibleLoadingItemIds,
			visibleLoadingItemCount,
			visibleReadyItemCount,
		};
	}, [contentStateByItemId, setVisibleItemIds, visibleItemIds]);
}

interface VisibleReviewContentLoadPlan {
	readonly contentKey: string;
	readonly item: BridgeReviewItemDescriptor;
	readonly itemId: string;
}

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

function normalizeVisibleReviewItemIds(props: {
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
		if (seenItemIds.has(itemId) || props.reviewPackage.itemsById[itemId] === undefined) {
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
