import type { MutableRefObject } from 'react';
import { useCallback } from 'react';

import type { BridgeDemandScheduler } from '../core/demand/bridge-demand-scheduler.js';
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
import type { LoadReviewItemContentResourcesProps } from '../review-viewer/content/review-content-loader.js';
import type { BridgeReviewContentRegistry } from '../review-viewer/content/review-content-registry.js';
import {
	type VisibleReviewContentLoadResult,
	useVisibleReviewContentHydration,
} from '../review-viewer/content/visible-review-content-hydration.js';
import {
	shouldPauseVisibleReviewContentHydration,
	type SelectedContentResourcesState,
} from './bridge-app-review-selection-state.js';
import type { BridgeReviewPackageTelemetryContext } from './bridge-app-review-telemetry.js';

const emptyVisibleContentResourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources> =
	new Map<string, BridgeCodeViewContentResources>();
const emptyVisibleLoadingItemIds: ReadonlySet<string> = new Set<string>();

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
	readonly reviewDemandScheduler: BridgeDemandScheduler;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
	readonly selectedItemId: string | null;
	readonly setLastVisibleDemandTelemetry: (sample: ReviewContentDemandTelemetry) => void;
	readonly telemetryRecorderRef: MutableRefObject<BridgeTelemetryRecorder>;
}

export interface BridgeReviewVisibleContentController {
	readonly setVisibleContentItemIds: (itemIds: readonly string[]) => void;
	readonly visibleContentResourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>;
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
		reviewDemandScheduler,
		reviewPackage,
		selectedContentResourcesState,
		selectedItemId,
		setLastVisibleDemandTelemetry,
		telemetryRecorderRef,
	} = props;
	const visibleContentHydrationPaused = shouldPauseVisibleReviewContentHydration({
		isActive,
		codeViewScrollActive: isCodeViewScrollActive,
		currentSelectedContentKey,
		foregroundSelectedContentKey,
		selectedContentResourcesState,
	});
	const loadVisibleContentResourcesThroughDemand = useCallback(
		async (
			loadProps: LoadReviewItemContentResourcesProps,
		): Promise<VisibleReviewContentLoadResult> =>
			loadReviewItemContentResourcesThroughDemandResult({
				reviewPackage: loadProps.reviewPackage,
				itemId: loadProps.itemId,
				interest: 'visible',
				resolveDescriptorRef: (handle): BridgeDescriptorRef | null =>
					reviewContentDescriptorRefsByHandleIdRef.current.get(handle.handleId) ?? null,
				scheduler: reviewDemandScheduler,
				executor: resourceExecutor,
				traceContext: loadProps.traceContext ?? null,
				...(loadProps.signal === undefined ? {} : { signal: loadProps.signal }),
				...(loadProps.telemetryRecorder === undefined
					? {}
					: { telemetryRecorder: loadProps.telemetryRecorder }),
				onDemandTelemetry: setLastVisibleDemandTelemetry,
			}),
		[
			resourceExecutor,
			reviewContentDescriptorRefsByHandleIdRef,
			reviewDemandScheduler,
			setLastVisibleDemandTelemetry,
		],
	);
	const visibleContentHydration = useVisibleReviewContentHydration({
		contentRegistry,
		loadContentResources: loadVisibleContentResourcesThroughDemand,
		reviewPackage: isActive ? reviewPackage : null,
		selectedItemId: isActive ? selectedItemId : null,
		telemetryParentTraceContext:
			currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
		telemetryRecorder: telemetryRecorderRef.current,
		contentInvalidationVersion: reviewContentInvalidationVersion,
		visibleHydrationPaused: visibleContentHydrationPaused,
	});

	return {
		setVisibleContentItemIds: visibleContentHydration.setVisibleItemIds,
		visibleContentResourcesByItemId: visibleContentHydrationPaused
			? emptyVisibleContentResourcesByItemId
			: visibleContentHydration.visibleContentResourcesByItemId,
		visibleLoadingItemCount: visibleContentHydrationPaused
			? 0
			: visibleContentHydration.visibleLoadingItemCount,
		visibleLoadingItemIds: visibleContentHydrationPaused
			? emptyVisibleLoadingItemIds
			: visibleContentHydration.visibleLoadingItemIds,
		visibleReadyItemCount: visibleContentHydrationPaused
			? 0
			: visibleContentHydration.visibleReadyItemCount,
	};
}
