import { describe, expect, test } from 'vitest';

import {
	makeBridgeContentHandle,
	makeBridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-test-support.js';
import { contentAddressedResourceKey } from '../review-viewer/content/review-content-registry.js';
import { contentResourceKeysForReviewHandleIds } from './bridge-app-review-descriptors.js';

describe('content resource keys for review handle ids', () => {
	test('maps invalidated handle ids to canonical registry keys', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const headHandle = makeBridgeContentHandle('item-source', 'head');

		const resourceKeys = contentResourceKeysForReviewHandleIds({
			handleIds: new Set([headHandle.handleId]),
			reviewPackage,
		});

		expect(resourceKeys).toEqual([contentAddressedResourceKey(headHandle)]);
	});

	test('returns every content role key when all handles are invalidated', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const allHandleIds = new Set<string>();
		for (const item of Object.values(reviewPackage.itemsById)) {
			for (const handle of Object.values(item.contentRoles)) {
				if (handle !== null && handle !== undefined) {
					allHandleIds.add(handle.handleId);
				}
			}
		}

		const resourceKeys = contentResourceKeysForReviewHandleIds({
			handleIds: allHandleIds,
			reviewPackage,
		});

		expect(resourceKeys.length).toBe(allHandleIds.size);
	});

	test('returns no keys without a package or without invalidated handles', () => {
		const reviewPackage = makeBridgeReviewPackage();

		expect(
			contentResourceKeysForReviewHandleIds({
				handleIds: new Set(['handle-item-source-head']),
				reviewPackage: null,
			}),
		).toEqual([]);
		expect(
			contentResourceKeysForReviewHandleIds({
				handleIds: new Set<string>(),
				reviewPackage,
			}),
		).toEqual([]);
	});
});
