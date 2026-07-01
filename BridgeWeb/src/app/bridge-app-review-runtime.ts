import { useRef } from 'react';

import { createBridgeBodyRegistry } from '../core/demand/bridge-body-registry.js';
import {
	createBridgeDemandScheduler,
	type BridgeDemandScheduler,
} from '../core/demand/bridge-demand-scheduler.js';
import {
	createBridgeResourceExecutor,
	type BridgeResourceExecutor,
} from '../core/demand/bridge-resource-executor.js';
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import {
	createBridgeResourceDescriptorRegistry,
	type BridgeResourceDescriptorRegistry,
} from '../core/resources/bridge-resource-registry.js';
import {
	bridgeTextResourceLoadErrorKind,
	readBridgeTextResourceStream,
	type BridgeTextResourceStreamResult,
} from '../core/resources/bridge-resource-stream.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';
import type { BridgeCodeViewContentResources } from '../review-viewer/code-view/bridge-code-view-materialization.js';
import { demandFreshnessKeyForReviewDescriptorRef } from '../review-viewer/content/review-content-demand-loader.js';
import {
	createBridgeReviewContentRegistry,
	type BridgeReviewContentRegistry,
} from '../review-viewer/content/review-content-registry.js';
import {
	createBridgeReviewViewerStore,
	type BridgeReviewViewerStore,
} from '../review-viewer/state/review-viewer-store.js';
import { bridgeReviewAllowedResourceKindsByProtocol } from './bridge-app-review-descriptors.js';

const bridgeReviewContentMaxBytesPerRole = 50 * 1024 * 1024;
const bridgeReviewContentMaxRolesPerItem = 2;

export interface BridgeReviewContentDemandByteBudget {
	readonly maxContentBytesPerRole: number;
	readonly maxContentRolesPerItem: number;
	readonly bodyRegistryMaxBytes: number;
	readonly resourceExecutorMaxInFlightBytes: number;
	readonly resourceExecutorMaxQueuedBytes: number;
	readonly demandMaxQueuedEstimatedBytes: number;
}

export const bridgeReviewContentDemandByteBudget: BridgeReviewContentDemandByteBudget = {
	maxContentBytesPerRole: bridgeReviewContentMaxBytesPerRole,
	maxContentRolesPerItem: bridgeReviewContentMaxRolesPerItem,
	bodyRegistryMaxBytes: bridgeReviewContentMaxBytesPerRole,
	resourceExecutorMaxInFlightBytes:
		bridgeReviewContentMaxBytesPerRole * bridgeReviewContentMaxRolesPerItem,
	resourceExecutorMaxQueuedBytes:
		bridgeReviewContentMaxBytesPerRole * bridgeReviewContentMaxRolesPerItem,
	demandMaxQueuedEstimatedBytes:
		bridgeReviewContentMaxBytesPerRole * bridgeReviewContentMaxRolesPerItem,
};

const bridgeReviewBodyRegistryMaxBytes = bridgeReviewContentDemandByteBudget.bodyRegistryMaxBytes;
const bridgeReviewResourceExecutorMaxConcurrentLoads = 8;
const bridgeReviewResourceExecutorMaxInFlightBytes =
	bridgeReviewContentDemandByteBudget.resourceExecutorMaxInFlightBytes;
const bridgeReviewResourceExecutorMaxQueuedLoads = 128;
const bridgeReviewResourceExecutorMaxQueuedBytes =
	bridgeReviewContentDemandByteBudget.resourceExecutorMaxQueuedBytes;
export const foregroundSelectionVisibleHydrationReleaseDelayMilliseconds = 180;
const bridgeReviewDemandMaxQueuedIntentsPerLane = 128;
const bridgeReviewDemandMaxQueuedEstimatedBytes =
	bridgeReviewContentDemandByteBudget.demandMaxQueuedEstimatedBytes;
export const bridgeReviewIntakeMaxFrameBytes = 1024 * 1024;
export const emptyVisibleContentResourcesByItemId: ReadonlyMap<
	string,
	BridgeCodeViewContentResources
> = new Map<string, BridgeCodeViewContentResources>();
export const emptyVisibleLoadingItemIds: ReadonlySet<string> = new Set<string>();
export function useBridgeReviewViewerStore(): BridgeReviewViewerStore {
	const storeRef = useRef<BridgeReviewViewerStore | null>(null);
	if (storeRef.current === null) {
		storeRef.current = createBridgeReviewViewerStore();
	}
	return storeRef.current;
}

export function useBridgeReviewContentRegistry(): BridgeReviewContentRegistry {
	const registryRef = useRef<BridgeReviewContentRegistry | null>(null);
	if (registryRef.current === null) {
		registryRef.current = createBridgeReviewContentRegistry();
	}
	return registryRef.current;
}

