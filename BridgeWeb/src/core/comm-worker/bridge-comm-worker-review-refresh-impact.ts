import type { z } from 'zod';

import type { BridgeCommWorkerReviewBatchPresentation } from './bridge-comm-worker-review-batch-installer.js';
import { reviewRuntimeItemSignatures } from './bridge-comm-worker-review-runtime-index.js';
import type { bridgeProductReviewRefreshImpactSchema } from './bridge-product-review-metadata-contracts.js';
import type { BridgeWorkerReviewCandidateStartDisposition } from './bridge-worker-contracts.js';

export type BridgeProductReviewRefreshImpact = z.infer<
	typeof bridgeProductReviewRefreshImpactSchema
>;

export function reviewCandidateStartDispositionFromRefreshImpact(props: {
	readonly impact: BridgeProductReviewRefreshImpact | null;
	readonly previous: BridgeCommWorkerReviewBatchPresentation | null;
	readonly successor: BridgeCommWorkerReviewBatchPresentation;
}): BridgeWorkerReviewCandidateStartDisposition {
	const { impact, previous, successor } = props;
	if (impact === null) return { kind: 'replacement' };
	if (
		previous === null ||
		(impact.preDeliveryPresentationClass.kind === 'promoted' &&
			impact.preDeliveryPresentationClass.reason === 'unknown')
	) {
		return {
			affectedStableFileIdentities: impact.affectedStableFileIdentities,
			kind: 'sameSource',
			presentationClass: impact.preDeliveryPresentationClass,
		};
	}
	const previousSignatures = reviewRuntimeItemSignatures(previous.runtimeSource);
	const successorSignatures = reviewRuntimeItemSignatures(successor.runtimeSource);
	const affectedStableFileIdentities = [
		...new Set([...previousSignatures.keys(), ...successorSignatures.keys()]),
	].filter((itemId): boolean => previousSignatures.get(itemId) !== successorSignatures.get(itemId));
	return {
		affectedStableFileIdentities,
		kind: 'sameSource',
		presentationClass: impact.preDeliveryPresentationClass,
	};
}
