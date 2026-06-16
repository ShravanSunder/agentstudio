import { useEffect, useMemo } from 'react';

import type {
	BridgeFileChangeKind,
	BridgeFileClass,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
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
import { createBridgeReviewProjectionSyncClient } from '../workers/rpc/review-projection-sync-client.js';
import type { BridgeReviewProjectionWorkerClient } from '../workers/rpc/review-projection-worker-client.js';
import { selectBridgeReviewProjectionExecutionLane } from '../workers/rpc/review-projection-worker-planner.js';

export interface UseBridgeReviewProjectionCoordinatorProps {
	readonly store: BridgeReviewViewerStore;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly gitStatusFilter: BridgeFileChangeKind | 'all';
	readonly fileClassFilter: BridgeFileClass | 'all';
	readonly projectionWorkerClient: BridgeReviewProjectionWorkerClient | null;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly telemetryParentTraceContext: BridgeTraceContext | null;
	readonly flushTelemetry: () => void;
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

		const projectionRequest = makeBridgeReviewProjectionRequest({
			projectionMode,
			gitStatusFilter,
			fileClassFilter,
		});
		const projectionInput = makeBridgeReviewProjectionInput(reviewPackage);
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
			decision.lane === 'worker' && projectionWorkerClient !== null ? 'worker' : 'sync';
		const projectionClient =
			executionLane === 'worker' && projectionWorkerClient !== null
				? projectionWorkerClient
				: syncProjectionClient;
		const task = projectionClient.startProjection({
			abortKey: projectionAbortKey,
			projectionInput,
			projectionRequest,
			visibleItemIds: [],
			workloadId: projectionWorkloadId,
		});
		store.getState().actions.startProjectionRequest(task.identity);
		store.getState().actions.setWorkerStatus({
			lane: executionLane,
			pendingRequestCount: 1,
			lastCompletedRequestId: store.getState().workerStatus.lastCompletedRequestId,
		});

		let isCurrentRequest = true;
		void task.completed
			.then((completion): void => {
				if (!isCurrentRequest) {
					return;
				}
				if (completion.status !== 'success') {
					store.getState().actions.failProjectionRequest(completion.identity);
					return;
				}
				const didApply = store.getState().actions.applyProjectionWorkerResult({
					identity: completion.identity,
					result: completion.response.result,
				});
				if (!didApply) {
					return;
				}
				recordBridgeProjectionBuildTelemetry({
					telemetryRecorder,
					parentTraceContext: telemetryParentTraceContext,
					reviewPackage,
					projectionMode,
					durationMilliseconds: completion.response.metrics.durationMilliseconds,
					executionLane,
					treePathCount: completion.response.metrics.treePathCount,
				});
				flushTelemetry();
			})
			.catch((): void => {
				if (isCurrentRequest) {
					store.getState().actions.failProjectionRequest(task.identity);
				}
			});

		return (): void => {
			isCurrentRequest = false;
		};
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

function projectedTreePathCount(
	items: readonly { readonly basePath: string | null; readonly headPath: string | null }[],
): number {
	return new Set(
		items.flatMap((item): readonly string[] =>
			[item.basePath, item.headPath].filter((path): path is string => path !== null),
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
