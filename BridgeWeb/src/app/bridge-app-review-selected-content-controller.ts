import type { Dispatch, MutableRefObject, SetStateAction } from 'react';
import { useCallback, useLayoutEffect, useRef, useState } from 'react';

import type { BridgeDemandScheduler } from '../core/demand/bridge-demand-scheduler.js';
import type { BridgeResourceExecutor } from '../core/demand/bridge-resource-executor.js';
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type { BridgeTextResourceStreamResult } from '../core/resources/bridge-resource-stream.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import {
	loadReviewItemContentResourcesThroughDemandResult,
	type ReviewContentDemandTelemetry,
} from '../review-viewer/content/review-content-demand-loader.js';
import { recordBridgeViewerContentQueueTelemetry } from '../review-viewer/telemetry/bridge-review-viewer-telemetry.js';
import { foregroundSelectionVisibleHydrationReleaseDelayMilliseconds } from './bridge-app-review-runtime.js';
import {
	contentResourceCount,
	makeSelectedContentResourcesKey,
	scheduleSelectedContentRetry,
	selectedContentResourcesStateFromDemandLoadResult,
	shouldStartSelectedReviewContentDemand,
	type BridgeReviewFileNavigationTarget,
	type SelectedContentResourcesState,
} from './bridge-app-review-selection-state.js';
import {
	createChildTraceContext,
	recordReviewStartupTelemetry,
	type BridgeReviewPackageTelemetryContext,
} from './bridge-app-review-telemetry.js';

export interface UseSelectedReviewContentDemandControllerProps {
	readonly currentReviewPackageTelemetryContextRef: MutableRefObject<BridgeReviewPackageTelemetryContext | null>;
	readonly reviewContentDescriptorRefsByHandleIdRef: MutableRefObject<
		ReadonlyMap<string, BridgeDescriptorRef>
	>;
	readonly resourceExecutor: BridgeResourceExecutor<BridgeTextResourceStreamResult>;
	readonly reviewDemandScheduler: BridgeDemandScheduler;
	readonly telemetryRecorderRef: MutableRefObject<BridgeTelemetryRecorder>;
}

export interface StartSelectedReviewContentDemandProps {
	readonly itemId: string;
	readonly presentation: SelectedReviewContentPresentation;
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedContentKey: string;
}

export type SelectedReviewContentPresentation = {
	readonly kind: 'file';
	readonly version: BridgeReviewFileNavigationTarget['version'];
} | null;

export interface SelectedReviewContentDemandController {
	readonly cancelForegroundSelectionRelease: () => void;
	readonly clearForegroundSelectionNow: (contentKey: string) => void;
	readonly foregroundSelectedContentKey: string | null;
	readonly lastSelectedDemandTelemetry: ReviewContentDemandTelemetry | null;
	readonly lastSelectedDemandTelemetryRef: MutableRefObject<ReviewContentDemandTelemetry | null>;
	readonly scheduleForegroundSelectionRelease: (contentKey: string) => void;
	readonly selectedContentAbortControllerRef: MutableRefObject<AbortController | null>;
	readonly selectedContentActiveLoadKeyRef: MutableRefObject<string | null>;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
	readonly selectedContentResourcesStateRef: MutableRefObject<SelectedContentResourcesState | null>;
	readonly selectedContentRetryScheduledRef: MutableRefObject<boolean>;
	readonly selectedContentRetryVersion: number;
	readonly setForegroundSelectedContentKey: (value: string | null) => void;
	readonly setLastSelectedDemandTelemetry: Dispatch<
		SetStateAction<ReviewContentDemandTelemetry | null>
	>;
	readonly setSelectedContentRetryVersion: Dispatch<SetStateAction<number>>;
	readonly setSelectedContentResourcesState: (
		value:
			| SelectedContentResourcesState
			| null
			| ((current: SelectedContentResourcesState | null) => SelectedContentResourcesState | null),
	) => void;
	readonly startSelectedReviewContentDemand: (
		props: StartSelectedReviewContentDemandProps,
	) => () => void;
}

