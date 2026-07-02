import { useEffect, useMemo, useRef } from 'react';

import type {
	BridgeFileChangeKind,
	BridgeFileClass,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type {
	BridgeTelemetryFlushProps,
	BridgeTelemetryRecorder,
} from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import type {
	BridgeReviewProjectionMode,
	BridgeReviewProjectionFacet,
	BridgeReviewProjectionWorkloadId,
} from '../models/review-projection-models.js';
import { makeBridgeReviewProjectionRequest } from '../navigation/review-projection-request.js';
import {
	makeBridgeReviewProjectionInput,
	projectionIdForRequest,
} from '../navigation/review-projection.js';
import type { BridgeReviewViewerStore } from '../state/review-viewer-store.js';
import {
	recordBridgeProjectionBuildTelemetry,
	recordBridgeProjectionCoordinatorTelemetry,
} from '../telemetry/bridge-review-viewer-telemetry.js';
import { createBridgeReviewProjectionSyncClient } from '../workers/projection/review-projection-sync-client.js';
import type {
	BridgeReviewProjectionWorkerClient,
	BridgeReviewProjectionWorkerTask,
} from '../workers/projection/review-projection-worker-client.js';
import { selectBridgeReviewProjectionExecutionLane } from '../workers/projection/review-projection-worker-planner.js';

export interface UseBridgeReviewProjectionCoordinatorProps {
	readonly store: BridgeReviewViewerStore;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly facets: readonly BridgeReviewProjectionFacet[];
	readonly gitStatusFilter: BridgeFileChangeKind | 'all';
	readonly fileClassFilter: BridgeFileClass | 'all';
	readonly projectionWorkerClient: BridgeReviewProjectionWorkerClient | null;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly telemetryParentTraceContext: BridgeTraceContext | null;
	readonly flushTelemetry: (props?: BridgeTelemetryFlushProps) => void;
}

export interface StartBridgeReviewProjectionCoordinatorRequestProps {
	readonly store: BridgeReviewViewerStore;
	readonly reviewPackage: BridgeReviewPackage;
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly facets: readonly BridgeReviewProjectionFacet[];
	readonly gitStatusFilter: BridgeFileChangeKind | 'all';
	readonly fileClassFilter: BridgeFileClass | 'all';
	readonly projectionWorkerClient: BridgeReviewProjectionWorkerClient | null;
	readonly syncProjectionClient: BridgeReviewProjectionWorkerClient;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly telemetryParentTraceContext: BridgeTraceContext | null;
	readonly flushTelemetry: (props?: BridgeTelemetryFlushProps) => void;
}

const projectionAbortKey = 'bridge-review-projection';
const projectionWorkloadId: BridgeReviewProjectionWorkloadId = 'interactive';
const projectionStartCoalescingDelayMilliseconds = 32;
const projectionStartMaxCoalescingDelayMilliseconds = 96;

export function useBridgeReviewProjectionCoordinator(
	props: UseBridgeReviewProjectionCoordinatorProps,
): void {
	const {
		fileClassFilter,
		facets,
		flushTelemetry,
		gitStatusFilter,
		projectionMode,
		projectionWorkerClient,
		reviewPackage,
		store,
		telemetryParentTraceContext,
		telemetryRecorder,
	} = props;
	const syncProjectionClient = useMemo(() => createBridgeReviewProjectionSyncClient(), []);
	const activeProjectionCleanupRef = useRef<(() => void) | null>(null);
	const pendingProjectionStartTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
	const pendingProjectionFirstQueuedAtRef = useRef<number | null>(null);
	const latestProjectionStartPropsRef =
		useRef<StartBridgeReviewProjectionCoordinatorRequestProps | null>(null);
	const latestProjectionControlKeyRef = useRef<string | null>(null);

	useEffect(
		(): (() => void) => (): void => {
			cancelPendingProjectionStart({
				pendingProjectionStartTimeoutRef,
				pendingProjectionFirstQueuedAtRef,
				latestProjectionStartPropsRef,
			});
			activeProjectionCleanupRef.current?.();
			activeProjectionCleanupRef.current = null;
		},
		[],
	);

	useEffect((): (() => void) | undefined => {
		if (reviewPackage === null) {
			cancelPendingProjectionStart({
				pendingProjectionStartTimeoutRef,
				pendingProjectionFirstQueuedAtRef,
				latestProjectionStartPropsRef,
			});
			activeProjectionCleanupRef.current?.();
			activeProjectionCleanupRef.current = null;
			latestProjectionControlKeyRef.current = null;
			return undefined;
		}
		const projectionControlKey = makeReviewProjectionControlKey({
			projectionMode,
			facets,
			gitStatusFilter,
			fileClassFilter,
		});
		const shouldStartImmediately =
			latestProjectionControlKeyRef.current !== null &&
			latestProjectionControlKeyRef.current !== projectionControlKey;
		latestProjectionControlKeyRef.current = projectionControlKey;
		latestProjectionStartPropsRef.current = {
			store,
			reviewPackage,
			projectionMode,
			facets,
			gitStatusFilter,
			fileClassFilter,
			projectionWorkerClient,
			syncProjectionClient,
			telemetryRecorder,
			telemetryParentTraceContext,
			flushTelemetry,
		};
		const cancelScheduledStart = scheduleLatestReviewProjectionCoordinatorStart({
			activeProjectionCleanupRef,
			pendingProjectionFirstQueuedAtRef,
			pendingProjectionStartTimeoutRef,
			latestProjectionStartPropsRef,
			startImmediately: shouldStartImmediately,
		});
		return (): void => {
			cancelScheduledStart();
		};
	}, [
		fileClassFilter,
		facets,
		flushTelemetry,
		gitStatusFilter,
		projectionMode,
		projectionWorkerClient,
		reviewPackage,
		store,
		telemetryParentTraceContext,
		telemetryRecorder,
		syncProjectionClient,
	]);
}

interface ReviewProjectionStartRefs {
	readonly activeProjectionCleanupRef: {
		current: (() => void) | null;
	};
	readonly pendingProjectionFirstQueuedAtRef: {
		current: number | null;
	};
	readonly pendingProjectionStartTimeoutRef: {
		current: ReturnType<typeof setTimeout> | null;
	};
	readonly latestProjectionStartPropsRef: {
		current: StartBridgeReviewProjectionCoordinatorRequestProps | null;
	};
	readonly startImmediately: boolean;
}

function scheduleLatestReviewProjectionCoordinatorStart(
	refs: ReviewProjectionStartRefs,
): () => void {
	if (refs.startImmediately) {
		if (refs.pendingProjectionStartTimeoutRef.current !== null) {
			clearTimeout(refs.pendingProjectionStartTimeoutRef.current);
			refs.pendingProjectionStartTimeoutRef.current = null;
		}
		refs.pendingProjectionFirstQueuedAtRef.current = null;
		startLatestReviewProjectionCoordinatorRequest(refs);
		return (): void => {};
	}
	if (refs.pendingProjectionFirstQueuedAtRef.current === null) {
		refs.pendingProjectionFirstQueuedAtRef.current = performance.now();
	}
	if (refs.pendingProjectionStartTimeoutRef.current !== null) {
		clearTimeout(refs.pendingProjectionStartTimeoutRef.current);
		refs.pendingProjectionStartTimeoutRef.current = null;
	}
	const elapsedMilliseconds = performance.now() - refs.pendingProjectionFirstQueuedAtRef.current;
	const delayMilliseconds =
		elapsedMilliseconds >= projectionStartMaxCoalescingDelayMilliseconds
			? 0
			: projectionStartCoalescingDelayMilliseconds;
	const timeoutId = setTimeout((): void => {
		refs.pendingProjectionStartTimeoutRef.current = null;
		refs.pendingProjectionFirstQueuedAtRef.current = null;
		startLatestReviewProjectionCoordinatorRequest(refs);
	}, delayMilliseconds);
	refs.pendingProjectionStartTimeoutRef.current = timeoutId;
	return (): void => {
		if (refs.pendingProjectionStartTimeoutRef.current === timeoutId) {
			clearTimeout(timeoutId);
			refs.pendingProjectionStartTimeoutRef.current = null;
		}
	};
}

function startLatestReviewProjectionCoordinatorRequest(refs: ReviewProjectionStartRefs): void {
	const latestProjectionStartProps = refs.latestProjectionStartPropsRef.current;
	refs.latestProjectionStartPropsRef.current = null;
	if (latestProjectionStartProps === null) {
		return;
	}
	const previousProjectionCleanup = refs.activeProjectionCleanupRef.current;
	const nextProjectionCleanup = startBridgeReviewProjectionCoordinatorRequest(
		latestProjectionStartProps,
	);
	refs.activeProjectionCleanupRef.current = nextProjectionCleanup;
	previousProjectionCleanup?.();
}

function cancelPendingProjectionStart(refs: {
	readonly pendingProjectionStartTimeoutRef: {
		current: ReturnType<typeof setTimeout> | null;
	};
	readonly pendingProjectionFirstQueuedAtRef: {
		current: number | null;
	};
	readonly latestProjectionStartPropsRef: {
		current: StartBridgeReviewProjectionCoordinatorRequestProps | null;
	};
}): void {
	if (refs.pendingProjectionStartTimeoutRef.current !== null) {
		clearTimeout(refs.pendingProjectionStartTimeoutRef.current);
		refs.pendingProjectionStartTimeoutRef.current = null;
	}
	refs.pendingProjectionFirstQueuedAtRef.current = null;
	refs.latestProjectionStartPropsRef.current = null;
}

function makeReviewProjectionControlKey(props: {
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly facets: readonly BridgeReviewProjectionFacet[];
	readonly gitStatusFilter: BridgeFileChangeKind | 'all';
	readonly fileClassFilter: BridgeFileClass | 'all';
}): string {
	return JSON.stringify({
		fileClassFilter: props.fileClassFilter,
		facets: props.facets,
		gitStatusFilter: props.gitStatusFilter,
		projectionMode: props.projectionMode,
	});
}

export function startBridgeReviewProjectionCoordinatorRequest(
	props: StartBridgeReviewProjectionCoordinatorRequestProps,
): () => void {
	const inputBuildStartMilliseconds = performance.now();
	const projectionRequest = makeBridgeReviewProjectionRequest({
		projectionMode: props.projectionMode,
		facets: props.facets,
		gitStatusFilter: props.gitStatusFilter,
		fileClassFilter: props.fileClassFilter,
	});
	const projectionInput = makeBridgeReviewProjectionInput(props.reviewPackage);
	// F5 guided-order freeze: when this is a streaming continuation of the SAME guided
	// projection (identical projectionId — same package, generation, mode, and facets) reuse the
	// already-applied order so incoming metadata cannot re-rank rows the reader is looking at. A
	// new generation, mode, or facet change produces a different projectionId, so the hint drops
	// and the projection re-ranks from scratch.
	const previousProjection = props.store.getState().projection;
	const stableGuidedOrderHint =
		props.projectionMode.kind === 'guidedReview' &&
		previousProjection !== null &&
		previousProjection.projectionId === projectionIdForRequest(projectionInput, projectionRequest)
			? previousProjection.orderedItemIds
			: undefined;
	const decision = selectBridgeReviewProjectionExecutionLane({
		changedItemCount: projectionInput.orderedItems.length,
		projectedTreePathCount: projectedTreePathCount(projectionInput.orderedItems),
		activeRefinementPathCount: activeFacetPathCount(
			projectionInput.orderedItems,
			projectionRequest.facets,
		),
		hasActiveNonVisibilityRefinement: hasActiveNonVisibilityFacet(projectionRequest.facets),
		workloadId: projectionWorkloadId,
	});
	const inputBuildDurationMilliseconds = performance.now() - inputBuildStartMilliseconds;
	const executionLane =
		decision.lane === 'worker' && props.projectionWorkerClient !== null ? 'worker' : 'sync';
	const projectionClient =
		executionLane === 'worker' && props.projectionWorkerClient !== null
			? props.projectionWorkerClient
			: props.syncProjectionClient;
	let isCurrentRequest = true;
	let activeTask: BridgeReviewProjectionWorkerTask | null = null;
	const startProjectionTask = (
		client: BridgeReviewProjectionWorkerClient,
		taskExecutionLane: 'sync' | 'worker',
	): BridgeReviewProjectionWorkerTask => {
		const projectionTotalStartMilliseconds = performance.now();
		const task = client.startProjection({
			abortKey: projectionAbortKey,
			projectionInput,
			projectionRequest,
			visibleItemIds: [],
			workloadId: projectionWorkloadId,
			...(stableGuidedOrderHint === undefined ? {} : { stableGuidedOrderHint }),
		});
		activeTask = task;
		props.store.getState().actions.startProjectionRequest(task.identity);
		props.store.getState().actions.setWorkerStatus({
			lane: taskExecutionLane,
			pendingRequestCount: 1,
			lastCompletedRequestId: props.store.getState().workerStatus.lastCompletedRequestId,
		});
		void task.completed
			.then((completion): void => {
				if (!isCurrentRequest) {
					return;
				}
				if (completion.status !== 'success') {
					props.store.getState().actions.failProjectionRequest(completion.identity);
					return;
				}
				const storeApplyStartMilliseconds = performance.now();
				const didApply = props.store.getState().actions.applyProjectionWorkerResult({
					identity: completion.identity,
					result: completion.response.result,
				});
				const storeApplyDurationMilliseconds = performance.now() - storeApplyStartMilliseconds;
				if (!didApply) {
					return;
				}
				recordBridgeProjectionCoordinatorTelemetry({
					telemetryRecorder: props.telemetryRecorder,
					traceContext: props.telemetryParentTraceContext,
					phase: 'projection_input_build',
					durationMilliseconds: inputBuildDurationMilliseconds,
					executionLane: taskExecutionLane,
					reviewPackage: props.reviewPackage,
					result: 'success',
				});
				recordBridgeProjectionCoordinatorTelemetry({
					telemetryRecorder: props.telemetryRecorder,
					traceContext: props.telemetryParentTraceContext,
					phase: 'projection_store_apply',
					durationMilliseconds: storeApplyDurationMilliseconds,
					executionLane: taskExecutionLane,
					reviewPackage: props.reviewPackage,
					result: 'success',
				});
				recordBridgeProjectionCoordinatorTelemetry({
					telemetryRecorder: props.telemetryRecorder,
					traceContext: props.telemetryParentTraceContext,
					phase: 'projection_total',
					durationMilliseconds: performance.now() - projectionTotalStartMilliseconds,
					executionLane: taskExecutionLane,
					reviewPackage: props.reviewPackage,
					result: 'success',
				});
				recordBridgeProjectionBuildTelemetry({
					telemetryRecorder: props.telemetryRecorder,
					parentTraceContext: props.telemetryParentTraceContext,
					reviewPackage: props.reviewPackage,
					projectionMode: props.projectionMode,
					durationMilliseconds: completion.response.metrics.durationMilliseconds,
					executionLane: taskExecutionLane,
					treePathCount: completion.response.metrics.treePathCount,
				});
				props.flushTelemetry({ force: true });
			})
			.catch((): void => {
				if (!isCurrentRequest) {
					return;
				}
				if (taskExecutionLane === 'worker') {
					startProjectionTask(props.syncProjectionClient, 'sync');
					return;
				}
				props.store.getState().actions.failProjectionRequest(task.identity);
			});
		return task;
	};
	startProjectionTask(projectionClient, executionLane);

	return (): void => {
		isCurrentRequest = false;
		activeTask?.abort();
		if (activeTask !== null) {
			props.store.getState().actions.cancelProjectionRequest(activeTask.identity);
		}
	};
}

function projectedTreePathCount(
	items: readonly {
		readonly basePath?: string | null;
		readonly headPath?: string | null;
	}[],
): number {
	return new Set(
		items.flatMap((item): readonly string[] =>
			[item.basePath, item.headPath].filter(
				(path: string | null | undefined): path is string => path !== null && path !== undefined,
			),
		),
	).size;
}

function activeFacetPathCount(
	items: readonly { readonly itemId: string }[],
	facets: readonly BridgeReviewProjectionFacet[],
): number {
	return hasActiveNonVisibilityFacet(facets) ? items.length : 0;
}

function hasActiveNonVisibilityFacet(facets: readonly BridgeReviewProjectionFacet[]): boolean {
	return facets.some((facet: BridgeReviewProjectionFacet): boolean => facet.kind !== 'visibility');
}
