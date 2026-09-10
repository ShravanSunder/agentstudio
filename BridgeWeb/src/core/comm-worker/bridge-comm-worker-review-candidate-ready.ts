import {
	buildBridgeWorkerReviewCandidateReadyEvent,
	buildBridgeWorkerReviewCandidateFailedEvent,
	buildBridgeWorkerReviewCandidateStartedEvent,
} from './bridge-comm-worker-protocol.js';
import type {
	BridgeCommWorkerReviewCandidateReadyPublication,
	BridgeCommWorkerReviewCandidateFailedPublication,
	BridgeCommWorkerReviewCandidateStartedPublication,
} from './bridge-comm-worker-review-publication-types.js';
import type {
	BridgeWorkerReviewCandidateReadyEvent,
	BridgeWorkerReviewCandidateFailedEvent,
	BridgeWorkerReviewCandidateStartedEvent,
} from './bridge-worker-contracts.js';

export function buildBridgeCommWorkerReviewCandidateReadyPublication(
	publication: BridgeCommWorkerReviewCandidateReadyPublication,
	createSequence: () => number,
): BridgeWorkerReviewCandidateReadyEvent {
	return buildBridgeWorkerReviewCandidateReadyEvent({
		epoch: publication.workerDerivationEpoch,
		packageId: publication.identity.packageId,
		publicationId: publication.identity.publicationId,
		reviewGeneration: publication.identity.generation,
		revision: publication.identity.revision,
		sequence: createSequence(),
		sourceIdentity: publication.identity.sourceIdentity,
	});
}

export function buildBridgeCommWorkerReviewCandidateFailedPublication(
	publication: BridgeCommWorkerReviewCandidateFailedPublication,
	createSequence: () => number,
): BridgeWorkerReviewCandidateFailedEvent {
	return buildBridgeWorkerReviewCandidateFailedEvent({
		epoch: publication.workerDerivationEpoch,
		packageId: publication.identity.packageId,
		publicationId: publication.identity.publicationId,
		retryable: publication.retryable,
		reviewGeneration: publication.identity.generation,
		revision: publication.identity.revision,
		sequence: createSequence(),
		sourceIdentity: publication.identity.sourceIdentity,
	});
}

export function buildBridgeCommWorkerReviewCandidateStartedPublication(
	publication: BridgeCommWorkerReviewCandidateStartedPublication,
	createSequence: () => number,
): BridgeWorkerReviewCandidateStartedEvent {
	return buildBridgeWorkerReviewCandidateStartedEvent({
		disposition: publication.disposition,
		epoch: publication.workerDerivationEpoch,
		packageId: publication.identity.packageId,
		publicationId: publication.identity.publicationId,
		reviewGeneration: publication.identity.generation,
		revision: publication.identity.revision,
		sequence: createSequence(),
		sourceIdentity: publication.identity.sourceIdentity,
	});
}