export interface UseBridgeReviewSelectedContentEffectProps {
	readonly cancelForegroundSelectionRelease: () => void;
	readonly currentSelectedContentKey: string | null;
	readonly isActive: boolean;
	readonly reviewPackageRef: MutableRefObject<BridgeReviewPackage | null>;
	readonly rootSnapshotRef: MutableRefObject<{ readonly selectedItemId: string | null }>;
	readonly selectedContentAbortControllerRef: MutableRefObject<AbortController | null>;
	readonly selectedContentActiveLoadKeyRef: MutableRefObject<string | null>;
	readonly selectedContentRetryVersion: number;
	readonly selectedItemPresentation: SelectedReviewContentPresentation;
	readonly setForegroundSelectedContentKey: (value: string | null) => void;
	readonly setLastSelectedDemandTelemetry: Dispatch<
		SetStateAction<ReviewContentDemandTelemetry | null>
	>;
	readonly setSelectedContentResourcesState: SelectedReviewContentDemandController['setSelectedContentResourcesState'];
	readonly startSelectedReviewContentDemand: SelectedReviewContentDemandController['startSelectedReviewContentDemand'];
}

export function useSelectedReviewContentDemandController(
	props: UseSelectedReviewContentDemandControllerProps,
): SelectedReviewContentDemandController {
	const {
		currentReviewPackageTelemetryContextRef,
		reviewContentDescriptorRefsByHandleIdRef,
		resourceExecutor,
		reviewDemandScheduler,
		telemetryRecorderRef,
	} = props;
	const [selectedContentResourcesState, setSelectedContentResourcesState] =
		useState<SelectedContentResourcesState | null>(null);
	const selectedContentResourcesStateRef = useRef<SelectedContentResourcesState | null>(null);
	selectedContentResourcesStateRef.current = selectedContentResourcesState;
	const [foregroundSelectedContentKey, setForegroundSelectedContentKey] = useState<string | null>(
		null,
	);
	const foregroundSelectionReleaseCancelRef = useRef<(() => void) | null>(null);
	const cancelForegroundSelectionRelease = useCallback((): void => {
		foregroundSelectionReleaseCancelRef.current?.();
		foregroundSelectionReleaseCancelRef.current = null;
	}, []);
	const clearForegroundSelectionNow = useCallback(
		(contentKey: string): void => {
			cancelForegroundSelectionRelease();
			setForegroundSelectedContentKey((currentContentKey: string | null): string | null =>
				currentContentKey === contentKey ? null : currentContentKey,
			);
		},
		[cancelForegroundSelectionRelease],
	);
	const scheduleForegroundSelectionRelease = useCallback(
		(contentKey: string): void => {
			cancelForegroundSelectionRelease();
			const timeoutId = setTimeout((): void => {
				foregroundSelectionReleaseCancelRef.current = null;
				setForegroundSelectedContentKey((currentContentKey: string | null): string | null =>
					currentContentKey === contentKey ? null : currentContentKey,
				);
			}, foregroundSelectionVisibleHydrationReleaseDelayMilliseconds);
			foregroundSelectionReleaseCancelRef.current = (): void => {
				clearTimeout(timeoutId);
			};
		},
		[cancelForegroundSelectionRelease],
	);
	const [selectedContentRetryVersion, setSelectedContentRetryVersion] = useState(0);
	const selectedContentRetryScheduledRef = useRef(false);
	const [lastSelectedDemandTelemetry, setLastSelectedDemandTelemetry] =
		useState<ReviewContentDemandTelemetry | null>(null);
	const lastSelectedDemandTelemetryRef = useRef<ReviewContentDemandTelemetry | null>(null);
	lastSelectedDemandTelemetryRef.current = lastSelectedDemandTelemetry;
	const selectedContentActiveLoadKeyRef = useRef<string | null>(null);
	const selectedContentLoadStartByKeyRef = useRef<Map<string, number>>(new Map());
	const selectedContentAbortControllerRef = useRef<AbortController | null>(null);

	const startSelectedReviewContentDemand = useCallback(
		(loadProps: StartSelectedReviewContentDemandProps): (() => void) => {
			const selectedItem = loadProps.reviewPackage.itemsById[loadProps.itemId];
			if (selectedItem === undefined) {
				setSelectedContentResourcesState(null);
				cancelForegroundSelectionRelease();
				setForegroundSelectedContentKey(null);
				setLastSelectedDemandTelemetry(null);
				return (): void => {};
			}
			const selectedContentLoadKey = loadProps.selectedContentKey;
			const currentSelectedContentResourcesState = selectedContentResourcesStateRef.current;
			if (
				!shouldStartSelectedReviewContentDemand({
					activeSelectedContentLoadKey: selectedContentActiveLoadKeyRef.current,
					currentSelectedContentResourcesState,
					selectedContentKey: loadProps.selectedContentKey,
					selectedContentLoadKey,
				})
			) {
				scheduleForegroundSelectionRelease(loadProps.selectedContentKey);
				return (): void => {};
			}
			let didCancel = false;
			const contentAbortController = new AbortController();
			selectedContentAbortControllerRef.current?.abort();
			selectedContentAbortControllerRef.current = contentAbortController;
			selectedContentActiveLoadKeyRef.current = selectedContentLoadKey;
			const selectedContentLoadStarts = selectedContentLoadStartByKeyRef.current;
			setSelectedContentResourcesState(
				(current: SelectedContentResourcesState | null): SelectedContentResourcesState | null =>
					current?.contentKey === loadProps.selectedContentKey
						? current
						: {
								itemId: loadProps.itemId,
								contentKey: loadProps.selectedContentKey,
								status: 'loading',
								resources: null,
							},
			);
			const parentTraceContext =
				currentReviewPackageTelemetryContextRef.current?.traceContext ?? null;
			selectedContentLoadStarts.set(loadProps.selectedContentKey, performance.now());
			recordBridgeViewerContentQueueTelemetry({
				telemetryRecorder: telemetryRecorderRef.current,
				parentTraceContext,
				item: selectedItem,
				interest: 'selected',
			});
			void loadReviewItemContentResourcesThroughDemandResult({
				reviewPackage: loadProps.reviewPackage,
				itemId: loadProps.itemId,
				interest: 'selected',
				presentation: loadProps.presentation,
				resolveDescriptorRef: (handle): BridgeDescriptorRef | null =>
					reviewContentDescriptorRefsByHandleIdRef.current.get(handle.handleId) ?? null,
				scheduler: reviewDemandScheduler,
				executor: resourceExecutor,
				signal: contentAbortController.signal,
				traceContext: telemetryRecorderRef.current.isEnabled('web')
					? createChildTraceContext(parentTraceContext)
					: null,
				telemetryRecorder: telemetryRecorderRef.current,
				onDemandTelemetry: setLastSelectedDemandTelemetry,
			})
				.then((loadResult): void => {
					if (!didCancel) {
						const loadStartMilliseconds =
							selectedContentLoadStarts.get(loadProps.selectedContentKey) ?? null;
						selectedContentLoadStarts.delete(loadProps.selectedContentKey);
						if (selectedContentActiveLoadKeyRef.current === selectedContentLoadKey) {
							selectedContentActiveLoadKeyRef.current = null;
						}
						setSelectedContentResourcesState(
							selectedContentResourcesStateFromDemandLoadResult({
								itemId: loadProps.itemId,
								contentKey: loadProps.selectedContentKey,
								loadResult,
							}),
						);
						scheduleForegroundSelectionRelease(loadProps.selectedContentKey);
						if (loadResult.status === 'ready' && loadStartMilliseconds !== null) {
							recordSelectedContentReadyTelemetry({
								telemetryRecorder: telemetryRecorderRef.current,
								parentTraceContext,
								loadStartMilliseconds,
								resourceCount: contentResourceCount(loadResult.resources),
							});
						}
						if (loadResult.status === 'deferred') {
							scheduleSelectedContentRetry({
								scheduledRef: selectedContentRetryScheduledRef,
								setSelectedContentRetryVersion,
							});
						}
					}
				})
				.catch((): void => {
					if (!didCancel) {
						selectedContentLoadStarts.delete(loadProps.selectedContentKey);
						if (selectedContentActiveLoadKeyRef.current === selectedContentLoadKey) {
							selectedContentActiveLoadKeyRef.current = null;
						}
						setSelectedContentResourcesState({
							itemId: loadProps.itemId,
							contentKey: loadProps.selectedContentKey,
							status: 'failed',
							resources: null,
						});
						clearForegroundSelectionNow(loadProps.selectedContentKey);
					}
				});
			return (): void => {
				didCancel = true;
				selectedContentLoadStarts.delete(loadProps.selectedContentKey);
				contentAbortController.abort();
				if (selectedContentActiveLoadKeyRef.current === selectedContentLoadKey) {
					selectedContentActiveLoadKeyRef.current = null;
				}
				if (selectedContentAbortControllerRef.current === contentAbortController) {
					selectedContentAbortControllerRef.current = null;
				}
			};
		},
		[
			cancelForegroundSelectionRelease,
			clearForegroundSelectionNow,
			currentReviewPackageTelemetryContextRef,
			scheduleForegroundSelectionRelease,
			resourceExecutor,
			reviewContentDescriptorRefsByHandleIdRef,
			reviewDemandScheduler,
			setSelectedContentRetryVersion,
			telemetryRecorderRef,
		],
	);

	return {
		cancelForegroundSelectionRelease,
		clearForegroundSelectionNow,
		foregroundSelectedContentKey,
		lastSelectedDemandTelemetry,
		lastSelectedDemandTelemetryRef,
		scheduleForegroundSelectionRelease,
		selectedContentAbortControllerRef,
		selectedContentActiveLoadKeyRef,
		selectedContentResourcesState,
		selectedContentResourcesStateRef,
		selectedContentRetryScheduledRef,
		selectedContentRetryVersion,
		setForegroundSelectedContentKey,
		setLastSelectedDemandTelemetry,
		setSelectedContentRetryVersion,
		setSelectedContentResourcesState,
		startSelectedReviewContentDemand,
	};
}

