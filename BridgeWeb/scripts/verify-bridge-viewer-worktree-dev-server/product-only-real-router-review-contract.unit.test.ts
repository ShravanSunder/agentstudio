import { describe, expect, test } from 'vitest';

import { isFreshReviewTraversalMilestoneReady } from './product-only-real-router-review-proof.ts';

describe('Bridge Viewer product-only Review contract', () => {
	test('defers the final hydration milestone until traversal reaches its terminal window', () => {
		// Arrange
		const observedItemCount = 16;

		// Act
		const middleMilestoneReady = isFreshReviewTraversalMilestoneReady({
			milestone: { label: 'middle', minimumObservedItemCount: 8 },
			observedItemCount,
		});
		const finalMilestoneReady = isFreshReviewTraversalMilestoneReady({
			milestone: { label: 'final', minimumObservedItemCount: 16 },
			observedItemCount,
		});

		// Assert
		expect(middleMilestoneReady).toBe(true);
		expect(finalMilestoneReady).toBe(false);
	});
});
