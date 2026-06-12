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
			revision: reviewPackage.revision + 1,
			operations: {
				addItems: [addedItem],
				updateItems: [],
				removeItems: ['item-source'],
				moveItems: [],
				updateGroups: null,
				updateSummary: null,
				invalidateContent: [],
			},
		});

		expect(nextPackage.orderedItemIds).toEqual(['item-added']);
		expect(nextPackage.revision).toBe(2);
		expect(nextPackage.itemsById['item-source']).toBeUndefined();
		expect(nextPackage.itemsById['item-added']).toEqual(addedItem);
	});

	test('applies reorder-only deltas with the full next package order', () => {
		const sourceItem = makeBridgeReviewItem({
			itemId: 'item-source',
			path: 'Sources/App/View.swift',
		});
		const testItem = makeBridgeReviewItem({
			itemId: 'item-test',
			path: 'Tests/App/ViewTests.swift',
		});
		const reviewPackage = {
			...makeBridgeReviewPackage(),
			orderedItemIds: ['item-source', 'item-test'],
			itemsById: {
				'item-source': sourceItem,
				'item-test': testItem,
			},
		};

		const nextPackage = applyBridgeReviewDelta(reviewPackage, {
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision + 1,
			operations: {
				addItems: [],
				updateItems: [],
				removeItems: [],
				moveItems: ['item-test', 'item-source'],
				updateGroups: null,
				updateSummary: null,
				invalidateContent: [],
			},
		});

		expect(nextPackage.orderedItemIds).toEqual(['item-test', 'item-source']);
	});

	test('does not use linear ordered item membership when appending added items', () => {
		const reviewPackage = {
			...makeBridgeReviewPackage(),
			orderedItemIds: new LinearMembershipGuardedArray('item-source'),
		};
		const addedItem = makeBridgeReviewItem({
			itemId: 'item-added',
			path: 'Sources/App/New.swift',
		});

		const nextPackage = applyBridgeReviewDelta(reviewPackage, {
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision + 1,
			operations: {
				addItems: [addedItem],
				updateItems: [],
				removeItems: [],
				moveItems: [],
				updateGroups: null,
				updateSummary: null,
				invalidateContent: [],
			},
		});

		expect(nextPackage.orderedItemIds).toEqual(['item-source', 'item-added']);
	});

	test('distinguishes unchanged groups from an intentional empty group update', () => {
		const reviewPackage = {
			...makeBridgeReviewPackage(),
			groups: [
				{
					groupId: 'group-source',
					grouping: { kind: 'folder' as const, label: 'Sources' },
					label: 'Sources',
					orderedItemIds: ['item-source'],
					summary: { filesChanged: 1, additions: 1, deletions: 1 },
					hiddenSummary: {
						hiddenFileCount: 0,
						hiddenAdditions: 0,
						hiddenDeletions: 0,
						hiddenFileClasses: [],
					},
				},
			],
		};

		const nextPackage = applyBridgeReviewDelta(reviewPackage, {
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision + 1,
			operations: {
				addItems: [],
				updateItems: [],
				removeItems: [],
				moveItems: [],
				updateGroups: [],
				updateSummary: null,
				invalidateContent: [],
			},
		});

		expect(nextPackage.groups).toEqual([]);
	});
});

class LinearMembershipGuardedArray extends Array<string> {
	override includes(searchElement: string, fromIndex?: number): boolean {
		void searchElement;
		void fromIndex;
		throw new Error('delta add path must use indexed membership');
	}
}
