import { buildBridgeWorkerReviewCandidateReadyEvent } from './bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerReviewCandidateReadyPublication } from './bridge-comm-worker-review-metadata-applicator.js';
import type { BridgeWorkerReviewCandidateReadyEvent } from './bridge-worker-contracts.js';

export function buildBridgeCommWorkerReviewCandidateReadyPublication(
	publication: BridgeCommWorkerReviewCandidateReadyPublication,
	createSequence: () => number,
): BridgeWorkerReviewCandidateReadyEvent {
	return buildBridgeWorkerReviewCandidateReadyEvent({
		affectedStableFileIdentities: publication.affectedStableFileIdentities,
		epoch: publication.workerDerivationEpoch,
		packageId: publication.identity.packageId,
		preDeliveryPresentationClass: publication.preDeliveryPresentationClass,
		publicationId: publication.identity.publicationId,
		reviewGeneration: publication.identity.generation,
		revision: publication.identity.revision,
		sequence: createSequence(),
		sourceIdentity: publication.identity.sourceIdentity,
	});
}
