import { describe, expect, test } from 'vitest';

import rowCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-file-batch-row-corpus.json' with { type: 'json' };
import { bridgeProductFileBatchRowSchema } from './bridge-product-file-batch-row-contracts.js';

describe('Bridge product File batch row', () => {
	test('retains canonical record identity while a deleted ghost has no read descriptor', () => {
		expect(rowCorpus.rows).toHaveLength(3);
		for (const { recordKey, row } of rowCorpus.rows) {
			expect(recordKey.startsWith('/workspace/')).toBe(true);
			expect(bridgeProductFileBatchRowSchema.parse(row)).toEqual(row);
			if (row.kind === 'deleted') {
				expect(row.readDescriptor).toBeNull();
				expect(row.oldPath).not.toBeNull();
			}
		}
	});

	test('rejects a read descriptor on a deleted ghost', () => {
		const fileRow = rowCorpus.rows[0];
		const deletedRow = rowCorpus.rows[2];
		expect(fileRow).toBeDefined();
		expect(deletedRow).toBeDefined();
		if (fileRow === undefined || deletedRow === undefined) return;
		expect(
			bridgeProductFileBatchRowSchema.safeParse({
				...deletedRow.row,
				readDescriptor: fileRow.row.readDescriptor,
			}).success,
		).toBe(false);
	});
});
