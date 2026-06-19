import { describe, expect, test } from 'vitest';

import { bridgeReviewPackageSchema } from './bridge-review-package-schema.js';
import { makeBridgeReviewPackage } from './bridge-review-package-test-support.js';

describe('Bridge review package schema', () => {
	test('parses the current Bridge review package contract', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const parsedReviewPackage = bridgeReviewPackageSchema.parse(reviewPackage);

		expect(parsedReviewPackage.packageId).toBe(reviewPackage.packageId);
		expect(parsedReviewPackage.orderedItemIds).toEqual(reviewPackage.orderedItemIds);
	});

	test('rejects invalid package payloads at boundary parse time', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const result = bridgeReviewPackageSchema.safeParse({
			...reviewPackage,
			itemsById: undefined,
		});

		expect(result.success).toBe(false);
	});
});
