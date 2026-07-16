import type { BridgeProductContentStream } from './bridge-product-transport-contract.js';
import type { BridgeWorkerReviewContentRequestDescriptor } from './bridge-worker-contracts.js';
import { bridgeWorkerReviewContentRequestDescriptorSchema } from './bridge-worker-contracts.js';

export type BridgeWorkerReviewContentOpen = (
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
	abortSignal: AbortSignal,
) => BridgeProductContentStream<'review.content'>;

export interface BridgeWorkerReviewContentResourceFetch {
	(
		descriptor: BridgeWorkerReviewContentRequestDescriptor,
	): Promise<BridgeWorkerFetchedReviewContentResource>;
}

export interface FetchBridgeWorkerReviewContentResourceProps {
	readonly descriptor: BridgeWorkerReviewContentRequestDescriptor;
	readonly openContent: BridgeWorkerReviewContentOpen;
	readonly signal?: AbortSignal;
}

export interface BridgeWorkerFetchedReviewContentResource {
	readonly itemId: string;
	readonly role: BridgeWorkerReviewContentRequestDescriptor['role'];
	readonly contentHash: string;
	readonly contentHashAlgorithm: string;
	readonly descriptorId: string;
	readonly language: string | null;
	readonly byteLength: number;
	readonly observedSha256: string;
	readonly requestId: string;
	readonly sourceGeneration: number;
	readonly sourceIdentity: string;
	readonly sourcePosition: string;
	readonly text: string;
	readonly textBytes: ArrayBuffer;
}

export function createSharedBridgeWorkerReviewContentResourceFetch(props: {
	readonly openContent: BridgeWorkerReviewContentOpen | undefined;
}): BridgeWorkerReviewContentResourceFetch {
	const inFlightResourcesByIdentity = new Map<
		string,
		ReturnType<BridgeWorkerReviewContentResourceFetch>
	>();
	return async (descriptor: BridgeWorkerReviewContentRequestDescriptor) => {
		const resourceKey = sharedBridgeWorkerReviewContentResourceKey(descriptor);
		const existingResource = inFlightResourcesByIdentity.get(resourceKey);
		if (existingResource !== undefined) {
			return await existingResource;
		}
		if (props.openContent === undefined) {
			throw new Error('Bridge worker Review content requires the shared product transport.');
		}
		const resourcePromise = fetchBridgeWorkerReviewContentResource({
			descriptor,
			openContent: props.openContent,
		});
		inFlightResourcesByIdentity.set(resourceKey, resourcePromise);
		try {
			return await resourcePromise;
		} finally {
			inFlightResourcesByIdentity.delete(resourceKey);
		}
	};
}

export async function fetchBridgeWorkerReviewContentResource(
	props: FetchBridgeWorkerReviewContentResourceProps,
): Promise<BridgeWorkerFetchedReviewContentResource> {
	const descriptor = bridgeWorkerReviewContentRequestDescriptorSchema.parse(props.descriptor);
	if (descriptor.isBinary) {
		throw new Error('Bridge worker review content fetch cannot load binary descriptors.');
	}
	const abortSignal = props.signal ?? new AbortController().signal;
	const contentStream = props.openContent(descriptor, abortSignal);
	const [, terminal] = await Promise.all([
		drainBridgeProductReviewContentFrames(contentStream),
		contentStream.terminal,
	]);
	if (terminal.kind === 'error') {
		throw new Error(
			terminal.safeMessage ?? `Bridge worker Review content failed: ${terminal.code}.`,
		);
	}
	if (terminal.kind === 'reset') {
		throw new Error(`Bridge worker Review content reset: ${terminal.reason}.`);
	}
	if (terminal.descriptorId !== descriptor.descriptorId) {
		throw new Error('Bridge worker Review content terminal descriptor does not match demand.');
	}
	const text = new TextDecoder('utf-8', { fatal: true }).decode(terminal.bytes);
	return {
		itemId: descriptor.itemId,
		role: descriptor.role,
		contentHash: descriptor.contentDigest.value,
		contentHashAlgorithm: descriptor.contentDigest.algorithm,
		descriptorId: descriptor.descriptorId,
		language: descriptor.language,
		byteLength: terminal.bytes.byteLength,
		observedSha256: terminal.observedSha256,
		requestId: contentStream.contentRequestId,
		sourceGeneration: descriptor.reviewGeneration,
		sourceIdentity: descriptor.sourceIdentity,
		sourcePosition:
			terminal.endOfSource && descriptor.window.startByte === 0
				? 'whole'
				: `byteRange:${descriptor.window.startByte}:${terminal.bytes.byteLength}`,
		text,
		textBytes: terminal.bytes,
	};
}

async function drainBridgeProductReviewContentFrames(
	contentStream: BridgeProductContentStream<'review.content'>,
): Promise<void> {
	for await (const frame of contentStream.frames) {
		// The shared transport validates and assembles ordered content into its terminal result.
		void frame;
	}
}

function sharedBridgeWorkerReviewContentResourceKey(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
): string {
	return [
		descriptor.packageId,
		descriptor.sourceIdentity,
		descriptor.descriptorId,
		descriptor.handleId,
		descriptor.itemId,
		descriptor.role,
		descriptor.contentDigest.algorithm,
		descriptor.contentDigest.authority,
		descriptor.contentDigest.value,
		descriptor.language ?? '',
		descriptor.wholeByteLength ?? '',
		descriptor.declaredByteLength ?? '',
		descriptor.maximumBytes,
		descriptor.window.startByte,
	].join('\u0000');
}
