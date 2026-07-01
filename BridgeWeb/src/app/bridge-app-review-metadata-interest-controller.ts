import type { BridgeDemandLane } from '../core/models/bridge-demand-models.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewFrameAuthority } from './bridge-app-review-frame-authority.js';
import { uniqueReviewVisibleItemIds } from './bridge-app-review-metadata-package.js';

type ReviewMetadataInterestLane = Extract<BridgeDemandLane, 'foreground' | 'visible'>;

export interface ReviewMetadataInterestIdentity {
	readonly streamId: string;
	readonly generation: number;
}

export interface ReviewMetadataInterestRequest {
	readonly protocol: 'review';
	readonly streamId: string;
	readonly generation: number;
	readonly itemIds: readonly string[];
	readonly lane: ReviewMetadataInterestLane;
}

export interface ReviewMetadataInterestIdentityViewState {
	readonly authority: BridgeReviewFrameAuthority | null;
	readonly reviewPackage: BridgeReviewPackage | null;
}

export interface ReviewMetadataInterestViewState {
	readonly identity: ReviewMetadataInterestIdentity | null;
	readonly isActive: boolean;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly visibleItemIds: readonly string[];
}

export function reviewMetadataInterestIdentityForViewState(
	props: ReviewMetadataInterestIdentityViewState,
): ReviewMetadataInterestIdentity | null {
	if (props.authority === null || props.reviewPackage === null) {
		return null;
	}
	return {
		streamId: props.authority.streamId,
		generation: props.reviewPackage.reviewGeneration,
	};
}

export function reviewMetadataInterestIdentityKey(
	identity: ReviewMetadataInterestIdentity | null,
): string | null {
	return identity === null ? null : `${identity.streamId}:${identity.generation}`;
}

export function reviewMetadataInterestRequestsForViewState(
	props: ReviewMetadataInterestViewState,
): readonly ReviewMetadataInterestRequest[] {
	if (props.identity === null) {
		return [];
	}
	if (!props.isActive || props.reviewPackage === null) {
		return clearReviewMetadataInterestRequests(props.identity);
	}
	const selectedItemIds =
		props.selectedItemId !== null && props.selectedItemId in props.reviewPackage.itemsById
			? [props.selectedItemId]
			: [];
	const visibleItemIds = uniqueKnownReviewItemIds({
		itemIds: uniqueReviewVisibleItemIds(props.visibleItemIds),
		reviewPackage: props.reviewPackage,
		excludedItemIds: selectedItemIds,
	});
	return [
		makeReviewMetadataInterestRequest({
			identity: props.identity,
			itemIds: selectedItemIds,
			lane: 'foreground',
		}),
		makeReviewMetadataInterestRequest({
			identity: props.identity,
			itemIds: visibleItemIds,
			lane: 'visible',
		}),
	];
}

function clearReviewMetadataInterestRequests(
	identity: ReviewMetadataInterestIdentity,
): readonly ReviewMetadataInterestRequest[] {
	return [
		makeReviewMetadataInterestRequest({
			identity,
			itemIds: [],
			lane: 'foreground',
		}),
		makeReviewMetadataInterestRequest({
			identity,
			itemIds: [],
			lane: 'visible',
		}),
	];
}

function makeReviewMetadataInterestRequest(props: {
	readonly identity: ReviewMetadataInterestIdentity;
	readonly itemIds: readonly string[];
	readonly lane: ReviewMetadataInterestLane;
}): ReviewMetadataInterestRequest {
	return {
		protocol: 'review',
		streamId: props.identity.streamId,
		generation: props.identity.generation,
		itemIds: props.itemIds,
		lane: props.lane,
	};
}

function uniqueKnownReviewItemIds(props: {
	readonly itemIds: readonly string[];
	readonly reviewPackage: BridgeReviewPackage;
	readonly excludedItemIds: readonly string[];
}): readonly string[] {
	const excludedItemIds = new Set(props.excludedItemIds);
	return props.itemIds.filter(
		(itemId): boolean => itemId in props.reviewPackage.itemsById && !excludedItemIds.has(itemId),
	);
}
