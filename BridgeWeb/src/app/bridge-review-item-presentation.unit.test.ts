import { describe, expect, test } from 'vitest';

import {
	openedReviewItemAfterReviewSourceChange,
	openedReviewItemAfterSelectionChange,
} from './bridge-review-item-presentation.js';

describe('Review item presentation', () => {
	test('keeps Open through transient or repeated selection and closes it for another file', () => {
		expect(
			openedReviewItemAfterSelectionChange({
				openedReviewItemId: 'item-1',
				selectedItemId: null,
			}),
		).toBe('item-1');
		expect(
			openedReviewItemAfterSelectionChange({
				openedReviewItemId: 'item-1',
				selectedItemId: 'item-1',
			}),
		).toBe('item-1');
		expect(
			openedReviewItemAfterSelectionChange({
				openedReviewItemId: 'item-1',
				selectedItemId: 'item-2',
			}),
		).toBeNull();
	});

	test('closes Open when Review is replaced by another package with the same file id', () => {
		expect(
			openedReviewItemAfterReviewSourceChange({
				currentReviewPackageId: 'package-b',
				openedReviewItemId: 'item-1',
				previousReviewPackageId: 'package-a',
			}),
		).toBeNull();
		expect(
			openedReviewItemAfterReviewSourceChange({
				currentReviewPackageId: 'package-a',
				openedReviewItemId: 'item-1',
				previousReviewPackageId: 'package-a',
			}),
		).toBe('item-1');
		expect(
			openedReviewItemAfterReviewSourceChange({
				currentReviewPackageId: null,
				openedReviewItemId: 'item-1',
				previousReviewPackageId: 'package-a',
			}),
		).toBe('item-1');
	});
});
