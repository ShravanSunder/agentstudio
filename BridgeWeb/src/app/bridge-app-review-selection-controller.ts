import type { Dispatch, MutableRefObject, SetStateAction } from 'react';
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';

import type { BridgeRPCClient } from '../bridge/bridge-rpc-client.js';
import type { BridgeResourceExecutor } from '../core/demand/bridge-resource-executor.js';
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type { BridgeTextResourceStreamResult } from '../core/resources/bridge-resource-stream.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type {
	BridgeReviewSelectionSlice,
	BridgeReviewViewportSlice,
	BridgeReviewViewerStoreActions,
} from '../review-viewer/state/review-viewer-store.js';
import {
	cancelReviewItemDemand,
	reviewItemDemandCancellationTargetForSelectionChange,
} from './bridge-app-review-descriptors.js';
import type { SelectedReviewContentDemandController } from './bridge-app-review-selected-content-controller.js';
import {
	makeSelectedContentResourcesKey,
	selectedItemPresentationForReviewFileTarget,
	type BridgeReviewFileNavigationTarget,
} from './bridge-app-review-selection-state.js';
import {
	createChildTraceContext,
	makeTelemetryMarkedItemKey,
	makeTelemetryPackageKey,
	recordReviewStartupTelemetry,
	type BridgeReviewPackageTelemetryContext,
	type PendingReviewSelectionCommitTelemetry,
} from './bridge-app-review-telemetry.js';

declare global {
	interface Window {
		__bridgeReviewSliceInvalidationProbe?: {
			clicks: {
				readonly invalidatedKeyCount: number;
				readonly packageItemCount: number;
				readonly selectedItemCount: number;
				readonly subscriberNotificationCount: number;
				readonly visibleDeltaCount: number;
			}[];
		};
	}
}

export interface UseBridgeReviewSelectionControllerProps {
	readonly cancelForegroundSelectionRelease: () => void;
	readonly currentReviewPackageTelemetryContextRef: MutableRefObject<BridgeReviewPackageTelemetryContext | null>;
	readonly hasProjection: boolean;
	readonly initialReviewFileTarget: BridgeReviewFileNavigationTarget | null;
	readonly isActive: boolean;
	readonly resourceExecutor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
	readonly reviewContentDescriptorRefsByHandleIdRef: MutableRefObject<
		ReadonlyMap<string, BridgeDescriptorRef>
	>;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly reviewPackageRef: MutableRefObject<BridgeReviewPackage | null>;
	readonly selectionSlice: BridgeReviewSelectionSlice;
	readonly selectionSliceRef: MutableRefObject<BridgeReviewSelectionSlice>;
	readonly viewportSlice: BridgeReviewViewportSlice;
	readonly rpcClient: BridgeRPCClient;
	readonly selectedContentAbortControllerRef: MutableRefObject<AbortController | null>;
	readonly selectedContentActiveLoadKeyRef: MutableRefObject<string | null>;
	readonly setForegroundSelectedContentKey: (value: string | null) => void;
	readonly setSelectedContentResourcesState: SelectedReviewContentDemandController['setSelectedContentResourcesState'];
	readonly setSelectedReviewFileTarget: Dispatch<
		SetStateAction<BridgeReviewFileNavigationTarget | null>
	>;
	readonly startSelectedReviewContentDemand: SelectedReviewContentDemandController['startSelectedReviewContentDemand'];
	readonly telemetryRecorderRef: MutableRefObject<BridgeTelemetryRecorder>;
	readonly viewerActions: BridgeReviewViewerStoreActions;
}

export interface BridgeReviewSelectionController {
	readonly beginForegroundReviewSelection: (
		itemId: string,
		presentationTarget?: BridgeReviewFileNavigationTarget | null,
	) => boolean;
	readonly lastSelectionCommitDurationMilliseconds: number | null;
	readonly selectReviewItem: (
		itemId: string,
		presentationTarget?: BridgeReviewFileNavigationTarget | null,
	) => boolean;
}

