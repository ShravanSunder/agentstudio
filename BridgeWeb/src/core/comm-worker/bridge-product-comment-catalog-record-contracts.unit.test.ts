import { describe, expect, test } from 'vitest';

import recordCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-comment-catalog-record-corpus.json' with { type: 'json' };
import {
	bridgeProductCommentCatalogRecordKey,
	bridgeProductCommentCatalogRecordSchema,
} from './bridge-product-comment-catalog-record-contracts.js';

describe('Bridge product comment catalog records', () => {
	test('round-trips keyed session, thread and message records', () => {
		expect(recordCorpus.records).toHaveLength(3);
		for (const { recordKey, record } of recordCorpus.records) {
			const parsed = bridgeProductCommentCatalogRecordSchema.parse(record);
			expect(parsed).toEqual(record);
			expect(bridgeProductCommentCatalogRecordKey(parsed)).toBe(recordKey);
		}
	});

	test('rejects a session record whose revision differs from its committed entry', () => {
		const session = recordCorpus.records[0];
		expect(session).toBeDefined();
		if (session === undefined) return;
		expect(
			bridgeProductCommentCatalogRecordSchema.safeParse({ ...session.record, revision: 2 }).success,
		).toBe(false);
	});
});
