import { describe, expect, test } from 'vitest';

import { bridgeReviewContentDemandByteBudget } from './bridge-review-content-byte-budget.js';

describe('Bridge Review content byte budget', () => {
	test('keeps per-body admission at 4 MiB and pane-local registry retention at 128 MiB', () => {
		expect(bridgeReviewContentDemandByteBudget.maxContentBytesPerRole).toBe(4 * 1024 * 1024);
		expect(bridgeReviewContentDemandByteBudget.bodyRegistryMaxBytes).toBe(128 * 1024 * 1024);
	});
});
