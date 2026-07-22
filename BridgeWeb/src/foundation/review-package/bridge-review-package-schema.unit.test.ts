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

	test('accepts omitted keys for Swift nil optional fields', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		if (item === undefined) {
			throw new Error('Expected item-source fixture item');
		}
		const packageWithOmittedNilOptionals = {
			...reviewPackage,
			query: {
				...reviewPackage.query,
				baseEndpointId: undefined,
				headEndpointId: undefined,
				fileTarget: undefined,
				grouping: {
					...reviewPackage.query.grouping,
					label: undefined,
				},
				provenanceFilter: {
					...reviewPackage.query.provenanceFilter,
					createdAfterUnixMilliseconds: undefined,
					createdBeforeUnixMilliseconds: undefined,
				},
			},
			baseEndpoint: {
				...reviewPackage.baseEndpoint,
				contentSetHash: undefined,
			},
			headEndpoint: {
				...reviewPackage.headEndpoint,
				contentSetHash: undefined,
			},
			itemsById: {
				'item-source': {
					...item,
					baseContentHash: undefined,
					headContentHash: undefined,
					hiddenReason: undefined,
					contentRoles: {
						base: item.contentRoles.base,
						head: item.contentRoles.head,
					},
				},
			},
		};

		const parsedReviewPackage = bridgeReviewPackageSchema.parse(packageWithOmittedNilOptionals);

		expect(parsedReviewPackage.query.fileTarget).toBeUndefined();
		expect(parsedReviewPackage.itemsById['item-source']?.hiddenReason).toBeUndefined();
	});

	test('rejects invalid package payloads at boundary parse time', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const result = bridgeReviewPackageSchema.safeParse({
			...reviewPackage,
			itemsById: undefined,
		});

		expect(result.success).toBe(false);
	});

	test('rejects legacy feature resource URL authority on content handles', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const baseHandle = item?.contentRoles.base;
		if (item === undefined || baseHandle === null || baseHandle === undefined) {
			throw new Error('Expected item-source base handle fixture');
		}

		const result = bridgeReviewPackageSchema.safeParse({
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				[item.itemId]: {
					...item,
					contentRoles: {
						...item.contentRoles,
						base: {
							...baseHandle,
							resourceUrl: 'agentstudio://resource/review/content/legacy',
						},
					},
				},
			},
		});

		expect(result.success).toBe(false);
	});
});