export function useBridgeReviewSelectionController(
	props: UseBridgeReviewSelectionControllerProps,
): BridgeReviewSelectionController {
	const {
		cancelForegroundSelectionRelease,
		currentReviewPackageTelemetryContextRef,
		hasProjection,
		initialReviewFileTarget,
		isActive,
		resourceExecutor,
		reviewContentDescriptorRefsByHandleIdRef,
		reviewPackage,
		reviewPackageRef,
		selectionSlice,
		selectionSliceRef,
		viewportSlice,
		rpcClient,
		selectedContentAbortControllerRef,
		selectedContentActiveLoadKeyRef,
		setForegroundSelectedContentKey,
		setSelectedContentResourcesState,
		setSelectedReviewFileTarget,
		startSelectedReviewContentDemand,
		telemetryRecorderRef,
		viewerActions,
	} = props;
	const lastTelemetryMarkedItemRef = useRef<string | null>(null);
	const pendingSelectionCommitTelemetryRef = useRef<PendingReviewSelectionCommitTelemetry | null>(
		null,
	);
	const [lastSelectionCommitDurationMilliseconds, setLastSelectionCommitDurationMilliseconds] =
		useState<number | null>(null);

	const beginForegroundReviewSelection = useCallback(
		(
			itemId: string,
			presentationTarget: BridgeReviewFileNavigationTarget | null = null,
		): boolean => {
			const currentReviewPackage = reviewPackageRef.current;
			if (currentReviewPackage === null || !(itemId in currentReviewPackage.itemsById)) {
				return false;
			}
			const previousSelectedItemId = selectionSliceRef.current.selectedItemId;
			const isSelectionChange = previousSelectedItemId !== itemId;
			const selectedContentKey = makeSelectedContentResourcesKey(currentReviewPackage, itemId);
			const selectedPresentation = selectedItemPresentationForReviewFileTarget({
				reviewPackage: currentReviewPackage,
				selectedItemId: itemId,
				target: presentationTarget ?? initialReviewFileTarget,
			});
			if (isSelectionChange) {
				pendingSelectionCommitTelemetryRef.current = telemetryRecorderRef.current.isEnabled('web')
					? {
							itemId,
							packageKey: makeTelemetryPackageKey(currentReviewPackage),
							startedAtMilliseconds: performance.now(),
							traceContext: createChildTraceContext(
								currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
							),
						}
					: null;
				cancelForegroundSelectionRelease();
				setForegroundSelectedContentKey(selectedContentKey);
				selectedContentAbortControllerRef.current?.abort();
				selectedContentAbortControllerRef.current = null;
				selectedContentActiveLoadKeyRef.current = null;
				cancelReviewItemDemand({
					descriptorRefsByHandleId: reviewContentDescriptorRefsByHandleIdRef.current,
					item: reviewItemDemandCancellationTargetForSelectionChange({
						previousSelectedItemId,
						reviewPackage: currentReviewPackage,
					}),
					resourceExecutor,
				});
				setSelectedContentResourcesState({
					itemId,
					contentKey: selectedContentKey,
					status: 'loading',
					resources: null,
				});
				startSelectedReviewContentDemand({
					itemId,
					presentation: selectedPresentation,
					reviewPackage: currentReviewPackage,
					selectedContentKey,
				});
			}
			if (presentationTarget !== null || isSelectionChange) {
				setSelectedReviewFileTarget(presentationTarget);
			}
			viewerActions.setSelectedItemId(itemId);
			viewerActions.setRenderMode({ kind: 'codeView' });
			recordBridgeReviewSliceInvalidationProbe({
				itemId,
				packageItemCount: currentReviewPackage.orderedItemIds.length,
				visibleItemIds: viewportSlice.visibleItemIds,
			});
			return true;
		},
		[
			cancelForegroundSelectionRelease,
			currentReviewPackageTelemetryContextRef,
			initialReviewFileTarget,
			resourceExecutor,
			reviewContentDescriptorRefsByHandleIdRef,
			reviewPackageRef,
			selectionSliceRef,
			selectedContentAbortControllerRef,
			selectedContentActiveLoadKeyRef,
			setForegroundSelectedContentKey,
			setSelectedContentResourcesState,
			setSelectedReviewFileTarget,
			startSelectedReviewContentDemand,
			telemetryRecorderRef,
			viewportSlice.visibleItemIds,
			viewerActions,
		],
	);
	const selectReviewItem = useCallback(
		(
			itemId: string,
			presentationTarget: BridgeReviewFileNavigationTarget | null = null,
		): boolean => {
			const currentReviewPackage = reviewPackageRef.current;
			if (
				!beginForegroundReviewSelection(itemId, presentationTarget) ||
				currentReviewPackage === null
			) {
				return false;
			}
			lastTelemetryMarkedItemRef.current = makeTelemetryMarkedItemKey(currentReviewPackage, itemId);
			scheduleReviewMarkFileViewedCommand({ itemId, rpcClient });
			return true;
		},
		[beginForegroundReviewSelection, reviewPackageRef, rpcClient],
	);

	useLayoutEffect((): void => {
		const pendingTelemetry = pendingSelectionCommitTelemetryRef.current;
		if (
			pendingTelemetry === null ||
			!isActive ||
			reviewPackage === null ||
			!hasProjection ||
			selectionSlice.selectedItemId !== pendingTelemetry.itemId
		) {
			return;
		}
		if (makeTelemetryPackageKey(reviewPackage) !== pendingTelemetry.packageKey) {
			pendingSelectionCommitTelemetryRef.current = null;
			return;
		}
		pendingSelectionCommitTelemetryRef.current = null;
		const durationMilliseconds = performance.now() - pendingTelemetry.startedAtMilliseconds;
		setLastSelectionCommitDurationMilliseconds(Math.max(0, durationMilliseconds));
		recordReviewStartupTelemetry({
			telemetryRecorder: telemetryRecorderRef.current,
			phase: 'selection_commit',
			slice: 'review_projection',
			transport: 'worker',
			traceContext: pendingTelemetry.traceContext,
			durationMilliseconds,
			result: 'success',
		});
	}, [hasProjection, isActive, reviewPackage, selectionSlice.selectedItemId, telemetryRecorderRef]);

	useEffect((): void => {
		if (
			!isActive ||
			reviewPackage === null ||
			selectionSlice.selectedItemId === null ||
			!telemetryRecorderRef.current.isEnabled('web')
		) {
			return;
		}
		const markedItemKey = makeTelemetryMarkedItemKey(reviewPackage, selectionSlice.selectedItemId);
		if (lastTelemetryMarkedItemRef.current === markedItemKey) {
			return;
		}
		lastTelemetryMarkedItemRef.current = markedItemKey;
		rpcClient.sendCommand({
			method: 'review.markFileViewed',
			params: { fileId: selectionSlice.selectedItemId },
		});
	}, [isActive, reviewPackage, selectionSlice.selectedItemId, rpcClient, telemetryRecorderRef]);

	return {
		beginForegroundReviewSelection,
		lastSelectionCommitDurationMilliseconds,
		selectReviewItem,
	};
}

