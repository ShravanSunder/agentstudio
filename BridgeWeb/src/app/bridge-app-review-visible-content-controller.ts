import type { MutableRefObject } from 'react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type { BridgeResourceExecutor } from '../core/demand/bridge-resource-executor.js';
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type { BridgeTextResourceStreamResult } from '../core/resources/bridge-resource-stream.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeCodeViewContentResources } from '../review-viewer/code-view/bridge-code-view-materialization.js';
import {
	loadReviewItemContentResourcesThroughDemandResult,
	type ReviewContentDemandTelemetry,
} from '../review-viewer/content/review-content-demand-loader.js';
import type { BridgeReviewContentRegistry } from '../review-viewer/content/review-content-registry.js';
import {
	makeReviewItemContentResourcesKey,
	type VisibleReviewContentLoadProps,
	type VisibleReviewContentLoadResult,
	useVisibleReviewContentHydration,
} from '../review-viewer/content/visible-review-content-hydration.js';
import {
	shouldPauseVisibleReviewContentHydration,
	type SelectedContentResourcesState,
} from './bridge-app-review-selection-state.js';
import type { BridgeReviewPackageTelemetryContext } from './bridge-app-review-telemetry.js';

export interface UseBridgeReviewVisibleContentControllerProps {
	readonly contentRegistry: BridgeReviewContentRegistry;
	readonly currentReviewPackageTelemetryContextRef: MutableRefObject<BridgeReviewPackageTelemetryContext | null>;
	readonly currentSelectedContentKey: string | null;
	readonly foregroundSelectedContentKey: string | null;
	readonly isActive: boolean;
	readonly isCodeViewScrollActive: boolean;
	readonly resourceExecutor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
	readonly reviewContentDescriptorRefsByHandleIdRef: MutableRefObject<
		ReadonlyMap<string, BridgeDescriptorRef>
	>;
	readonly reviewContentInvalidationVersion: number;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
	readonly selectedItemId: string | null;
	readonly setLastVisibleDemandTelemetry: (sample: ReviewContentDemandTelemetry) => void;
	readonly telemetryRecorderRef: MutableRefObject<BridgeTelemetryRecorder>;
}

export interface BridgeReviewVisibleContentController {
	readonly requestForegroundItemContent: (itemId: string) => boolean;
	readonly setVisibleContentItemIds: (itemIds: readonly string[]) => void;
	readonly visibleContentResourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>;
	readonly visibleItemIds: readonly string[];
	readonly visibleLoadingItemCount: number;
	readonly visibleLoadingItemIds: ReadonlySet<string>;
	readonly visibleReadyItemCount: number;
}

