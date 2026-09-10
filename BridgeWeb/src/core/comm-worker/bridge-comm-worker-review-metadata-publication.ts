import { bridgeCommWorkerReviewDisplayPatches } from './bridge-comm-worker-review-display-projection.js';
import {
	BridgeCommWorkerReviewMetadataProjection,
	type BridgeCommWorkerReviewMetadataApplyResult,
} from './bridge-comm-worker-review-metadata-projection.js';
import {
	reviewMetadataEventCompletesProjection,
	type ReviewMetadataLineage,
} from './bridge-comm-worker-review-publication-transaction.js';
import type {
	BridgeCommWorkerReviewCandidateReadyFacts,
	BridgeCommWorkerReviewCandidateFailedPublication,
	BridgeCommWorkerReviewCandidateReadyPublication,
	BridgeCommWorkerReviewComparisonCommit,
} from './bridge-comm-worker-review-publication-types.js';
import type { BridgeCommWorkerReviewMetadataApplication } from './bridge-comm-worker-review-runtime-application.js';
import {
	reconcileBridgeCommWorkerReviewSuccessorReExposureFence,
	type BridgeCommWorkerReviewSuccessorReExposureFence,
} from './bridge-comm-worker-review-successor-re-exposure.js';
import type { BridgeProductReviewMetadataEvent } from './bridge-product-review-metadata-contracts.js';
import type {
	BridgeWorkerReviewCandidateStartDisposition,
	BridgeWorkerReviewDisplayPatch,
	BridgeWorkerReviewPublicationIdentity,
	BridgeWorkerReviewSourceDisplayPayload,
} from './bridge-worker-contracts.js';

export interface BridgeCommWorkerReviewPublicationTransaction {
	readonly commit: () => void;
	readonly rollback: () => void;
	readonly runPostCommitEffects: () => void;
}

export interface BridgeCommWorkerReviewMetadataPublicationResult {
	readonly activeCandidateReadyFacts: BridgeCommWorkerReviewCandidateReadyFacts | null;
	readonly lastSuccessorReExposureFence: BridgeCommWorkerReviewSuccessorReExposureFence | null;
}

