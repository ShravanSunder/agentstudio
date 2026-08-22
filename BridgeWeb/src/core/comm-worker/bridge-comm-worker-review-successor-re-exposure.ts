import { bridgeCommWorkerReviewDisplayPatches } from './bridge-comm-worker-review-display-projection.js';
import type { BridgeCommWorkerReviewMetadataSnapshot } from './bridge-comm-worker-review-metadata-projection.js';
import {
	compareReviewMetadataLineages,
	reviewMetadataSnapshotEventFromCompleteSnapshot,
	type ReviewMetadataLineage,
} from './bridge-comm-worker-review-publication-transaction.js';
import type {
	BridgeCommWorkerReviewCandidateReadyFacts,
	BridgeCommWorkerReviewCandidateReadyPublication,
	BridgeCommWorkerReviewComparisonCommit,
} from './bridge-comm-worker-review-publication-types.js';
import type {
	BridgeWorkerReviewDisplayPatch,
	BridgeWorkerReviewPublicationIdentity,
	BridgeWorkerReviewSourceDisplayPayload,
} from './bridge-worker-contracts.js';

export type BridgeCommWorkerReviewSuccessorReExposureFence =
	| {
			readonly admissionFailureRetryUsed: boolean;
			readonly installed: ReviewMetadataLineage;
			readonly kind: 'installedPair';
			readonly successor: ReviewMetadataLineage;
	  }
	| {
			readonly admissionFailureRetryUsed: boolean;
			readonly kind: 'admissionRecovery';
			readonly successor: ReviewMetadataLineage;
			readonly triggerPublicationId: string;
	  };

export type BridgeCommWorkerReviewSuccessorReExposureSettlement =
	| { readonly candidatePublicationId: string; readonly kind: 'admissionFailed' }
	| { readonly candidatePublicationId: string; readonly kind: 'admissionRejected' }
	| {
			readonly identity: BridgeWorkerReviewPublicationIdentity;
			readonly kind: 'publicationApplied';
	  };

export function handleBridgeCommWorkerReviewSuccessorReExposureSettlement(props: {
	readonly activeSnapshot: BridgeCommWorkerReviewMetadataSnapshot | null;
	readonly currentWorkerDerivationEpoch: number;
	readonly lastReExposureFence: BridgeCommWorkerReviewSuccessorReExposureFence | null;
	readonly latestProjectionRevision: number;
	readonly publishCandidateReady:
		| ((publication: BridgeCommWorkerReviewCandidateReadyPublication) => void)
		| undefined;
	readonly publishDisplayPatches:
		| ((publication: {
				readonly comparisonCommit?: BridgeCommWorkerReviewComparisonCommit | undefined;
				readonly operationCorrelationId?: string | null;
				readonly patches: readonly BridgeWorkerReviewDisplayPatch[];
				readonly reviewPublicationIdentity: BridgeWorkerReviewPublicationIdentity | null;
				readonly workerDerivationEpoch: number;
		  }) => void)
		| undefined;
	readonly readyFacts: BridgeCommWorkerReviewCandidateReadyFacts | null;
	readonly settlement: BridgeCommWorkerReviewSuccessorReExposureSettlement;
	readonly sourceDisplayStatus: BridgeWorkerReviewSourceDisplayPayload['status'];
	readonly workerDerivationEpoch: number | null;
}): {
	readonly lastReExposureFence: BridgeCommWorkerReviewSuccessorReExposureFence | null;
	readonly reExposed: boolean;
} {
	const workerDerivationEpoch =
		props.settlement.kind === 'publicationApplied'
			? props.workerDerivationEpoch
			: props.currentWorkerDerivationEpoch;
	if (
		workerDerivationEpoch === null ||
		workerDerivationEpoch !== props.currentWorkerDerivationEpoch
	) {
		return { lastReExposureFence: props.lastReExposureFence, reExposed: false };
	}
	const activeSnapshot = props.activeSnapshot;
	const readyFacts = props.readyFacts;
	if (activeSnapshot === null || readyFacts === null) {
		return { lastReExposureFence: props.lastReExposureFence, reExposed: false };
	}
	if (props.settlement.kind === 'publicationApplied') {
		const reExposureFence = reExposeBridgeCommWorkerReviewSuccessor({
			...props,
			activeSnapshot,
			installedIdentity: props.settlement.identity,
			lastReExposedPair: props.lastReExposureFence,
			readyFacts,
			workerDerivationEpoch,
		});
		return {
			lastReExposureFence: reExposureFence ?? props.lastReExposureFence,
			reExposed: reExposureFence !== null,
		};
	}
	const activeMatchesCandidate =
		readyFacts.identity.publicationId === props.settlement.candidatePublicationId;
	if (props.settlement.kind === 'admissionRejected' && activeMatchesCandidate) {
		return { lastReExposureFence: props.lastReExposureFence, reExposed: false };
	}
	if (
		props.settlement.kind === 'admissionFailed' &&
		props.lastReExposureFence?.successor.publicationId === readyFacts.identity.publicationId &&
		props.lastReExposureFence.admissionFailureRetryUsed
	) {
		return { lastReExposureFence: props.lastReExposureFence, reExposed: false };
	}
	publishBridgeCommWorkerActiveReviewProjection({
		...props,
		activeSnapshot,
		readyFacts,
		workerDerivationEpoch,
	});
	return {
		lastReExposureFence: {
			admissionFailureRetryUsed:
				props.settlement.kind === 'admissionFailed' && activeMatchesCandidate,
			kind: 'admissionRecovery',
			successor: readyFacts.identity,
			triggerPublicationId: props.settlement.candidatePublicationId,
		},
		reExposed: true,
	};
}

