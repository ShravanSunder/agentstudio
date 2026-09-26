import { describe, expect, test } from 'vitest';

import recordCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-review-batch-record-corpus.json' with { type: 'json' };
import { bridgeProductReviewBatchRecordSchema } from './bridge-product-review-batch-record-contracts.js';

describe('Bridge product Review batch records', () => {
	test('retains ordered item semantics and an empty publication', () => {
		expect(recordCorpus.records).toHaveLength(3);
		for (const { recordKey, record } of recordCorpus.records) {
			const parsed = bridgeProductReviewBatchRecordSchema.parse(record);
			expect(parsed).toEqual(record);
			if (parsed.recordKind === 'item') {
				expect(parsed.itemId).toBe(recordKey);
				expect(parsed.sortKey).toBe(0);
			} else {
				expect(recordKey).toBe('publication');
				if (parsed.displayed !== null) {
					expect(parsed.displayed.revision).toBe(11);
				}
			}
		}
	});

	test('rejects a content source assigned to another item or role', () => {
		const record = bridgeProductReviewBatchRecordSchema.parse(recordCorpus.records[0]?.record);
		if (record.recordKind !== 'item') return;
		const head = record.contentByRole.head;
		if (head.state !== 'available') return;
		expect(
			bridgeProductReviewBatchRecordSchema.safeParse({
				...record,
				contentByRole: {
					...record.contentByRole,
					head: { ...head, source: { ...head.source, itemId: 'another-item' } },
				},
			}).success,
		).toBe(false);
	});
});
