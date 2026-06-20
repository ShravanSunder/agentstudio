import { describe, expect, test } from 'vitest';

import { selectBridgeReviewProjectionExecutionLane } from './review-projection-worker-planner.js';

describe('selectBridgeReviewProjectionExecutionLane', () => {
	test('keeps small interactive projections on the sync lane', () => {
		const decision = selectBridgeReviewProjectionExecutionLane({
			changedItemCount: 32,
			projectedTreePathCount: 500,
			activeRefinementPathCount: 500,
			hasActiveNonVisibilityRefinement: true,
			workloadId: 'interactive',
		});

		expect(decision).toEqual({
			lane: 'sync',
			reason: 'smallInteractiveProjection',
		});
	});

	test('uses the worker lane when changed item or tree path thresholds are exceeded', () => {
		expect(
			selectBridgeReviewProjectionExecutionLane({
				changedItemCount: 33,
				projectedTreePathCount: 500,
				activeRefinementPathCount: 0,
				hasActiveNonVisibilityRefinement: false,
				workloadId: 'interactive',
			}),
		).toEqual({
			lane: 'worker',
			reason: 'changedItemThreshold',
		});

		expect(
			selectBridgeReviewProjectionExecutionLane({
				changedItemCount: 1,
				projectedTreePathCount: 501,
				activeRefinementPathCount: 0,
				hasActiveNonVisibilityRefinement: false,
				workloadId: 'interactive',
			}),
		).toEqual({
			lane: 'worker',
			reason: 'treePathThreshold',
		});
	});

	test('uses the worker lane for large refinement work and named benchmark workloads', () => {
		expect(
			selectBridgeReviewProjectionExecutionLane({
				changedItemCount: 1,
				projectedTreePathCount: 500,
				activeRefinementPathCount: 501,
				hasActiveNonVisibilityRefinement: true,
				workloadId: 'interactive',
			}),
		).toEqual({
			lane: 'worker',
			reason: 'refinementThreshold',
		});

		expect(
			selectBridgeReviewProjectionExecutionLane({
				changedItemCount: 1,
				projectedTreePathCount: 1,
				activeRefinementPathCount: 0,
				hasActiveNonVisibilityRefinement: false,
				workloadId: 'bridge_viewer_medium_review_v1',
			}),
		).toEqual({
			lane: 'worker',
			reason: 'workloadRequiresWorker',
		});
	});
});
