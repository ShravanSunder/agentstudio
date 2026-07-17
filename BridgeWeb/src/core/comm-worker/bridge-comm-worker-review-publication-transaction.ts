import type { BridgeCommWorkerReviewMetadataSnapshot } from './bridge-comm-worker-review-metadata-projection.js';
import type { BridgeProductReviewMetadataEvent } from './bridge-product-review-metadata-contracts.js';

export type ReviewMetadataSnapshotEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.snapshot' }
>;

export type ReviewMetadataLineageRelationship = 'ambiguous' | 'newer' | 'older' | 'same';

export interface ReviewMetadataLineage {
	readonly generation: number;
	readonly packageId: string;
	readonly publicationId: string;
	readonly revision: number;
	readonly sourceIdentity: string;
}

export function reviewMetadataLineage(
	event: BridgeProductReviewMetadataEvent,
): ReviewMetadataLineage {
	return {
		generation: event.generation,
		packageId: event.packageId,
		publicationId: event.publicationId,
		revision: event.revision,
		sourceIdentity: event.sourceIdentity,
	};
}

export function compareReviewMetadataLineages(
	candidate: ReviewMetadataLineage,
	acceptedFloor: ReviewMetadataLineage,
): ReviewMetadataLineageRelationship {
	if (candidate.generation < acceptedFloor.generation) return 'older';
	if (candidate.generation > acceptedFloor.generation) return 'newer';
	if (
		candidate.packageId !== acceptedFloor.packageId ||
		candidate.sourceIdentity !== acceptedFloor.sourceIdentity
	) {
		return 'ambiguous';
	}
	if (candidate.revision < acceptedFloor.revision) return 'older';
	if (candidate.revision > acceptedFloor.revision) return 'newer';
	if (candidate.publicationId !== acceptedFloor.publicationId) return 'ambiguous';
	return 'same';
}

export function assertEquivalentReviewPublicationSnapshots(
	activeSnapshot: BridgeCommWorkerReviewMetadataSnapshot,
	replayedSnapshot: BridgeCommWorkerReviewMetadataSnapshot,
): void {
	if (JSON.stringify(activeSnapshot) !== JSON.stringify(replayedSnapshot)) {
		throw new Error('Bridge Review replay changed payload for an active publication identity.');
	}
}

export function reviewDeltaPublicationFingerprint(
	event: Extract<BridgeProductReviewMetadataEvent, { readonly eventKind: 'review.delta' }>,
): string {
	return JSON.stringify(event);
}

export function reviewMetadataSnapshotEventFromCompleteSnapshot(
	snapshot: BridgeCommWorkerReviewMetadataSnapshot,
): ReviewMetadataSnapshotEvent {
	if (
		snapshot.baseEndpoint === null ||
		snapshot.headEndpoint === null ||
		snapshot.identity === null ||
		snapshot.query === null ||
		snapshot.revision === null ||
		snapshot.summary === null ||
		snapshot.totalItemCount === null ||
		snapshot.totalTreeRowCount === null
	) {
		throw new Error('Bridge Review metadata display replacement requires a complete snapshot.');
	}
	return {
		baseEndpoint: snapshot.baseEndpoint,
		contentSources: snapshot.contentSources,
		eventKind: 'review.snapshot',
		extentFacts: snapshot.extentFacts,
		generation: snapshot.identity.generation,
		headEndpoint: snapshot.headEndpoint,
		itemMetadata: snapshot.itemMetadata,
		itemWindow: {
			finalWindow: true,
			itemCount: snapshot.itemMetadata.length,
			startIndex: 0,
			totalItemCount: snapshot.totalItemCount,
		},
		packageId: snapshot.identity.packageId,
		publicationId: snapshot.identity.publicationId,
		query: snapshot.query,
		revision: snapshot.revision,
		sourceIdentity: snapshot.identity.sourceIdentity,
		summary: snapshot.summary,
		treeRows: snapshot.treeRows,
		treeWindow: {
			finalWindow: true,
			rowCount: snapshot.treeRows.length,
			startIndex: 0,
			totalRowCount: snapshot.totalTreeRowCount,
		},
	};
}

export function reviewMetadataInvalidatedEventFromSnapshot(
	snapshot: BridgeCommWorkerReviewMetadataSnapshot,
): Extract<BridgeProductReviewMetadataEvent, { readonly eventKind: 'review.invalidated' }> {
	if (snapshot.identity === null || snapshot.revision === null) {
		throw new Error('Bridge Review stale display publication requires active source identity.');
	}
	return {
		eventKind: 'review.invalidated',
		generation: snapshot.identity.generation,
		itemIds: [],
		packageId: snapshot.identity.packageId,
		pathHints: [],
		publicationId: snapshot.identity.publicationId,
		reason: 'sourceChanged',
		revision: snapshot.revision,
		scope: 'package',
		sourceIdentity: snapshot.identity.sourceIdentity,
	};
}

export function reviewMetadataEventCompletesProjection(
	event: BridgeProductReviewMetadataEvent,
): boolean {
	return (
		(event.eventKind === 'review.snapshot' || event.eventKind === 'review.window') &&
		event.itemWindow.finalWindow &&
		event.treeWindow.finalWindow
	);
}

export function requiredReviewPublicationId(
	snapshot: BridgeCommWorkerReviewMetadataSnapshot,
): string {
	if (snapshot.identity === null) {
		throw new Error('Bridge Review publication receipt requires active publication identity.');
	}
	return snapshot.identity.publicationId;
}
