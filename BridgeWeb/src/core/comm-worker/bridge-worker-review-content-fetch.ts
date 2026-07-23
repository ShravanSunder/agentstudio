import type { BridgeBodyRegistry } from '../demand/bridge-body-registry.js';
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
		signal?: AbortSignal,
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

export type BridgeWorkerResidentReviewContentBody = Pick<
	BridgeWorkerFetchedReviewContentResource,
	'byteLength' | 'observedSha256' | 'sourcePosition' | 'text' | 'textBytes'
>;

export class BridgeWorkerReviewContentRetryWaitError extends Error {}

export function createSharedBridgeWorkerReviewContentResourceFetch(props: {
	readonly bodyRegistry?: BridgeBodyRegistry<BridgeWorkerResidentReviewContentBody>;
	readonly openContent: BridgeWorkerReviewContentOpen | undefined;
	readonly resolveBodyRegistry?: () =>
		| BridgeBodyRegistry<BridgeWorkerResidentReviewContentBody>
		| undefined;
}): BridgeWorkerReviewContentResourceFetch {
	interface InFlightReviewContentResource {
		readonly promise: ReturnType<BridgeWorkerReviewContentResourceFetch>;
		readonly sourceSignal: AbortSignal | undefined;
	}
	const inFlightResourcesByIdentity = new Map<string, InFlightReviewContentResource>();
	return async (descriptor: BridgeWorkerReviewContentRequestDescriptor, signal?: AbortSignal) => {
		signal?.throwIfAborted();
		const bodyRegistry = props.bodyRegistry ?? props.resolveBodyRegistry?.();
		const residentCacheKey = residentBridgeWorkerReviewContentResourceCacheKey(descriptor);
		const residentFreshnessKey = residentBridgeWorkerReviewContentResourceFreshnessKey(descriptor);
		const residentResource = bodyRegistry?.get({
			cacheKey: residentCacheKey,
			freshnessKey: residentFreshnessKey,
		});
		if (residentResource !== null && residentResource !== undefined) {
			return fetchedBridgeWorkerReviewContentResourceFromResidentBody({
				body: residentResource,
				descriptor,
			});
		}
		const resourceKey = sharedBridgeWorkerReviewContentResourceKey(descriptor);
		const existingResource = inFlightResourcesByIdentity.get(resourceKey);
		if (existingResource !== undefined && existingResource.sourceSignal?.aborted !== true) {
			return await existingResource.promise;
		}
		if (existingResource !== undefined) {
			inFlightResourcesByIdentity.delete(resourceKey);
		}
		if (props.openContent === undefined) {
			throw new Error('Bridge worker Review content requires the shared product transport.');
		}
		const resourcePromise = fetchBridgeWorkerReviewContentResource({
			descriptor,
			openContent: props.openContent,
			...(signal === undefined ? {} : { signal }),
		});
		const resourceEntry: InFlightReviewContentResource = {
			promise: resourcePromise,
			sourceSignal: signal,
		};
		const evictAbortedResource = (): void => {
			if (inFlightResourcesByIdentity.get(resourceKey) === resourceEntry) {
				inFlightResourcesByIdentity.delete(resourceKey);
			}
		};
		signal?.addEventListener('abort', evictAbortedResource, { once: true });
		inFlightResourcesByIdentity.set(resourceKey, resourceEntry);
		try {
			const resource = await resourcePromise;
			signal?.throwIfAborted();
			bodyRegistry?.evictStale({
				cacheKey: residentCacheKey,
				keepFreshnessKey: residentFreshnessKey,
			});
			bodyRegistry?.put({
				body: {
					byteLength: resource.byteLength,
					observedSha256: resource.observedSha256,
					sourcePosition: resource.sourcePosition,
					text: resource.text,
					textBytes: resource.textBytes,
				},
				byteLength: resource.byteLength,
				cacheKey: residentCacheKey,
				freshnessKey: residentFreshnessKey,
			});
			return resource;
		} finally {
			signal?.removeEventListener('abort', evictAbortedResource);
			evictAbortedResource();
		}
	};
}

function fetchedBridgeWorkerReviewContentResourceFromResidentBody(props: {
	readonly body: BridgeWorkerResidentReviewContentBody;
	readonly descriptor: BridgeWorkerReviewContentRequestDescriptor;
}): BridgeWorkerFetchedReviewContentResource {
	return {
		...props.body,
		contentHash: props.descriptor.contentDigest.value,
		contentHashAlgorithm: props.descriptor.contentDigest.algorithm,
		descriptorId: props.descriptor.descriptorId,
		itemId: props.descriptor.itemId,
		language: props.descriptor.language,
		requestId: `resident-${props.descriptor.descriptorId}`,
		role: props.descriptor.role,
		sourceGeneration: props.descriptor.reviewGeneration,
		sourceIdentity: props.descriptor.sourceIdentity,
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
		if (terminal.retryable) {
			throw new BridgeWorkerReviewContentRetryWaitError(
				terminal.safeMessage ?? `Bridge worker Review content failed: ${terminal.code}.`,
			);
		}
		throw new Error(
			terminal.safeMessage ?? `Bridge worker Review content failed: ${terminal.code}.`,
		);
	}
	if (terminal.kind === 'reset') {
		throw new BridgeWorkerReviewContentRetryWaitError(
			`Bridge worker Review content reset: ${terminal.reason}.`,
		);
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
		residentBridgeWorkerReviewContentResourceCacheKey(descriptor),
		residentBridgeWorkerReviewContentResourceFreshnessKey(descriptor),
		descriptor.descriptorId,
		descriptor.endpointId,
		descriptor.handleId,
		descriptor.expectedSha256 ?? '',
		descriptor.language ?? '',
		descriptor.maximumBytes,
		descriptor.mimeType,
	].join('\u0000');
}

function residentBridgeWorkerReviewContentResourceCacheKey(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
): string {
	return [
		descriptor.packageId,
		descriptor.sourceIdentity,
		descriptor.reviewGeneration,
		descriptor.itemId,
		descriptor.role,
		descriptor.window.kind,
		descriptor.window.startByte,
		descriptor.window.maximumBytes,
	].join('\u0000');
}

function residentBridgeWorkerReviewContentResourceFreshnessKey(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
): string {
	return [
		descriptor.contentDigest.algorithm,
		descriptor.contentDigest.authority,
		descriptor.contentDigest.value,
		descriptor.declaredByteLength ?? '',
		descriptor.wholeByteLength ?? '',
		descriptor.encoding,
		descriptor.isBinary,
	].join('\u0000');
}
