import type { Dispatch, MutableRefObject, SetStateAction } from 'react';
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';

import type { BridgeRPCClient } from '../bridge/bridge-rpc-client.js';
import type { BridgeResourceExecutor } from '../core/demand/bridge-resource-executor.js';
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type { BridgeTextResourceStreamResult } from '../core/resources/bridge-resource-stream.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeReviewProjectionResult } from '../review-viewer/models/review-projection-models.js';
import type {
	BridgeReviewViewerRootSnapshot,
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

export interface UseBridgeReviewSelectionControllerProps {
	readonly cancelForegroundSelectionRelease: () => void;
	readonly currentReviewPackageTelemetryContextRef: MutableRefObject<BridgeReviewPackageTelemetryContext | null>;
	readonly initialReviewFileTarget: BridgeReviewFileNavigationTarget | null;
	readonly isActive: boolean;
	readonly projection: BridgeReviewProjectionResult | null;
	readonly resourceExecutor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
	readonly reviewContentDescriptorRefsByHandleIdRef: MutableRefObject<
		ReadonlyMap<string, BridgeDescriptorRef>
	>;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly reviewPackageRef: MutableRefObject<BridgeReviewPackage | null>;
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly rootSnapshotRef: MutableRefObject<BridgeReviewViewerRootSnapshot>;
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
		initialReviewFileTarget,
		isActive,
		projection,
		resourceExecutor,
		reviewContentDescriptorRefsByHandleIdRef,
		reviewPackage,
		reviewPackageRef,
		rootSnapshot,
		rootSnapshotRef,
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
			const previousSelectedItemId = rootSnapshotRef.current.selectedItemId;
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
			return true;
		},
		[
			cancelForegroundSelectionRelease,
			currentReviewPackageTelemetryContextRef,
			initialReviewFileTarget,
			resourceExecutor,
			reviewContentDescriptorRefsByHandleIdRef,
			reviewPackageRef,
			rootSnapshotRef,
			selectedContentAbortControllerRef,
			selectedContentActiveLoadKeyRef,
			setForegroundSelectedContentKey,
			setSelectedContentResourcesState,
			setSelectedReviewFileTarget,
			startSelectedReviewContentDemand,
			telemetryRecorderRef,
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
			projection === null ||
			rootSnapshot.selectedItemId !== pendingTelemetry.itemId
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
	}, [isActive, projection, reviewPackage, rootSnapshot.selectedItemId, telemetryRecorderRef]);

	useEffect((): void => {
		if (
			!isActive ||
			reviewPackage === null ||
			rootSnapshot.selectedItemId === null ||
			!telemetryRecorderRef.current.isEnabled('web')
		) {
			return;
		}
		const markedItemKey = makeTelemetryMarkedItemKey(reviewPackage, rootSnapshot.selectedItemId);
		if (lastTelemetryMarkedItemRef.current === markedItemKey) {
			return;
		}
		lastTelemetryMarkedItemRef.current = markedItemKey;
		rpcClient.sendCommand({
			method: 'review.markFileViewed',
			params: { fileId: rootSnapshot.selectedItemId },
		});
	}, [isActive, reviewPackage, rootSnapshot.selectedItemId, rpcClient, telemetryRecorderRef]);

	return {
		beginForegroundReviewSelection,
		lastSelectionCommitDurationMilliseconds,
		selectReviewItem,
	};
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
