import { describe, expect, test } from 'vitest';

import { reviewTreeRowMetadataSchema } from './review-protocol-models.js';

describe('Review tree row metadata', () => {
	test('accepts hierarchical product rows and rejects legacy descriptor fields', () => {
		const row = {
			depth: 2,
			isDirectory: false,
			itemId: 'item-1',
			lane: 'visible',
			loaded_by: 'visible',
			path: 'Sources/App/View.swift',
			rowId: 'row:item-1',
		};

		expect(reviewTreeRowMetadataSchema.safeParse(row).success).toBe(true);
		expect(
			reviewTreeRowMetadataSchema.safeParse({
				...row,
				contentDescriptor: { descriptorId: 'legacy-resource' },
			}).success,
		).toBe(false);
	});
});