export function useBridgeResourceDescriptorRegistry(): BridgeResourceDescriptorRegistry {
	const registryRef = useRef<BridgeResourceDescriptorRegistry | null>(null);
	if (registryRef.current === null) {
		registryRef.current = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: bridgeReviewAllowedResourceKindsByProtocol,
		});
	}
	return registryRef.current;
}

type BridgeReviewResourceExecutorCachedText = BridgeTextResourceStreamResult;

interface UseBridgeReviewResourceExecutorProps {
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly descriptorRefsByDescriptorIdRef: {
		readonly current: ReadonlyMap<string, BridgeDescriptorRef>;
	};
	readonly fetchContentRef: { readonly current: BridgeContentFetch | undefined };
	readonly invalidatedFreshnessKeysRef: { readonly current: Set<string> };
}

export function useBridgeReviewResourceExecutor(
	props: UseBridgeReviewResourceExecutorProps,
): BridgeResourceExecutor<BridgeTextResourceStreamResult> {
	const bodyRegistryRef = useRef(
		createBridgeBodyRegistry<BridgeReviewResourceExecutorCachedText>({
			maxBytes: bridgeReviewBodyRegistryMaxBytes,
		}),
	);
	const executorRef = useRef<BridgeResourceExecutor<BridgeTextResourceStreamResult> | null>(null);
	if (executorRef.current === null) {
		executorRef.current = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry: props.descriptorRegistry,
			maxConcurrentLoads: bridgeReviewResourceExecutorMaxConcurrentLoads,
			maxInFlightBytes: bridgeReviewResourceExecutorMaxInFlightBytes,
			maxQueuedLoads: bridgeReviewResourceExecutorMaxQueuedLoads,
			maxQueuedBytes: bridgeReviewResourceExecutorMaxQueuedBytes,
			classifyLoadFailure: bridgeTextResourceLoadErrorKind,
			isFresh: (intent): boolean => {
				if (isReviewProtocolBodyDescriptorRef(intent.descriptorRef)) {
					return (
						props.descriptorRegistry.lookup(intent.descriptorRef) !== null &&
						demandFreshnessKeyForReviewDescriptorRef(intent.descriptorRef) === intent.freshnessKey
					);
				}
				const currentDescriptorRef = props.descriptorRefsByDescriptorIdRef.current.get(
					intent.descriptorRef.descriptorId,
				);
				return (
					currentDescriptorRef !== undefined &&
					demandFreshnessKeyForReviewDescriptorRef(currentDescriptorRef) === intent.freshnessKey
				);
			},
			loadResource: async ({ descriptor, intent, onChunk, signal }) => {
				const cacheKey = descriptor.resourceUrl;
				const shouldBypassCachedBody = props.invalidatedFreshnessKeysRef.current.has(
					intent.freshnessKey,
				);
				const cachedBody = shouldBypassCachedBody
					? null
					: bodyRegistryRef.current.get({
							cacheKey,
							freshnessKey: intent.freshnessKey,
						});
				if (cachedBody !== null) {
					return {
						authoritative: cachedBody.authoritative,
						content: cachedBody,
						byteLength: cachedBody.byteLength,
					};
				}
				const fetchContent = props.fetchContentRef.current ?? fetch;
				const response = await fetchContent(descriptor.resourceUrl, { signal });
				if (!response.ok) {
					throw new Error(`Bridge descriptor content request failed: ${response.status}`);
				}
				const streamedText = await readBridgeTextResourceStream(response, {
					integrity: descriptor.content.integrity,
					maxBytes: descriptor.content.maxBytes,
					onTextChunk: (chunk): void => {
						onChunk({
							byteLength: chunk.byteLength,
							chunk: chunk.text,
							totalBytesRead: chunk.totalBytesRead,
						});
					},
					signal,
				});
				const byteLength = streamedText.byteLength;
				if (streamedText.authoritative) {
					bodyRegistryRef.current.put({
						cacheKey,
						freshnessKey: intent.freshnessKey,
						body: streamedText,
						byteLength,
					});
				}
				if (shouldBypassCachedBody) {
					props.invalidatedFreshnessKeysRef.current.delete(intent.freshnessKey);
				}
				return { authoritative: streamedText.authoritative, content: streamedText, byteLength };
			},
		});
	}
	return executorRef.current;
}

function isReviewProtocolBodyDescriptorRef(descriptorRef: BridgeDescriptorRef): boolean {
	return (
		descriptorRef.expectedProtocol === 'review' && descriptorRef.expectedResourceKind !== 'content'
	);
}

export function createBridgeReviewDemandScheduler(): BridgeDemandScheduler {
	return createBridgeDemandScheduler({
		maxQueuedIntentsPerLane: bridgeReviewDemandMaxQueuedIntentsPerLane,
		maxQueuedEstimatedBytes: bridgeReviewDemandMaxQueuedEstimatedBytes,
	});
}
