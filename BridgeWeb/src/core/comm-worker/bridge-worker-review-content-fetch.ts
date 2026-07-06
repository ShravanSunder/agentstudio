import { parseBridgeContentResourceUrl } from '../../bridge/bridge-resource-url.js';
import { readBridgeTextResourceStream } from '../resources/bridge-resource-stream.js';
import type { BridgeWorkerReviewContentRequestDescriptor } from './bridge-worker-contracts.js';
import { bridgeWorkerReviewContentRequestDescriptorSchema } from './bridge-worker-contracts.js';

export interface FetchBridgeWorkerReviewContentResourceProps {
	readonly descriptor: BridgeWorkerReviewContentRequestDescriptor;
	readonly fetchContent?: BridgeWorkerContentFetch;
	readonly signal?: AbortSignal;
}

export interface BridgeWorkerFetchedReviewContentResource {
	readonly itemId: string;
	readonly role: BridgeWorkerReviewContentRequestDescriptor['role'];
	readonly contentHash: string;
	readonly contentHashAlgorithm: string;
	readonly language: string | null;
	readonly byteLength: number;
	readonly text: string;
	readonly textBytes: ArrayBuffer;
}

export interface BridgeWorkerContentFetch {
	(url: string, init?: RequestInit): Promise<Response>;
}

export async function fetchBridgeWorkerReviewContentResource(
	props: FetchBridgeWorkerReviewContentResourceProps,
): Promise<BridgeWorkerFetchedReviewContentResource> {
	const descriptor = bridgeWorkerReviewContentRequestDescriptorSchema.parse(props.descriptor);
	if (descriptor.isBinary) {
		throw new Error('Bridge worker review content fetch cannot load binary descriptors.');
	}
	assertDescriptorResourceUrl(descriptor);
	const requestInit = props.signal === undefined ? undefined : { signal: props.signal };
	const response = await (props.fetchContent ?? fetch)(descriptor.resourceUrl, requestInit);
	if (!response.ok) {
		throw new Error(`Bridge worker review content request failed: ${response.status}.`);
	}
	const streamedText = await readBridgeTextResourceStream(response, {
		maxBytes: descriptor.sizeBytes,
		...(props.signal === undefined ? {} : { signal: props.signal }),
	});
	const text = streamedText.readText();
	const textBytes = new TextEncoder().encode(text);
	return {
		itemId: descriptor.itemId,
		role: descriptor.role,
		contentHash: descriptor.contentHash,
		contentHashAlgorithm: descriptor.contentHashAlgorithm,
		language: descriptor.language,
		byteLength: textBytes.byteLength,
		text,
		textBytes: textBytes.buffer,
	};
}

function assertDescriptorResourceUrl(descriptor: BridgeWorkerReviewContentRequestDescriptor): void {
	const parsedResourceUrl = parseBridgeContentResourceUrl(descriptor.resourceUrl);
	if (
		parsedResourceUrl === null ||
		parsedResourceUrl.handleId !== descriptor.handleId ||
		parsedResourceUrl.generation !== descriptor.reviewGeneration
	) {
		throw new Error('Bridge worker review content descriptor resource URL is invalid.');
	}
}
