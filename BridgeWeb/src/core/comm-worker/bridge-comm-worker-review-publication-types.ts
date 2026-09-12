import type { ReviewMetadataLineage } from './bridge-comm-worker-review-publication-transaction.js';
import type { BridgeProductReviewComparisonPresentation } from './bridge-product-review-comparison-presentation-contracts.js';
import type { BridgeWorkerReviewCandidateStartDisposition } from './bridge-worker-contracts.js';

export interface BridgeCommWorkerReviewCandidateReadyFacts {
	readonly disposition: BridgeWorkerReviewCandidateStartDisposition;
	readonly identity: ReviewMetadataLineage;
}

export interface BridgeCommWorkerReviewCandidateStartedPublication extends BridgeCommWorkerReviewCandidateReadyFacts {
	readonly workerDerivationEpoch: number;
}

export interface BridgeCommWorkerReviewCandidateFailedPublication {
	readonly identity: ReviewMetadataLineage;
	readonly retryable: boolean;
	readonly workerDerivationEpoch: number;
}

export interface BridgeCommWorkerReviewCandidateReadyPublication extends BridgeCommWorkerReviewCandidateReadyFacts {
	readonly workerDerivationEpoch: number;
}

export interface BridgeCommWorkerReviewComparisonCommit {
	readonly presentationRevision: number;
	readonly reviewComparison: BridgeProductReviewComparisonPresentation | null;
}
