import { parseBridgeResourceUrl } from '../../bridge/bridge-resource-url.js';
import { readBridgeTextResourceStream } from '../resources/bridge-resource-stream.js';
import type { BridgeWorkerFileViewContentRequestDescriptor } from './bridge-worker-contracts.js';
import { bridgeWorkerFileViewContentRequestDescriptorSchema } from './bridge-worker-contracts.js';
import type { BridgeWorkerContentFetch } from './bridge-worker-review-content-fetch.js';

export interface FetchBridgeWorkerFileViewContentResourceProps {
	readonly descriptor: BridgeWorkerFileViewContentRequestDescriptor;
	readonly fetchContent?: BridgeWorkerContentFetch;
	readonly signal?: AbortSignal;
}

export interface BridgeWorkerFetchedFileViewContentResource {
	readonly itemId: string;
	readonly path: string;
	readonly handleId: string;
	readonly descriptorId: string;
	readonly resourceKind: 'worktree.fileContent';
	readonly contentHash?: string | undefined;
	readonly contentHashAlgorithm?: string | undefined;
	readonly language: string | null;
	readonly sizeBytes: number;
	readonly maxBytes: number;
	readonly byteLength: number;
	readonly text: string;
	readonly textBytes: ArrayBuffer;
}

export async function fetchBridgeWorkerFileViewContentResource(
	props: FetchBridgeWorkerFileViewContentResourceProps,
): Promise<BridgeWorkerFetchedFileViewContentResource> {
	const descriptor = bridgeWorkerFileViewContentRequestDescriptorSchema.parse(props.descriptor);
	if (descriptor.isBinary) {
		throw new Error('Bridge worker File View content fetch cannot load binary descriptors.');
	}
	assertDescriptorResourceUrl(descriptor);
	const requestInit = props.signal === undefined ? undefined : { signal: props.signal };
	const response = await (props.fetchContent ?? fetch)(descriptor.resourceUrl, requestInit);
	if (!response.ok) {
		throw new Error(`Bridge worker File View content request failed: ${response.status}.`);
	}
	const streamedText = await readBridgeTextResourceStream(response, {
		maxBytes: descriptor.maxBytes,
		...(props.signal === undefined ? {} : { signal: props.signal }),
	});
	const text = streamedText.readText();
	const textBytes = streamedText.copyBytes();
	return {
		itemId: descriptor.itemId,
		path: descriptor.path,
		handleId: descriptor.handleId,
		descriptorId: descriptor.descriptorId,
		resourceKind: 'worktree.fileContent',
		...(descriptor.contentHash === undefined ? {} : { contentHash: descriptor.contentHash }),
		...(descriptor.contentHashAlgorithm === undefined
			? {}
			: { contentHashAlgorithm: descriptor.contentHashAlgorithm }),
		language: descriptor.language,
		sizeBytes: descriptor.sizeBytes,
		maxBytes: descriptor.maxBytes,
		byteLength: streamedText.byteLength,
		text,
		textBytes,
	};
}

function assertDescriptorResourceUrl(
	descriptor: BridgeWorkerFileViewContentRequestDescriptor,
): void {
	const parsedResourceUrl = parseBridgeResourceUrl(descriptor.resourceUrl);
	if (
		parsedResourceUrl?.kind !== 'worktreeResource' ||
		parsedResourceUrl.resourceKind !== 'worktree.fileContent' ||
		descriptor.resourceKind !== 'worktree.fileContent' ||
		parsedResourceUrl.resourceId !== descriptor.descriptorId ||
		parsedResourceUrl.canonicalUrl !== descriptor.resourceUrl
	) {
		throw new Error('Bridge worker File View content descriptor resource URL is invalid.');
	}
}
