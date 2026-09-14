import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductMetadataApplicationProtocolIdentity } from './bridge-product-metadata-application-protocol.js';
import type { BridgeProductContentStream } from './bridge-product-transport-contract.js';
import type { BridgeWorkerReviewContentRequestDescriptor } from './bridge-worker-contracts.js';

export function createIdleWorktreeAnnotationSubscription(
	protocol: BridgeProductMetadataApplicationProtocolIdentity,
): {
	readonly events: AsyncIterable<never>;
	readonly subscriptionId: string;
	readonly subscriptionKind: string;
	cancel(): Promise<void>;
	update(): Promise<void>;
} {
	const events = new BridgeProductBoundedAsyncQueue<never>(1);
	return {
		cancel: async (): Promise<void> => {
			events.close(true);
		},
		events,
		subscriptionId: `${protocol.kind}-idle-test-subscription`,
		subscriptionKind: protocol.kind,
		update: async (): Promise<void> => {},
	};
}

export function makeImmediateReviewContentStream(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
	text: string,
): BridgeProductContentStream<'review.content'> {
	return {
		contentKind: 'review.content',
		contentRequestId: `content-request-${descriptor.descriptorId}`,
		frames: emptyReviewContentFrames(),
		terminal: Promise.resolve(completedReviewContentTerminal(descriptor, text)),
	};
}

export function completedReviewContentTerminal(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
	text: string,
): Awaited<BridgeProductContentStream<'review.content'>['terminal']> {
	const bytes = new TextEncoder().encode(text);
	return {
		bytes: bytes.buffer,
		contentKind: 'review.content',
		descriptorId: descriptor.descriptorId,
		endOfSource: true,
		kind: 'complete',
		observedByteLength: bytes.byteLength,
		observedSha256: 'a'.repeat(64),
	};
}

export async function* emptyReviewContentFrames(): AsyncIterable<never> {}
