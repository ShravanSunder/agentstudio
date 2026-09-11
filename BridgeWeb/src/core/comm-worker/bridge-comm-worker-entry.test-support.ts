import type { BridgeProductReviewContentDescriptor } from './bridge-product-content-contracts.js';
import type { BridgeProductContentStream } from './bridge-product-transport-contract.js';
import type {
	BridgeWorkerReviewDisplayPatch,
	BridgeWorkerReviewPublicationIdentity,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';

export interface MakeFetchedReviewContentResourceProps {
	readonly contentHash: string;
	readonly role: BridgeWorkerFetchedReviewContentResource['role'];
	readonly text: string;
}

export function makeReviewPublicationIdentity(revision = 1): BridgeWorkerReviewPublicationIdentity {
	return {
		packageId: `review-package-${revision}`,
		publicationId: `00000000-0000-7000-8000-${revision.toString().padStart(12, '0')}`,
		reviewGeneration: revision,
		revision,
		sourceIdentity: `review-source-${revision}`,
	};
}

export function makeFetchedReviewContentResource(
	props: MakeFetchedReviewContentResourceProps,
): BridgeWorkerFetchedReviewContentResource {
	const textBytes = new TextEncoder().encode(props.text).buffer;
	return {
		itemId: 'item-1',
		role: props.role,
		contentHash: props.contentHash,
		contentHashAlgorithm: 'fixture-preview',
		descriptorId: `descriptor-item-1-${props.role}`,
		language: 'swift',
		byteLength: textBytes.byteLength,
		observedSha256: props.role === 'base' ? 'a'.repeat(64) : 'b'.repeat(64),
		requestId: `content-request-item-1-${props.role}`,
		sourceGeneration: 7,
		sourceIdentity: 'review-source-1',
		sourcePosition: 'whole',
		text: props.text,
		textBytes,
	};
}

export function makeCompletedReviewContentStream(
	descriptor: BridgeProductReviewContentDescriptor,
): BridgeProductContentStream<'review.content'> {
	const bytes = new TextEncoder().encode(
		descriptor.role === 'base' ? 'base body' : 'head body',
	).buffer;
	return {
		contentKind: 'review.content',
		contentRequestId: `content-request-${descriptor.role}`,
		frames: emptyReviewContentFrames(),
		terminal: Promise.resolve({
			bytes,
			contentKind: 'review.content',
			descriptorId: descriptor.descriptorId,
			endOfSource: true,
			kind: 'complete',
			observedByteLength: bytes.byteLength,
			observedSha256: 'a'.repeat(64),
		}),
	};
}

async function* emptyReviewContentFrames(): AsyncIterable<never> {}

export function expectedReviewMetadataUnavailablePatch(): BridgeWorkerServerToMainMessage {
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'reviewDisplayPatch',
		reviewPublicationIdentity: null,
		patches: [
			{
				operation: 'failed',
				payload: { error: 'metadataUnavailable', status: 'failed' },
				slice: 'reviewSource',
			},
			...expectedEmptyReviewProjectionResetPatches(),
		],
		projectionRevision: 1,
		sequence: 1,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

export function expectedEmptyReviewProjectionResetPatches(): readonly BridgeWorkerReviewDisplayPatch[] {
	return [
		{
			operation: 'batch',
			payload: { items: [], operations: [], reset: true, startIndex: 0 },
			slice: 'reviewItem',
		},
		{
			operation: 'batch',
			payload: { reset: true, windows: [{ rows: [], startIndex: 0 }] },
			slice: 'reviewTree',
		},
	];
}