export function createBridgeReviewSelectionControllerInteractionContract(): {
	readonly subscribedSlices: readonly string[];
} {
	return {
		subscribedSlices: [
			'selectionSlice',
			'rowPaintSlice',
			'contentAvailabilitySlice',
			'panelChromeSlice',
		],
	};
}

function recordBridgeReviewSliceInvalidationProbe(props: {
	readonly itemId: string;
	readonly packageItemCount: number;
	readonly visibleItemIds: readonly string[];
}): void {
	const probeWindow = (globalThis as typeof globalThis & { readonly window?: Window }).window;
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	const probe = probeWindow?.__bridgeReviewSliceInvalidationProbe;
	if (probe === undefined) {
		return;
	}
	const invalidatedKeys = new Set(props.visibleItemIds);
	invalidatedKeys.add(props.itemId);
	probe.clicks.push({
		invalidatedKeyCount: invalidatedKeys.size,
		packageItemCount: props.packageItemCount,
		selectedItemCount: 1,
		subscriberNotificationCount: invalidatedKeys.size,
		visibleDeltaCount: props.visibleItemIds.length,
	});
}

export function scheduleReviewMarkFileViewedCommand(props: {
	readonly itemId: string;
	readonly rpcClient: BridgeRPCClient;
}): void {
	queueMicrotask((): void => {
		props.rpcClient.sendCommand({
			method: 'review.markFileViewed',
			params: { fileId: props.itemId },
		});
	});
}