export function reExposeBridgeCommWorkerReviewSuccessor(props: {
	readonly activeSnapshot: BridgeCommWorkerReviewMetadataSnapshot;
	readonly installedIdentity: BridgeWorkerReviewPublicationIdentity;
	readonly lastReExposedPair: BridgeCommWorkerReviewSuccessorReExposureFence | null;
	readonly latestProjectionRevision: number;
	readonly publishCandidateReady:
		| ((publication: BridgeCommWorkerReviewCandidateReadyPublication) => void)
		| undefined;
	readonly publishDisplayPatches:
		| ((publication: {
				readonly comparisonCommit?: BridgeCommWorkerReviewComparisonCommit | undefined;
				readonly operationCorrelationId?: string | null;
				readonly patches: readonly BridgeWorkerReviewDisplayPatch[];
				readonly reviewPublicationIdentity: BridgeWorkerReviewPublicationIdentity | null;
				readonly workerDerivationEpoch: number;
		  }) => void)
		| undefined;
	readonly readyFacts: BridgeCommWorkerReviewCandidateReadyFacts;
	readonly sourceDisplayStatus: BridgeWorkerReviewSourceDisplayPayload['status'];
	readonly workerDerivationEpoch: number;
}): BridgeCommWorkerReviewSuccessorReExposureFence | null {
	const installedLineage = reviewMetadataLineageFromWorkerIdentity(props.installedIdentity);
	if (compareReviewMetadataLineages(props.readyFacts.identity, installedLineage) !== 'newer') {
		return null;
	}
	const lastFence = props.lastReExposedPair;
	if (
		lastFence !== null &&
		compareReviewMetadataLineages(lastFence.successor, props.readyFacts.identity) === 'same' &&
		(lastFence.kind === 'admissionRecovery' ||
			compareReviewMetadataLineages(lastFence.installed, installedLineage) === 'same')
	) {
		return null;
	}

	publishBridgeCommWorkerActiveReviewProjection(props);
	return {
		admissionFailureRetryUsed: false,
		installed: installedLineage,
		kind: 'installedPair',
		successor: props.readyFacts.identity,
	};
}

export function reconcileBridgeCommWorkerReviewSuccessorReExposureFence(
	fence: BridgeCommWorkerReviewSuccessorReExposureFence | null,
	activeIdentity: ReviewMetadataLineage,
): BridgeCommWorkerReviewSuccessorReExposureFence | null {
	if (fence === null) return null;
	const relationship = compareReviewMetadataLineages(activeIdentity, fence.successor);
	return relationship === 'same' || relationship === 'newer' ? fence : null;
}

export function publishBridgeCommWorkerActiveReviewProjection(props: {
	readonly activeSnapshot: BridgeCommWorkerReviewMetadataSnapshot;
	readonly latestProjectionRevision: number;
	readonly publishCandidateReady:
		| ((publication: BridgeCommWorkerReviewCandidateReadyPublication) => void)
		| undefined;
	readonly publishDisplayPatches:
		| ((publication: {
				readonly comparisonCommit?: BridgeCommWorkerReviewComparisonCommit | undefined;
				readonly operationCorrelationId?: string | null;
				readonly patches: readonly BridgeWorkerReviewDisplayPatch[];
				readonly reviewPublicationIdentity: BridgeWorkerReviewPublicationIdentity | null;
				readonly workerDerivationEpoch: number;
		  }) => void)
		| undefined;
	readonly readyFacts: BridgeCommWorkerReviewCandidateReadyFacts;
	readonly sourceDisplayStatus: BridgeWorkerReviewSourceDisplayPayload['status'];
	readonly workerDerivationEpoch: number;
}): void {
	const event = reviewMetadataSnapshotEventFromCompleteSnapshot(props.activeSnapshot);
	const comparisonCommit = props.activeSnapshot.comparisonCommit;
	if (comparisonCommit.status !== 'committed') {
		throw new Error('Bridge Review successor re-exposure requires a committed comparison.');
	}
	props.publishDisplayPatches?.({
		comparisonCommit: {
			presentationRevision: comparisonCommit.presentationRevision,
			reviewComparison: comparisonCommit.reviewComparison,
		},
		operationCorrelationId: props.activeSnapshot.identity?.operationCorrelationId ?? null,
		patches: bridgeCommWorkerReviewDisplayPatches({
			event,
			projectionResult: {
				affectedItemIds: props.activeSnapshot.orderedItemIds,
				invalidation: null,
				projectionRevision: props.latestProjectionRevision,
				reset: true,
			},
			snapshot: props.activeSnapshot,
			sourceStatus: props.sourceDisplayStatus,
		}),
		reviewPublicationIdentity: workerPublicationIdentity(props.readyFacts.identity),
		workerDerivationEpoch: props.workerDerivationEpoch,
	});
	props.publishCandidateReady?.({
		...props.readyFacts,
		workerDerivationEpoch: props.workerDerivationEpoch,
	});
}

function reviewMetadataLineageFromWorkerIdentity(
	identity: BridgeWorkerReviewPublicationIdentity,
): ReviewMetadataLineage {
	return {
		generation: identity.reviewGeneration,
		packageId: identity.packageId,
		publicationId: identity.publicationId,
		revision: identity.revision,
		sourceIdentity: identity.sourceIdentity,
	};
}

function workerPublicationIdentity(
	lineage: ReviewMetadataLineage,
): BridgeWorkerReviewPublicationIdentity {
	return {
		packageId: lineage.packageId,
		publicationId: lineage.publicationId,
		reviewGeneration: lineage.generation,
		revision: lineage.revision,
		sourceIdentity: lineage.sourceIdentity,
	};
}
