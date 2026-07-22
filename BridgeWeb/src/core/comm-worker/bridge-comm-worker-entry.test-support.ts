import type { BridgeWorkerServerToMainMessage } from './bridge-worker-contracts.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';

export interface MakeFetchedReviewContentResourceProps {
	readonly contentHash: string;
	readonly role: BridgeWorkerFetchedReviewContentResource['role'];
	readonly text: string;
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

export function expectedReviewMetadataUnavailablePatch(): BridgeWorkerServerToMainMessage {
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'failed',
				payload: { error: 'metadataUnavailable', status: 'failed' },
				slice: 'reviewSource',
			},
		],
		projectionRevision: 1,
		sequence: 2,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

export function expectedReviewPanelChromeReset(): BridgeWorkerServerToMainMessage {
	return {
		direction: 'serverWorkerToMain',
		kind: 'reviewRenderPatch',
		patches: [{ operation: 'reset', slice: 'panelChrome' }],
		publicationSequence: 1,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
		workerDerivationEpoch: 1,
	};
}
