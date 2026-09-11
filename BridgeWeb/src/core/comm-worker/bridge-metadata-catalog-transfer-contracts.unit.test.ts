import { describe, expect, test } from 'vitest';
import { z } from 'zod';

import transferCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-metadata-catalog-transfer-corpus.json' with { type: 'json' };
import {
	BRIDGE_METADATA_CATALOG_MAXIMUM_CANDIDATE_BYTES,
	BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT,
	createBridgeMetadataCatalogTransferSchema,
} from './bridge-metadata-catalog-transfer-contracts.js';

const fixtureEntrySchema = z
	.object({
		itemId: z.string().min(1),
	})
	.strict();

describe('Bridge metadata catalog transfer contracts', () => {
	test('defines the aggregate catalog ceilings', () => {
		expect(BRIDGE_METADATA_CATALOG_MAXIMUM_CANDIDATE_BYTES).toBe(8 * 1024 * 1024);
		expect(BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT).toBe(200_000);
	});

	test('accepts strict begin, nonempty window, and commit phases', () => {
		const schema = createBridgeMetadataCatalogTransferSchema(fixtureEntrySchema);
		const transfers = [
			{
				catalogRevision: 7,
				expectedEntryCount: 1,
				kind: 'catalog.begin',
				transferId: 'transfer-7',
			},
			{
				catalogRevision: 7,
				entries: [{ itemId: 'item-1' }],
				kind: 'catalog.window',
				transferId: 'transfer-7',
				windowOrdinal: 0,
			},
			{
				catalogRevision: 7,
				entryCount: 1,
				kind: 'catalog.commit',
				transferId: 'transfer-7',
				windowCount: 1,
			},
		] as const;

		for (const transfer of transfers) {
			expect(schema.parse(transfer)).toEqual(transfer);
		}
	});

	test('rejects unknown members, malformed phases, and empty windows', () => {
		const schema = createBridgeMetadataCatalogTransferSchema(fixtureEntrySchema);

		expect(
			schema.safeParse({
				catalogRevision: 7,
				expectedEntryCount: 0,
				kind: 'catalog.begin',
				transferId: 'transfer-7',
				unexpected: true,
			}).success,
		).toBe(false);
		expect(
			schema.safeParse({
				catalogRevision: 7,
				entries: [],
				kind: 'catalog.window',
				transferId: 'transfer-7',
				windowOrdinal: 0,
			}).success,
		).toBe(false);
		expect(
			schema.safeParse({
				catalogRevision: 7,
				entries: [{ itemId: 'item-1', secret: 'not admitted' }],
				kind: 'catalog.window',
				transferId: 'transfer-7',
				windowOrdinal: 0,
			}).success,
		).toBe(false);
		expect(
			schema.safeParse({
				catalogRevision: 7,
				expectedEntryCount: 0,
				phase: 'catalog.begin',
				transferId: 'transfer-7',
			}).success,
		).toBe(false);
	});

	test('decodes the shared Swift and TypeScript strict transfer corpus', () => {
		const sharedEntrySchema = z
			.object({
				itemId: z.string().min(1),
				payload: z.string(),
			})
			.strict();
		const schema = createBridgeMetadataCatalogTransferSchema(sharedEntrySchema);

		for (const sequence of transferCorpus.validSequences) {
			expect(sequence.name.length).toBeGreaterThan(0);
			for (const rawTransfer of sequence.transfers) {
				const transfer = schema.parse(JSON.parse(rawTransfer));
				expect(JSON.stringify(transfer)).toBe(rawTransfer);
			}
		}
	});
});
