import { useEffect, useMemo } from 'react';

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
	BridgeReviewProjectionRefinement,
	BridgeReviewProjectionWorkloadId,
} from '../models/review-projection-models.js';
import { makeBridgeReviewProjectionRequest } from '../navigation/review-projection-request.js';
import { makeBridgeReviewProjectionInput } from '../navigation/review-projection.js';
import type { BridgeReviewViewerStore } from '../state/review-viewer-store.js';
import { recordBridgeProjectionBuildTelemetry } from '../telemetry/bridge-review-viewer-telemetry.js';
import { createBridgeReviewProjectionSyncClient } from '../workers/projection/review-projection-sync-client.js';
import type { BridgeReviewProjectionWorkerClient } from '../workers/projection/review-projection-worker-client.js';
import { selectBridgeReviewProjectionExecutionLane } from '../workers/projection/review-projection-worker-planner.js';

export interface UseBridgeReviewProjectionCoordinatorProps {
	readonly store: BridgeReviewViewerStore;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly projectionMode: BridgeReviewProjectionMode;
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

export function useBridgeReviewProjectionCoordinator(
	props: UseBridgeReviewProjectionCoordinatorProps,
): void {
	const {
		fileClassFilter,
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

	useEffect((): (() => void) | undefined => {
		if (reviewPackage === null) {
			return undefined;
		}
		return startBridgeReviewProjectionCoordinatorRequest({
			store,
			reviewPackage,
			projectionMode,
			gitStatusFilter,
			fileClassFilter,
			projectionWorkerClient,
			syncProjectionClient,
			telemetryRecorder,
			telemetryParentTraceContext,
			flushTelemetry,
		});
	}, [
		fileClassFilter,
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

export function startBridgeReviewProjectionCoordinatorRequest(
	props: StartBridgeReviewProjectionCoordinatorRequestProps,
): () => void {
	const projectionRequest = makeBridgeReviewProjectionRequest({
		projectionMode: props.projectionMode,
		gitStatusFilter: props.gitStatusFilter,
		fileClassFilter: props.fileClassFilter,
	});
	const projectionInput = makeBridgeReviewProjectionInput(props.reviewPackage);
	const decision = selectBridgeReviewProjectionExecutionLane({
		changedItemCount: projectionInput.orderedItems.length,
		projectedTreePathCount: projectedTreePathCount(projectionInput.orderedItems),
		activeRefinementPathCount: activeRefinementPathCount(
			projectionInput.orderedItems,
			projectionRequest.refinements,
		),
		hasActiveNonVisibilityRefinement: hasActiveNonVisibilityRefinement(
			projectionRequest.refinements,
		),
		workloadId: projectionWorkloadId,
	});
	const executionLane =
		decision.lane === 'worker' && props.projectionWorkerClient !== null ? 'worker' : 'sync';
	const projectionClient =
		executionLane === 'worker' && props.projectionWorkerClient !== null
			? props.projectionWorkerClient
			: props.syncProjectionClient;
	const task = projectionClient.startProjection({
		abortKey: projectionAbortKey,
		projectionInput,
		projectionRequest,
		visibleItemIds: [],
		workloadId: projectionWorkloadId,
	});
	props.store.getState().actions.startProjectionRequest(task.identity);
	props.store.getState().actions.setWorkerStatus({
		lane: executionLane,
		pendingRequestCount: 1,
		lastCompletedRequestId: props.store.getState().workerStatus.lastCompletedRequestId,
	});

	let isCurrentRequest = true;
	void task.completed
		.then((completion): void => {
			if (!isCurrentRequest) {
				return;
			}
			if (completion.status !== 'success') {
				props.store.getState().actions.failProjectionRequest(completion.identity);
				return;
			}
			const didApply = props.store.getState().actions.applyProjectionWorkerResult({
				identity: completion.identity,
				result: completion.response.result,
			});
			if (!didApply) {
				return;
			}
			recordBridgeProjectionBuildTelemetry({
				telemetryRecorder: props.telemetryRecorder,
				parentTraceContext: props.telemetryParentTraceContext,
				reviewPackage: props.reviewPackage,
				projectionMode: props.projectionMode,
				durationMilliseconds: completion.response.metrics.durationMilliseconds,
				executionLane,
				treePathCount: completion.response.metrics.treePathCount,
			});
			props.flushTelemetry({ force: true });
		})
		.catch((): void => {
			if (isCurrentRequest) {
				props.store.getState().actions.failProjectionRequest(task.identity);
			}
		});

	return (): void => {
		isCurrentRequest = false;
		task.abort();
		props.store.getState().actions.cancelProjectionRequest(task.identity);
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

function activeRefinementPathCount(
	items: readonly { readonly itemId: string }[],
	refinements: readonly BridgeReviewProjectionRefinement[],
): number {
	return hasActiveNonVisibilityRefinement(refinements) ? items.length : 0;
}

function hasActiveNonVisibilityRefinement(
	refinements: readonly BridgeReviewProjectionRefinement[],
): boolean {
	return refinements.some(
		(refinement: BridgeReviewProjectionRefinement): boolean => refinement.kind !== 'visibility',
	);
}
