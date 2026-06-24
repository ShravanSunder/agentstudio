import type { BridgeReviewProjectionWorkloadId } from '../../models/review-projection-models.js';

export type BridgeReviewProjectionExecutionLane = 'sync' | 'worker';

export type BridgeReviewProjectionExecutionReason =
	| 'smallInteractiveProjection'
	| 'changedItemThreshold'
	| 'treePathThreshold'
	| 'refinementThreshold'
	| 'workloadRequiresWorker';

export interface SelectBridgeReviewProjectionExecutionLaneProps {
	readonly changedItemCount: number;
	readonly projectedTreePathCount: number;
	readonly activeRefinementPathCount: number;
	readonly hasActiveNonVisibilityRefinement: boolean;
	readonly workloadId: BridgeReviewProjectionWorkloadId;
}

export interface BridgeReviewProjectionExecutionLaneDecision {
	readonly lane: BridgeReviewProjectionExecutionLane;
	readonly reason: BridgeReviewProjectionExecutionReason;
}

const maximumSyncChangedItemCount = 32;
const maximumSyncProjectedTreePathCount = 500;
const maximumSyncActiveRefinementPathCount = 500;

const workerOnlyWorkloads = new Set<BridgeReviewProjectionWorkloadId>([
	'bridge_viewer_medium_review_v1',
	'bridge_viewer_large_tree_v1',
	'bridge_viewer_large_diff_scroll_v1',
]);

export function selectBridgeReviewProjectionExecutionLane(
	props: SelectBridgeReviewProjectionExecutionLaneProps,
): BridgeReviewProjectionExecutionLaneDecision {
	if (workerOnlyWorkloads.has(props.workloadId)) {
		return {
			lane: 'worker',
			reason: 'workloadRequiresWorker',
		};
	}
	if (props.changedItemCount > maximumSyncChangedItemCount) {
		return {
			lane: 'worker',
			reason: 'changedItemThreshold',
		};
	}
	if (props.projectedTreePathCount > maximumSyncProjectedTreePathCount) {
		return {
			lane: 'worker',
			reason: 'treePathThreshold',
		};
	}
	if (
		props.hasActiveNonVisibilityRefinement &&
		props.activeRefinementPathCount > maximumSyncActiveRefinementPathCount
	) {
		return {
			lane: 'worker',
			reason: 'refinementThreshold',
		};
	}
	return {
		lane: 'sync',
		reason: 'smallInteractiveProjection',
	};
}