export function publishBridgeCommWorkerReviewMetadataApplication(props: {
	readonly affectedItemIds: readonly string[];
	readonly affectedRowIds: readonly string[];
	readonly applyRuntimeSource: (
		application: BridgeCommWorkerReviewMetadataApplication,
	) => BridgeCommWorkerReviewPublicationTransaction | void;
	readonly candidateStart?: BridgeWorkerReviewCandidateStartDisposition | undefined;
	readonly candidateReadyEvent?: BridgeProductReviewMetadataEvent;
	readonly completeContentItemIds?: readonly string[];
	readonly completeRowIds?: readonly string[];
	readonly event: BridgeProductReviewMetadataEvent;
	readonly lastSuccessorReExposureFence: BridgeCommWorkerReviewSuccessorReExposureFence | null;
	readonly projectionResult: BridgeCommWorkerReviewMetadataApplyResult;
	readonly publishCandidateFailed?:
		| ((publication: BridgeCommWorkerReviewCandidateFailedPublication) => void)
		| undefined;
	readonly publishCandidateReady?:
		| ((publication: BridgeCommWorkerReviewCandidateReadyPublication) => void)
		| undefined;
	readonly publishDisplayPatches?:
		| ((publication: {
				readonly comparisonCommit?: BridgeCommWorkerReviewComparisonCommit | undefined;
				readonly operationCorrelationId?: string | null;
				readonly patches: readonly BridgeWorkerReviewDisplayPatch[];
				readonly reviewPublicationIdentity: BridgeWorkerReviewPublicationIdentity | null;
				readonly workerDerivationEpoch: number;
		  }) => void)
		| undefined;
	readonly removedItemIds: readonly string[];
	readonly reset: boolean;
	readonly rowMutation: BridgeCommWorkerReviewMetadataApplication['rowMutation'];
	readonly runtimeSource: BridgeCommWorkerReviewMetadataApplication['source'];
	readonly snapshot: ReturnType<BridgeCommWorkerReviewMetadataProjection['snapshot']>;
	readonly sourceDisplayStatus: BridgeWorkerReviewSourceDisplayPayload['status'];
	readonly sourceEpoch: number;
	readonly workerDerivationEpoch: number;
}): BridgeCommWorkerReviewMetadataPublicationResult {
	if (props.snapshot.identity === null || props.snapshot.revision === null)
		throw new Error('Review publication requires an exact source identity and revision.');
	const displayPatches = bridgeCommWorkerReviewDisplayPatches({
		event: props.event,
		projectionResult: props.projectionResult,
		snapshot: props.snapshot,
		sourceStatus: props.sourceDisplayStatus,
	});
	const runtimeApplication =
		props.applyRuntimeSource({
			affectedItemIds: props.affectedItemIds,
			affectedRowIds: props.affectedRowIds,
			operationCorrelationId: props.snapshot.identity.operationCorrelationId ?? null,
			...(props.completeContentItemIds === undefined
				? {}
				: { completeContentItemIds: props.completeContentItemIds }),
			...(props.completeRowIds === undefined ? {} : { completeRowIds: props.completeRowIds }),
			projectionRevision: props.projectionResult.projectionRevision,
			removedItemIds: props.removedItemIds,
			reset: props.reset,
			rowMutation: props.rowMutation,
			source: props.runtimeSource,
			sourceEpoch: props.sourceEpoch,
			workerDerivationEpoch: props.workerDerivationEpoch,
		}) ?? undefined;
	const candidateIdentity: ReviewMetadataLineage = {
		generation: props.snapshot.identity.generation,
		packageId: props.snapshot.identity.packageId,
		publicationId: props.snapshot.identity.publicationId,
		revision: props.snapshot.revision,
		sourceIdentity: props.snapshot.identity.sourceIdentity,
	};
	let activeCandidateReadyFacts: BridgeCommWorkerReviewCandidateReadyFacts | null = null;
	let lastSuccessorReExposureFence = props.lastSuccessorReExposureFence;
	try {
		props.publishDisplayPatches?.({
			...(!('presentationRevision' in props.event) ||
			props.event.presentationRevision === undefined ||
			!('reviewComparison' in props.event) ||
			props.event.reviewComparison === undefined
				? {}
				: {
						comparisonCommit: {
							presentationRevision: props.event.presentationRevision,
							reviewComparison: props.event.reviewComparison,
						},
					}),
			operationCorrelationId: props.snapshot.identity.operationCorrelationId ?? null,
			patches: displayPatches,
			reviewPublicationIdentity: {
				packageId: props.snapshot.identity.packageId,
				publicationId: props.snapshot.identity.publicationId,
				reviewGeneration: props.snapshot.identity.generation,
				revision: props.snapshot.revision,
				sourceIdentity: props.snapshot.identity.sourceIdentity,
			},
			workerDerivationEpoch: props.workerDerivationEpoch,
		});
		const candidateReadyEvent = props.candidateReadyEvent ?? props.event;
		if (
			props.candidateStart !== undefined &&
			(candidateReadyEvent.eventKind === 'review.delta' ||
				reviewMetadataEventCompletesProjection(candidateReadyEvent))
		) {
			activeCandidateReadyFacts = {
				disposition: props.candidateStart,
				identity: candidateIdentity,
			};
			props.publishCandidateReady?.({
				...activeCandidateReadyFacts,
				workerDerivationEpoch: props.workerDerivationEpoch,
			});
			lastSuccessorReExposureFence = reconcileBridgeCommWorkerReviewSuccessorReExposureFence(
				lastSuccessorReExposureFence,
				activeCandidateReadyFacts.identity,
			);
		}
	} catch (error) {
		runtimeApplication?.rollback();
		if (props.candidateStart !== undefined)
			props.publishCandidateFailed?.({
				identity: candidateIdentity,
				retryable: true,
				workerDerivationEpoch: props.workerDerivationEpoch,
			});
		throw error;
	}
	runtimeApplication?.commit();
	runtimeApplication?.runPostCommitEffects();
	return {
		activeCandidateReadyFacts,
		lastSuccessorReExposureFence,
	};
}
