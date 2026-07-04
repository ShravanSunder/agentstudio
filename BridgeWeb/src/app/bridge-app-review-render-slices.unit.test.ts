import { describe, expect, test } from 'vitest';

import { bridgeReviewViewerRenderSliceStateKeys } from '../review-viewer/state/review-viewer-store.js';

describe('BridgeApp review render slices', () => {
	test('review interaction path keeps protocol state out of FE render slices', () => {
		const forbiddenProtocolKeys = new Set([
			'activeProjectionRequestIdentity',
			'contentHydrationByItemId',
			'projectionIdentity',
			'reviewGeneration',
			'sequence',
			'staleness',
			'cacheMembership',
			'retryMembership',
			'demandMembership',
		]);

		expect(
			bridgeReviewViewerRenderSliceStateKeys().filter((key) => forbiddenProtocolKeys.has(key)),
		).toEqual([]);
	});
});
