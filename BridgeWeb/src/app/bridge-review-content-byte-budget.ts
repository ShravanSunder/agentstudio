import { bridgeContentDemandRetentionPolicy } from '../core/demand/bridge-content-demand-policy.js';
import type { BridgeContentHandle } from '../foundation/review-package/bridge-review-package.js';

const bridgeReviewContentMaxBytesPerRole = 4 * 1024 * 1024;
const bridgeReviewContentMaxRolesPerItem = 2;

export interface BridgeReviewContentDemandByteBudget {
	readonly maxContentBytesPerRole: number;
	readonly maxContentRolesPerItem: number;
	readonly bodyRegistryMaxBytes: number;
	readonly resourceExecutorMaxInFlightBytes: number;
	readonly resourceExecutorMaxQueuedBytes: number;
	readonly demandMaxQueuedEstimatedBytes: number;
}

export interface BridgeReviewContentByteBounds {
	readonly expectedBytes?: number | undefined;
	readonly maxBytes: number;
}

export const bridgeReviewContentDemandByteBudget: BridgeReviewContentDemandByteBudget = {
	maxContentBytesPerRole: bridgeReviewContentMaxBytesPerRole,
	maxContentRolesPerItem: bridgeReviewContentMaxRolesPerItem,
	bodyRegistryMaxBytes: bridgeContentDemandRetentionPolicy.reviewBodyRegistryMaxBytes,
	resourceExecutorMaxInFlightBytes:
		bridgeReviewContentMaxBytesPerRole * bridgeReviewContentMaxRolesPerItem,
	resourceExecutorMaxQueuedBytes:
		bridgeReviewContentMaxBytesPerRole * bridgeReviewContentMaxRolesPerItem,
	demandMaxQueuedEstimatedBytes:
		bridgeReviewContentMaxBytesPerRole * bridgeReviewContentMaxRolesPerItem,
};

export function bridgeReviewContentByteBoundsForHandle(
	handle: Pick<BridgeContentHandle, 'maxBytes' | 'sizeBytes' | 'sizeBytesIsExact'>,
): BridgeReviewContentByteBounds {
	const maxBytes =
		handle.maxBytes ??
		(handle.sizeBytesIsExact === false
			? bridgeReviewContentDemandByteBudget.maxContentBytesPerRole
			: Math.max(handle.sizeBytes, 1));
	if (handle.sizeBytesIsExact === false) {
		return { maxBytes };
	}
	return {
		expectedBytes: handle.sizeBytes,
		maxBytes,
	};
}
