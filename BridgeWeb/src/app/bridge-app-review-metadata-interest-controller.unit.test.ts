import { describe, expect, test } from 'vitest';

import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import {
	reviewMetadataInterestIdentityForViewState,
	reviewMetadataInterestRequestsForViewState,
} from './bridge-app-review-metadata-interest-controller.js';
import {
	reviewMetadataInterestEffectiveVisibleItemIdsForRuntimeState,
	reviewMetadataInterestSurfaceIdentityKeyForViewState,
	reviewMetadataInterestVisibleItemIdsForSurfaceState,
} from './bridge-app-review-metadata-interest-runtime.js';

describe('Bridge review metadata interest controller', () => {
	test('builds metadata-interest identity from authority and review package', () => {
		const reviewPackage = makeReviewPackageWithItemIds(['item-a']);

		expect(
			reviewMetadataInterestIdentityForViewState({
				authority: { paneId: 'pane-1', streamId: 'review:pane-1' },
				reviewPackage,
			}),
		).toEqual({
			streamId: 'review:pane-1',
			generation: reviewPackage.reviewGeneration,
		});
		expect(
			reviewMetadataInterestIdentityForViewState({
				authority: null,
				reviewPackage,
			}),
		).toBeNull();
	});

	test('builds the merged visible metadata-interest item set from visual surfaces', () => {
		expect(
			reviewMetadataInterestVisibleItemIdsForSurfaceState({
				codeViewVisibleItemIds: ['item-b', 'item-c', 'item-a'],
				treeVisibleItemIds: ['item-a', 'item-b'],
			}),
		).toEqual(['item-a', 'item-b', 'item-c']);
	});

	test('builds surface reset identity from stream and package freshness', () => {
		const reviewPackage = {
			...makeReviewPackageWithItemIds(['item-a']),
			packageId: 'package-a',
			reviewGeneration: 7,
			revision: 11,
		};

		expect(
			reviewMetadataInterestSurfaceIdentityKeyForViewState({
				authority: { paneId: 'pane-1', streamId: 'review:pane-1' },
				reviewPackage,
			}),
		).toBe('review:pane-1:package-a:7:11');
		expect(
			reviewMetadataInterestSurfaceIdentityKeyForViewState({
				authority: null,
				reviewPackage,
			}),
		).toBeNull();
	});

	test('clears effective runtime visible item ids while inactive or after identity changes', () => {
		expect(
			reviewMetadataInterestEffectiveVisibleItemIdsForRuntimeState({
				activeSurfaceIdentityKey: 'review:pane-1:package-a:1:revision-a',
				codeViewVisibleItemIds: ['item-b'],
				isActive: true,
				surfaceIdentityKey: 'review:pane-1:package-a:1:revision-a',
				treeVisibleItemIds: ['item-a'],
			}),
		).toEqual(['item-a', 'item-b']);
		expect(
			reviewMetadataInterestEffectiveVisibleItemIdsForRuntimeState({
				activeSurfaceIdentityKey: 'review:pane-1:package-b:1:revision-b',
				codeViewVisibleItemIds: ['item-b'],
				isActive: true,
				surfaceIdentityKey: 'review:pane-1:package-a:1:revision-a',
				treeVisibleItemIds: ['item-a'],
			}),
		).toEqual([]);
		expect(
			reviewMetadataInterestEffectiveVisibleItemIdsForRuntimeState({
				activeSurfaceIdentityKey: 'review:pane-1:package-a:1:revision-a',
				codeViewVisibleItemIds: ['item-b'],
				isActive: false,
				surfaceIdentityKey: 'review:pane-1:package-a:1:revision-a',
				treeVisibleItemIds: ['item-a'],
			}),
		).toEqual([]);
	});

	test('builds foreground and visible metadata-interest requests from app-level view state', () => {
		const reviewPackage = makeReviewPackageWithItemIds(['item-a', 'item-b', 'item-c']);
		const identity = {
			streamId: 'review:pane-1',
			generation: reviewPackage.reviewGeneration,
		};

		expect(
			reviewMetadataInterestRequestsForViewState({
				identity,
				isActive: true,
				reviewPackage,
				selectedItemId: 'item-a',
				visibleItemIds: ['item-a', 'item-b', 'item-c'],
			}),
		).toEqual([
			{
				protocol: 'review',
				streamId: 'review:pane-1',
				generation: identity.generation,
				itemIds: ['item-a'],
				lane: 'foreground',
			},
			{
				protocol: 'review',
				streamId: 'review:pane-1',
				generation: identity.generation,
				itemIds: ['item-b', 'item-c'],
				lane: 'visible',
			},
		]);
	});

	test('builds explicit empty lane requests for inactive or unknown review items', () => {
		const reviewPackage = makeReviewPackageWithItemIds(['item-a', 'item-b']);
		const identity = {
			streamId: 'review:pane-1',
			generation: reviewPackage.reviewGeneration,
		};

		expect(
			reviewMetadataInterestRequestsForViewState({
				identity,
				isActive: false,
				reviewPackage,
				selectedItemId: 'missing-item',
				visibleItemIds: ['item-a', 'item-b', 'missing-item'],
			}),
		).toEqual([
			{
				protocol: 'review',
				streamId: 'review:pane-1',
				generation: identity.generation,
				itemIds: [],
				lane: 'foreground',
			},
			{
				protocol: 'review',
				streamId: 'review:pane-1',
				generation: identity.generation,
				itemIds: [],
				lane: 'visible',
			},
		]);
		expect(
			reviewMetadataInterestRequestsForViewState({
				identity,
				isActive: true,
				reviewPackage,
				selectedItemId: 'missing-item',
				visibleItemIds: ['missing-item'],
			}),
		).toEqual([
			{
				protocol: 'review',
				streamId: 'review:pane-1',
				generation: identity.generation,
				itemIds: [],
				lane: 'foreground',
			},
			{
				protocol: 'review',
				streamId: 'review:pane-1',
				generation: identity.generation,
				itemIds: [],
				lane: 'visible',
			},
		]);
	});

	test('clears both lanes when the runtime has identity but no active review package', () => {
		expect(
			reviewMetadataInterestRequestsForViewState({
				identity: { streamId: 'review:pane-1', generation: 7 },
				isActive: true,
				reviewPackage: null,
				selectedItemId: 'item-a',
				visibleItemIds: ['item-a'],
			}),
		).toEqual([
			{
				protocol: 'review',
				streamId: 'review:pane-1',
				generation: 7,
				itemIds: [],
				lane: 'foreground',
			},
			{
				protocol: 'review',
				streamId: 'review:pane-1',
				generation: 7,
				itemIds: [],
				lane: 'visible',
			},
		]);
	});
});

function makeReviewPackageWithItemIds(itemIds: readonly string[]): BridgeReviewPackage {
	const itemsById = Object.fromEntries(
		itemIds.map((itemId): readonly [string, ReturnType<typeof makeBridgeReviewItem>] => [
			itemId,
			makeBridgeReviewItem({ itemId, path: `Sources/App/${itemId}.swift` }),
		]),
	);
	return {
		...makeBridgeReviewPackage(),
		orderedItemIds: [...itemIds],
		itemsById,
	};
}
