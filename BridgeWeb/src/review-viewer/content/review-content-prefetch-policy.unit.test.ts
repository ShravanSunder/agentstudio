import { describe, expect, test } from 'vitest';

import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import {
	reviewContentPrefetchCandidateItemIds,
	shouldRunReviewContentPrefetch,
} from './review-content-prefetch-policy.js';
import { canonicalContentResourceKey } from './review-content-registry.js';

function makeMultiItemPackage(itemIds: readonly string[]): BridgeReviewPackage {
	const basePackage = makeBridgeReviewPackage();
	const itemsById: Record<string, BridgeReviewItemDescriptor> = {};
	for (const itemId of itemIds) {
		itemsById[itemId] = makeBridgeReviewItem({
			itemId,
			path: `Sources/App/${itemId}.swift`,
		});
	}
	return {
		...basePackage,
		orderedItemIds: [...itemIds],
		itemsById,
	};
}

describe('review content prefetch candidate ordering', () => {
	test('rings outward from the selected item in review order', () => {
		const reviewPackage = makeMultiItemPackage(['a', 'b', 'c', 'd', 'e']);

		const candidateItemIds = reviewContentPrefetchCandidateItemIds({
			reviewPackage,
			selectedItemId: 'c',
			cachedResourceKeys: new Set<string>(),
			excludedItemIds: new Set<string>(),
		});

		expect(candidateItemIds).toEqual(['d', 'b', 'e', 'a']);
	});

	test('falls back to review order from the start without a selection', () => {
		const reviewPackage = makeMultiItemPackage(['a', 'b', 'c']);

		const candidateItemIds = reviewContentPrefetchCandidateItemIds({
			reviewPackage,
			selectedItemId: null,
			cachedResourceKeys: new Set<string>(),
			excludedItemIds: new Set<string>(),
		});

		expect(candidateItemIds).toEqual(['a', 'b', 'c']);
	});

	test('skips items whose content roles are fully cached', () => {
		const reviewPackage = makeMultiItemPackage(['a', 'b', 'c']);
		const cachedItem = reviewPackage.itemsById['b'];
		if (cachedItem === undefined) {
			throw new Error('expected item b in fixture');
		}
		const cachedResourceKeys = new Set<string>();
		for (const handle of Object.values(cachedItem.contentRoles)) {
			if (handle !== null && handle !== undefined) {
				cachedResourceKeys.add(canonicalContentResourceKey(handle));
			}
		}

		const candidateItemIds = reviewContentPrefetchCandidateItemIds({
			reviewPackage,
			selectedItemId: 'a',
			cachedResourceKeys,
			excludedItemIds: new Set<string>(),
		});

		expect(candidateItemIds).toEqual(['c']);
	});

	test('skips excluded items and the selected item itself', () => {
		const reviewPackage = makeMultiItemPackage(['a', 'b', 'c', 'd']);

		const candidateItemIds = reviewContentPrefetchCandidateItemIds({
			reviewPackage,
			selectedItemId: 'b',
			cachedResourceKeys: new Set<string>(),
			excludedItemIds: new Set(['c']),
		});

		expect(candidateItemIds).toEqual(['a', 'd']);
	});

	test('caps candidates at maxItems', () => {
		const reviewPackage = makeMultiItemPackage(['a', 'b', 'c', 'd', 'e', 'f']);

		const candidateItemIds = reviewContentPrefetchCandidateItemIds({
			reviewPackage,
			selectedItemId: 'a',
			cachedResourceKeys: new Set<string>(),
			excludedItemIds: new Set<string>(),
			maxItems: 2,
		});

		expect(candidateItemIds).toEqual(['b', 'c']);
	});
});

describe('review content prefetch gate', () => {
	const openGateProps = {
		isActive: true,
		isCodeViewScrollActive: false,
		reviewPackage: makeBridgeReviewPackage(),
		selectedContentLoading: false,
		visibleLoadingItemCount: 0,
	};

	test('runs only when the surface is idle with a package present', () => {
		expect(shouldRunReviewContentPrefetch(openGateProps)).toBe(true);
		expect(shouldRunReviewContentPrefetch({ ...openGateProps, isActive: false })).toBe(false);
		expect(shouldRunReviewContentPrefetch({ ...openGateProps, isCodeViewScrollActive: true })).toBe(
			false,
		);
		expect(shouldRunReviewContentPrefetch({ ...openGateProps, reviewPackage: null })).toBe(false);
		expect(shouldRunReviewContentPrefetch({ ...openGateProps, selectedContentLoading: true })).toBe(
			false,
		);
		expect(shouldRunReviewContentPrefetch({ ...openGateProps, visibleLoadingItemCount: 3 })).toBe(
			false,
		);
	});
});
