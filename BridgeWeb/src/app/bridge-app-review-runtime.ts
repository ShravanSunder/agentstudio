import { useRef } from 'react';

import type { BridgeDemandLane } from '../core/models/bridge-demand-models.js';
import {
	createBridgeResourceDescriptorRegistry,
	type BridgeResourceDescriptorRegistry,
} from '../core/resources/bridge-resource-registry.js';
import {
	bridgeResourceUrlWithContentInterest,
	type BridgeContentDemandInterest,
} from '../core/resources/bridge-resource-url.js';
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

export const foregroundSelectionVisibleHydrationReleaseDelayMilliseconds = 180;
export const bridgeReviewIntakeMaxFrameBytes = 1024 * 1024;

export function useBridgeReviewViewerStore(): BridgeReviewViewerStore {
	const storeRef = useRef<BridgeReviewViewerStore | null>(null);
	if (storeRef.current === null) {
		storeRef.current = createBridgeReviewViewerStore();
	}
	return storeRef.current;
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

export function contentDemandResourceUrl(resourceUrl: string, lane: BridgeDemandLane): string {
	return bridgeResourceUrlWithContentInterest(resourceUrl, contentInterestForDemandLane(lane));
}

function contentInterestForDemandLane(lane: BridgeDemandLane): BridgeContentDemandInterest {
	switch (lane) {
		case 'foreground':
		case 'active':
			return 'selected';
		case 'visible':
			return 'visible';
		case 'nearby':
			return 'nearby';
		case 'speculative':
			return 'speculative';
		case 'idle':
			return 'background';
	}
	const exhaustiveLane: never = lane;
	return exhaustiveLane;
}
