import { describe, expect, test } from 'vitest';

import { applyBridgeReviewDelta } from './bridge-review-delta.js';
import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from './bridge-review-package-test-support.js';

describe('bridge review delta', () => {
	test('applies item add update and removal for matching package generation', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const addedItem = makeBridgeReviewItem({ itemId: 'item-added', path: 'Sources/App/New.swift' });
		const nextPackage = applyBridgeReviewDelta(reviewPackage, {
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: 2,
			operations: {
				addItems: [addedItem],
				updateItems: [],
				removeItems: ['item-source'],
				moveItems: [],
				updateGroups: [],
				updateSummary: null,
				invalidateContent: [],
			},
		});

		expect(nextPackage.orderedItemIds).toEqual(['item-added']);
		expect(nextPackage.itemsById['item-source']).toBeUndefined();
		expect(nextPackage.itemsById['item-added']).toEqual(addedItem);
	});
});
