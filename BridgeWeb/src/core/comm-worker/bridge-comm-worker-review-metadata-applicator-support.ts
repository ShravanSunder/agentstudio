import type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-source-diff.js';
import type { BridgeProductReviewMetadataEvent } from './bridge-product-review-metadata-contracts.js';
import type { BridgeWorkerReviewCandidateStartDisposition } from './bridge-worker-contracts.js';

export type ReviewMetadataRoutedEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.delta' | 'review.invalidated' | 'review.window' }
>;
export type ReviewMetadataActiveEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.invalidated' | 'review.window' }
>;
export type ReviewMetadataPendingEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{
		readonly eventKind: 'review.delta' | 'review.invalidated' | 'review.snapshot' | 'review.window';
	}
>;

export interface MutableBridgeCommWorkerReviewRuntimeSource extends BridgeCommWorkerReviewRuntimeSource {
	readonly contentItems: BridgeCommWorkerReviewRuntimeSource['contentItems'][number][];
	readonly contentRequestDescriptors: BridgeCommWorkerReviewRuntimeSource['contentRequestDescriptors'][number][];
	readonly renderSemantics: BridgeCommWorkerReviewRuntimeSource['renderSemantics'][number][];
	reviewPublicationIdentity: BridgeCommWorkerReviewRuntimeSource['reviewPublicationIdentity'];
	readonly rows: BridgeCommWorkerReviewRuntimeSource['rows'][number][];
}

export function candidateStartDisposition(
	event: Extract<
		BridgeProductReviewMetadataEvent,
		{ readonly eventKind: 'review.delta' | 'review.reset' | 'review.sourceAccepted' }
	>,
): BridgeWorkerReviewCandidateStartDisposition {
	if (
		(event.eventKind === 'review.delta' || event.eventKind === 'review.reset') &&
		event.preDeliveryPresentationClass !== undefined &&
		event.affectedStableFileIdentities !== undefined
	)
		return {
			affectedStableFileIdentities: event.affectedStableFileIdentities,
			kind: 'sameSource',
			presentationClass: event.preDeliveryPresentationClass,
		};
	return { kind: 'replacement' };
}

export function replaceMapContents<TKey, TValue>(
	target: Map<TKey, TValue>,
	source: ReadonlyMap<TKey, TValue>,
): void {
	target.clear();
	for (const [key, value] of source) target.set(key, value);
}

export function assertNeverReviewMetadataEvent(event: never): never {
	throw new Error(`Unhandled Review metadata applicator event: ${JSON.stringify(event)}`);
}

export function emptyReviewRuntimeSource(): MutableBridgeCommWorkerReviewRuntimeSource {
	return {
		contentItems: [],
		contentRequestDescriptors: [],
		renderSemantics: [],
		reviewPublicationIdentity: null,
		rows: [],
	};
}
