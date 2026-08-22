import type { ReviewMetadataLineage } from './bridge-comm-worker-review-publication-transaction.js';
import type { BridgeProductReviewComparisonPresentation } from './bridge-product-review-comparison-presentation-contracts.js';
import type { BridgeWorkerReviewPreDeliveryPresentationClass } from './bridge-worker-contracts.js';

export interface BridgeCommWorkerReviewCandidateReadyFacts {
	readonly affectedStableFileIdentities: readonly string[];
	readonly identity: ReviewMetadataLineage;
	readonly preDeliveryPresentationClass: BridgeWorkerReviewPreDeliveryPresentationClass;
}

export interface BridgeCommWorkerReviewCandidateReadyPublication extends BridgeCommWorkerReviewCandidateReadyFacts {
	readonly workerDerivationEpoch: number;
}

export interface BridgeCommWorkerReviewComparisonCommit {
	readonly presentationRevision: number;
	readonly reviewComparison: BridgeProductReviewComparisonPresentation | null;
}
