import type { BridgeMainReviewPublicationIdentity } from '../core/comm-worker/bridge-main-review-candidate-bank.js';
import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type { BridgeProductReviewAnnotationPublicationIdentity } from '../core/comm-worker/bridge-product-call-contracts.js';

export interface ReviewAnnotationApplicationCheckpoint {
	readonly catalogCursor: number;
	readonly identity: BridgeProductReviewAnnotationPublicationIdentity;
}

export interface PendingReviewAnnotationApplicationCheckpoint extends ReviewAnnotationApplicationCheckpoint {
	readonly applicationId: number;
}

export function reviewAnnotationPublicationIdentityForMainIdentity(
	identity: BridgeMainReviewPublicationIdentity,
): BridgeProductReviewAnnotationPublicationIdentity {
	return {
		packageId: identity.packageId,
		publicationId: identity.publicationId,
		reviewGeneration: identity.generation,
		revision: identity.revision,
		sourceIdentity: identity.sourceIdentity,
	};
}

export function reviewAffectedItemIdsForInstalledChanges(props: {
	readonly checkpoint: ReviewAnnotationApplicationCheckpoint | null;
	readonly currentIdentity: BridgeProductReviewAnnotationPublicationIdentity;
	readonly renderStore: BridgePaneSurfaceClient['renderStore'];
	readonly targetCatalogCursor: number;
}): readonly string[] | null {
	if (
		props.checkpoint === null ||
		!reviewAnnotationCheckpointCanAdvance(props.checkpoint.identity, props.currentIdentity)
	) {
		return null;
	}
	const changeRead = props.renderStore.readReviewCatalogChangesAfter(
		props.checkpoint.catalogCursor,
	);
	const representedChanges = changeRead.changes.filter(
		(change): boolean => change.cursor <= props.targetCatalogCursor,
	);
	if (changeRead.resetRequired || representedChanges.some((change): boolean => change.reset)) {
		return null;
	}
	return [...new Set(representedChanges.flatMap((change) => change.itemIds))];
}

export function reviewAnnotationPublicationIdentitiesMatch(
	left: BridgeProductReviewAnnotationPublicationIdentity,
	right:
		| BridgeProductReviewAnnotationPublicationIdentity
		| {
				readonly generation: number;
				readonly packageId: string;
				readonly publicationId: string;
				readonly revision: number;
				readonly sourceIdentity: string;
		  }
		| null,
): boolean {
	return (
		right !== null &&
		left.packageId === right.packageId &&
		left.publicationId === right.publicationId &&
		left.reviewGeneration ===
			('reviewGeneration' in right ? right.reviewGeneration : right.generation) &&
		left.revision === right.revision &&
		left.sourceIdentity === right.sourceIdentity
	);
}

export function annotationContentSessionIdsMeetCurrentDemand(
	contentSessionIds: readonly string[],
	expectedContentSessionIds: readonly string[],
): boolean {
	const contentSessionIdSet = new Set(contentSessionIds);
	return expectedContentSessionIds.every((sessionId): boolean =>
		contentSessionIdSet.has(sessionId),
	);
}

function reviewAnnotationCheckpointCanAdvance(
	checkpointIdentity: BridgeProductReviewAnnotationPublicationIdentity,
	currentIdentity: BridgeProductReviewAnnotationPublicationIdentity,
): boolean {
	if (
		checkpointIdentity.packageId !== currentIdentity.packageId ||
		checkpointIdentity.sourceIdentity !== currentIdentity.sourceIdentity ||
		checkpointIdentity.reviewGeneration !== currentIdentity.reviewGeneration ||
		checkpointIdentity.revision > currentIdentity.revision
	) {
		return false;
	}
	return (
		checkpointIdentity.revision < currentIdentity.revision ||
		checkpointIdentity.publicationId === currentIdentity.publicationId
	);
}
