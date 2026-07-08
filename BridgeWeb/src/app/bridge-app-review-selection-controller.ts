import type { Dispatch, MutableRefObject, SetStateAction } from 'react';
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';

import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type {
	BridgeReviewSelectionSlice,
	BridgeReviewViewportSlice,
} from '../review-viewer/state/review-viewer-store.js';
import type {
	BridgeReviewFileNavigationTarget,
	SelectedContentPaintTelemetryStart,
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
	readonly currentReviewPackageTelemetryContextRef: MutableRefObject<BridgeReviewPackageTelemetryContext | null>;
	readonly hasProjection: boolean;
	readonly isActive: boolean;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly reviewPackageRef: MutableRefObject<BridgeReviewPackage | null>;
	readonly selectionSlice: BridgeReviewSelectionSlice;
	readonly selectionSliceRef: MutableRefObject<BridgeReviewSelectionSlice>;
	readonly viewportSliceRef: MutableRefObject<BridgeReviewViewportSlice>;
	readonly markFileViewed: (itemId: string, onDeliveryFailure?: () => void) => boolean;
	readonly setReviewRenderModeCodeView: () => void;
	readonly setSelectedReviewFileTarget: Dispatch<
		SetStateAction<BridgeReviewFileNavigationTarget | null>
	>;
	readonly setSelectedReviewItemId: (itemId: string | null) => void;
	readonly telemetryRecorderRef: MutableRefObject<BridgeTelemetryRecorder>;
}

export interface BridgeReviewSelectionController {
	readonly beginForegroundReviewSelection: (
		itemId: string,
		presentationTarget?: BridgeReviewFileNavigationTarget | null,
	) => boolean;
	readonly lastSelectionCommitDurationMilliseconds: number | null;
	readonly selectedContentPaintTelemetryStart: SelectedContentPaintTelemetryStart | null;
	readonly selectReviewItem: (
		itemId: string,
		presentationTarget?: BridgeReviewFileNavigationTarget | null,
	) => boolean;
}

export function useBridgeReviewSelectionController(
	props: UseBridgeReviewSelectionControllerProps,
): BridgeReviewSelectionController {
	const {
		currentReviewPackageTelemetryContextRef,
		hasProjection,
		isActive,
		reviewPackage,
		reviewPackageRef,
		selectionSlice,
		selectionSliceRef,
		viewportSliceRef,
		markFileViewed,
		setReviewRenderModeCodeView,
		setSelectedReviewFileTarget,
		setSelectedReviewItemId,
		telemetryRecorderRef,
	} = props;
	const lastTelemetryMarkedItemRef = useRef<string | null>(null);
	const pendingSelectionCommitTelemetryRef = useRef<PendingReviewSelectionCommitTelemetry | null>(
		null,
	);
	const [lastSelectionCommitDurationMilliseconds, setLastSelectionCommitDurationMilliseconds] =
		useState<number | null>(null);
	const [selectedContentPaintTelemetryStart, setSelectedContentPaintTelemetryStart] =
		useState<SelectedContentPaintTelemetryStart | null>(null);

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
			if (isSelectionChange) {
				const packageKey = makeTelemetryPackageKey(currentReviewPackage);
				const startedAtMilliseconds = performance.now();
				const actionTraceContext = createChildTraceContext(
					currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
				);
				const paintTelemetryStart = telemetryRecorderRef.current.isEnabled('web')
					? {
							itemId,
							packageKey,
							startedAtMilliseconds,
							actionTraceContext,
						}
					: null;
				setSelectedContentPaintTelemetryStart(paintTelemetryStart);
				pendingSelectionCommitTelemetryRef.current =
					paintTelemetryStart === null
						? null
						: {
								itemId,
								packageKey,
								startedAtMilliseconds,
								traceContext: actionTraceContext,
							};
			}
			if (presentationTarget !== null || isSelectionChange) {
				setSelectedReviewFileTarget(presentationTarget);
			}
			setSelectedReviewItemId(itemId);
			setReviewRenderModeCodeView();
			recordBridgeReviewSliceInvalidationProbe({
				itemId,
				packageItemCount: currentReviewPackage.orderedItemIds.length,
				visibleItemIds: viewportSliceRef.current.visibleItemIds,
			});
			return true;
		},
		[
			currentReviewPackageTelemetryContextRef,
			reviewPackageRef,
			selectionSliceRef,
			setReviewRenderModeCodeView,
			setSelectedReviewFileTarget,
			setSelectedReviewItemId,
			telemetryRecorderRef,
			viewportSliceRef,
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
			scheduleReviewMarkFileViewedCommand({
				itemId,
				markFileViewed,
				onDeliveryFailure: (): void => {
					if (
						lastTelemetryMarkedItemRef.current ===
						makeTelemetryMarkedItemKey(currentReviewPackage, itemId)
					) {
						lastTelemetryMarkedItemRef.current = null;
					}
				},
			});
			return true;
		},
		[beginForegroundReviewSelection, markFileViewed, reviewPackageRef],
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
			setSelectedContentPaintTelemetryStart((currentStart) =>
				currentStart?.packageKey === pendingTelemetry.packageKey ? null : currentStart,
			);
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
		if (
			!markFileViewed(selectionSlice.selectedItemId, (): void => {
				if (lastTelemetryMarkedItemRef.current === markedItemKey) {
					lastTelemetryMarkedItemRef.current = null;
				}
			})
		) {
			lastTelemetryMarkedItemRef.current = null;
		}
	}, [
		isActive,
		markFileViewed,
		reviewPackage,
		selectionSlice.selectedItemId,
		telemetryRecorderRef,
	]);

	return {
		beginForegroundReviewSelection,
		lastSelectionCommitDurationMilliseconds,
		selectedContentPaintTelemetryStart,
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
	readonly markFileViewed: (itemId: string, onDeliveryFailure?: () => void) => boolean | void;
	readonly onDeliveryFailure?: () => void;
}): void {
	queueMicrotask((): void => {
		if (props.markFileViewed(props.itemId, props.onDeliveryFailure) === false) {
			props.onDeliveryFailure?.();
		}
	});
}
