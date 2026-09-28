import type { z } from 'zod';

import type { bridgeProductReviewRefreshImpactSchema } from './bridge-product-review-metadata-contracts.js';
import type { BridgeWorkerReviewCandidateStartDisposition } from './bridge-worker-contracts.js';

export type BridgeProductReviewRefreshImpact = z.infer<
	typeof bridgeProductReviewRefreshImpactSchema
>;

export function reviewCandidateStartDispositionFromRefreshImpact(
	impact: BridgeProductReviewRefreshImpact | null,
): BridgeWorkerReviewCandidateStartDisposition {
	if (impact === null) return { kind: 'replacement' };
	return {
		affectedStableFileIdentities: impact.affectedStableFileIdentities,
		kind: 'sameSource',
		presentationClass: impact.preDeliveryPresentationClass,
	};
}