export function useBridgeReviewSelectedContentEffect(
	props: UseBridgeReviewSelectedContentEffectProps,
): void {
	const {
		cancelForegroundSelectionRelease,
		currentSelectedContentKey,
		isActive,
		reviewPackageRef,
		rootSnapshotRef,
		selectedContentAbortControllerRef,
		selectedContentActiveLoadKeyRef,
		selectedContentRetryVersion,
		selectedItemPresentation,
		setForegroundSelectedContentKey,
		setLastSelectedDemandTelemetry,
		setSelectedContentResourcesState,
		startSelectedReviewContentDemand,
	} = props;

	useLayoutEffect((): (() => void) => {
		if (!isActive) {
			selectedContentAbortControllerRef.current?.abort();
			selectedContentAbortControllerRef.current = null;
			selectedContentActiveLoadKeyRef.current = null;
			cancelForegroundSelectionRelease();
			setForegroundSelectedContentKey(null);
			setLastSelectedDemandTelemetry(null);
			return (): void => {};
		}
		const selectedItemId = rootSnapshotRef.current.selectedItemId;
		const currentReviewPackage = reviewPackageRef.current;
		if (currentReviewPackage === null || selectedItemId === null) {
			setSelectedContentResourcesState(null);
			cancelForegroundSelectionRelease();
			setForegroundSelectedContentKey(null);
			setLastSelectedDemandTelemetry(null);
			return (): void => {};
		}
		const selectedItem = currentReviewPackage.itemsById[selectedItemId];
		if (selectedItem === undefined) {
			setSelectedContentResourcesState(null);
			cancelForegroundSelectionRelease();
			setForegroundSelectedContentKey(null);
			setLastSelectedDemandTelemetry(null);
			return (): void => {};
		}
		const selectedContentKey =
			currentSelectedContentKey ??
			makeSelectedContentResourcesKey(currentReviewPackage, selectedItemId);
		return startSelectedReviewContentDemand({
			itemId: selectedItemId,
			presentation: selectedItemPresentation,
			reviewPackage: currentReviewPackage,
			selectedContentKey,
		});
	}, [
		cancelForegroundSelectionRelease,
		currentSelectedContentKey,
		isActive,
		reviewPackageRef,
		rootSnapshotRef,
		selectedContentAbortControllerRef,
		selectedContentActiveLoadKeyRef,
		selectedContentRetryVersion,
		selectedItemPresentation,
		setForegroundSelectedContentKey,
		setLastSelectedDemandTelemetry,
		setSelectedContentResourcesState,
		startSelectedReviewContentDemand,
	]);
}

function recordSelectedContentReadyTelemetry(props: {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly loadStartMilliseconds: number;
	readonly resourceCount: number;
}): void {
	recordReviewStartupTelemetry({
		telemetryRecorder: props.telemetryRecorder,
		phase: 'selected_content_ready',
		slice: 'content_fetch',
		transport: 'content',
		traceContext: createChildTraceContext(props.parentTraceContext),
		durationMilliseconds: performance.now() - props.loadStartMilliseconds,
		result: 'success',
		numericAttributes: {
			'agentstudio.bridge.content.resource_count': props.resourceCount,
		},
	});
}
