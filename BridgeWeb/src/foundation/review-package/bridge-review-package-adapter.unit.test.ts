import { describe, expect, test } from 'vitest';

import { contentHandlesForItem, orderedReviewItems } from './bridge-review-package-adapter.js';
import { makeBridgeReviewPackage } from './bridge-review-package-test-support.js';

describe('bridge review package adapter', () => {
	test('orders visible items by package order and exposes scoped content handles', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const items = orderedReviewItems(reviewPackage);
		const firstItem = items[0];

		if (firstItem === undefined) {
			throw new Error('expected at least one ordered review item');
		}

		expect(items.map((item) => item.itemId)).toEqual(['item-source']);
		expect(contentHandlesForItem(firstItem).map((handle) => handle.role)).toEqual(['base', 'head']);
	});

	test('treats omitted optional content-role slots as absent handles', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const firstItem = orderedReviewItems(reviewPackage)[0];

		if (firstItem === undefined) {
			throw new Error('expected at least one ordered review item');
		}
		const base = firstItem.contentRoles.base;
		const head = firstItem.contentRoles.head;
		if (base === null || base === undefined || head === null || head === undefined) {
			throw new Error('expected base and head handles');
		}

		const itemWithOmittedRoles = {
			...firstItem,
			contentRoles: {
				base,
				head,
			},
		};

		expect(contentHandlesForItem(itemWithOmittedRoles).map((handle) => handle.role)).toEqual([
			'base',
			'head',
		]);
	});
});