export function useBridgeReviewVisibleContentController(
	props: UseBridgeReviewVisibleContentControllerProps,
): BridgeReviewVisibleContentController {
	const {
		contentRegistry,
		currentReviewPackageTelemetryContextRef,
		currentSelectedContentKey,
		foregroundSelectedContentKey,
		isActive,
		isCodeViewScrollActive,
		resourceExecutor,
		reviewContentDescriptorRefsByHandleIdRef,
		reviewContentInvalidationVersion,
		reviewPackage,
		selectedContentResourcesState,
		selectedItemId,
		setLastVisibleDemandTelemetry,
		telemetryRecorderRef,
	} = props;
	const [
		foregroundExpandedContentResourcesByItemId,
		setForegroundExpandedContentResourcesByItemId,
	] = useState<ReadonlyMap<string, BridgeCodeViewContentResources>>(
		(): ReadonlyMap<string, BridgeCodeViewContentResources> =>
			new Map<string, BridgeCodeViewContentResources>(),
	);
	const foregroundExpandedContentResourcesByItemIdRef = useRef<
		ReadonlyMap<string, BridgeCodeViewContentResources>
	>(foregroundExpandedContentResourcesByItemId);
	foregroundExpandedContentResourcesByItemIdRef.current =
		foregroundExpandedContentResourcesByItemId;
	const [foregroundExpandedLoadingItemIds, setForegroundExpandedLoadingItemIds] = useState<
		ReadonlySet<string>
	>((): ReadonlySet<string> => new Set<string>());
	const foregroundExpandedContentKeyByItemIdRef = useRef<Map<string, string>>(
		new Map<string, string>(),
	);
	const foregroundExpandedAbortControllersByContentKeyRef = useRef<Map<string, AbortController>>(
		new Map<string, AbortController>(),
	);
	const visibleContentHydrationPaused = shouldPauseVisibleReviewContentHydration({
		isActive,
		codeViewScrollActive: isCodeViewScrollActive,
		currentSelectedContentKey,
		foregroundSelectedContentKey,
		selectedContentResourcesState,
	});
	const loadVisibleContentResourcesThroughDemand = useCallback(
		async (loadProps: VisibleReviewContentLoadProps): Promise<VisibleReviewContentLoadResult> =>
			loadReviewItemContentResourcesThroughDemandResult({
				reviewPackage: loadProps.reviewPackage,
				itemId: loadProps.itemId,
				interest: loadProps.interest,
				resolveDescriptorRef: (handle): BridgeDescriptorRef | null =>
					reviewContentDescriptorRefsByHandleIdRef.current.get(handle.handleId) ?? null,
				executor: resourceExecutor,
				contentRegistry,
				traceContext: loadProps.traceContext ?? null,
				...(loadProps.signal === undefined ? {} : { signal: loadProps.signal }),
				...(loadProps.telemetryRecorder === undefined
					? {}
					: { telemetryRecorder: loadProps.telemetryRecorder }),
				onDemandTelemetry: setLastVisibleDemandTelemetry,
			}),
		[
			contentRegistry,
			resourceExecutor,
			reviewContentDescriptorRefsByHandleIdRef,
			setLastVisibleDemandTelemetry,
		],
	);
	const visibleContentHydration = useVisibleReviewContentHydration({
		contentRegistry,
		loadContentResources: loadVisibleContentResourcesThroughDemand,
		reviewPackage: isActive ? reviewPackage : null,
		resolveDescriptorRef: (handle): BridgeDescriptorRef | null =>
			reviewContentDescriptorRefsByHandleIdRef.current.get(handle.handleId) ?? null,
		selectedItemId: isActive ? selectedItemId : null,
		telemetryParentTraceContext:
			currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
		telemetryRecorder: telemetryRecorderRef.current,
		contentInvalidationVersion: reviewContentInvalidationVersion,
		visibleHydrationPaused: visibleContentHydrationPaused,
	});
	const packageIdentityKey =
		reviewPackage === null
			? null
			: [
					reviewPackage.packageId,
					String(reviewPackage.reviewGeneration),
					String(reviewPackage.revision),
					String(reviewContentInvalidationVersion),
				].join(':');
	useEffect((): (() => void) => {
		const abortControllers = foregroundExpandedAbortControllersByContentKeyRef.current;
		abortForegroundExpandedContentLoads(abortControllers);
		foregroundExpandedContentKeyByItemIdRef.current.clear();
		setForegroundExpandedContentResourcesByItemId(
			new Map<string, BridgeCodeViewContentResources>(),
		);
		setForegroundExpandedLoadingItemIds(new Set<string>());
		return (): void => {
			abortForegroundExpandedContentLoads(abortControllers);
		};
	}, [packageIdentityKey]);
	const requestForegroundItemContent = useCallback(
		(itemId: string): boolean => {
			if (!isActive || reviewPackage === null) {
				return false;
			}
			const item = reviewPackage.itemsById[itemId];
			if (item === undefined) {
				return false;
			}
			const contentKey = [
				makeReviewItemContentResourcesKey({
					item,
					reviewPackage,
				}),
				'expandedForeground',
				String(reviewContentInvalidationVersion),
			].join(':');
			const existingContentKey = foregroundExpandedContentKeyByItemIdRef.current.get(itemId);
			if (
				existingContentKey === contentKey &&
				(foregroundExpandedAbortControllersByContentKeyRef.current.has(contentKey) ||
					foregroundExpandedContentResourcesByItemIdRef.current.has(itemId))
			) {
				return true;
			}
			if (existingContentKey !== undefined) {
				foregroundExpandedAbortControllersByContentKeyRef.current.get(existingContentKey)?.abort();
				foregroundExpandedAbortControllersByContentKeyRef.current.delete(existingContentKey);
			}
			const abortController = new AbortController();
			foregroundExpandedContentKeyByItemIdRef.current.set(itemId, contentKey);
			foregroundExpandedAbortControllersByContentKeyRef.current.set(contentKey, abortController);
			setForegroundExpandedLoadingItemIds(
				(currentItemIds: ReadonlySet<string>): ReadonlySet<string> => {
					const nextItemIds = new Set(currentItemIds);
					nextItemIds.add(itemId);
					return nextItemIds;
				},
			);
			void loadReviewItemContentResourcesThroughDemandResult({
				reviewPackage,
				itemId,
				interest: 'selected',
				resolveDescriptorRef: (handle): BridgeDescriptorRef | null =>
					reviewContentDescriptorRefsByHandleIdRef.current.get(handle.handleId) ?? null,
				executor: resourceExecutor,
				contentRegistry,
				signal: abortController.signal,
				traceContext: currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
				telemetryRecorder: telemetryRecorderRef.current,
				onDemandTelemetry: setLastVisibleDemandTelemetry,
			})
				.then((loadResult): void => {
					foregroundExpandedAbortControllersByContentKeyRef.current.delete(contentKey);
					setForegroundExpandedLoadingItemIds(
						(currentItemIds: ReadonlySet<string>): ReadonlySet<string> => {
							const nextItemIds = new Set(currentItemIds);
							nextItemIds.delete(itemId);
							return nextItemIds;
						},
					);
					if (abortController.signal.aborted) {
						return;
					}
					if (loadResult.status !== 'ready') {
						foregroundExpandedContentKeyByItemIdRef.current.delete(itemId);
						return;
					}
					foregroundExpandedContentKeyByItemIdRef.current.set(itemId, contentKey);
					setForegroundExpandedContentResourcesByItemId(
						(
							currentResourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>,
						): ReadonlyMap<string, BridgeCodeViewContentResources> => {
							const nextResourcesByItemId = new Map(currentResourcesByItemId);
							nextResourcesByItemId.set(itemId, loadResult.resources);
							return nextResourcesByItemId;
						},
					);
				})
				.catch((): void => {
					foregroundExpandedAbortControllersByContentKeyRef.current.delete(contentKey);
					foregroundExpandedContentKeyByItemIdRef.current.delete(itemId);
					setForegroundExpandedLoadingItemIds(
						(currentItemIds: ReadonlySet<string>): ReadonlySet<string> => {
							const nextItemIds = new Set(currentItemIds);
							nextItemIds.delete(itemId);
							return nextItemIds;
						},
					);
				});
			return true;
		},
		[
			contentRegistry,
			currentReviewPackageTelemetryContextRef,
			isActive,
			resourceExecutor,
			reviewContentDescriptorRefsByHandleIdRef,
			reviewContentInvalidationVersion,
			reviewPackage,
			setLastVisibleDemandTelemetry,
			telemetryRecorderRef,
		],
	);
	const visibleContentResourcesByItemId = useMemo(
		(): ReadonlyMap<string, BridgeCodeViewContentResources> =>
			mergeContentResourcesByItemId({
				foregroundResourcesByItemId: foregroundExpandedContentResourcesByItemId,
				visibleResourcesByItemId: visibleContentHydration.visibleContentResourcesByItemId,
			}),
		[
			foregroundExpandedContentResourcesByItemId,
			visibleContentHydration.visibleContentResourcesByItemId,
		],
	);
	const visibleLoadingItemIds = useMemo(
		(): ReadonlySet<string> =>
			unionItemIds({
				primaryItemIds: visibleContentHydration.visibleLoadingItemIds,
				secondaryItemIds: foregroundExpandedLoadingItemIds,
			}),
		[foregroundExpandedLoadingItemIds, visibleContentHydration.visibleLoadingItemIds],
	);

	return {
		requestForegroundItemContent,
		setVisibleContentItemIds: visibleContentHydration.setVisibleItemIds,
		visibleContentResourcesByItemId,
		visibleItemIds: visibleContentHydration.visibleItemIds,
		visibleLoadingItemCount: visibleLoadingItemIds.size,
		visibleLoadingItemIds,
		visibleReadyItemCount: visibleContentResourcesByItemId.size,
	};
}

function abortForegroundExpandedContentLoads(
	abortControllersByContentKey: Map<string, AbortController>,
): void {
	for (const abortController of abortControllersByContentKey.values()) {
		abortController.abort();
	}
	abortControllersByContentKey.clear();
}

function mergeContentResourcesByItemId(props: {
	readonly foregroundResourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>;
	readonly visibleResourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>;
}): ReadonlyMap<string, BridgeCodeViewContentResources> {
	if (props.foregroundResourcesByItemId.size === 0) {
		return props.visibleResourcesByItemId;
	}
	const nextResourcesByItemId = new Map(props.visibleResourcesByItemId);
	for (const [itemId, resources] of props.foregroundResourcesByItemId) {
		nextResourcesByItemId.set(itemId, resources);
	}
	return nextResourcesByItemId;
}

function unionItemIds(props: {
	readonly primaryItemIds: ReadonlySet<string>;
	readonly secondaryItemIds: ReadonlySet<string>;
}): ReadonlySet<string> {
	if (props.secondaryItemIds.size === 0) {
		return props.primaryItemIds;
	}
	const nextItemIds = new Set(props.primaryItemIds);
	for (const itemId of props.secondaryItemIds) {
		nextItemIds.add(itemId);
	}
	return nextItemIds;
}
