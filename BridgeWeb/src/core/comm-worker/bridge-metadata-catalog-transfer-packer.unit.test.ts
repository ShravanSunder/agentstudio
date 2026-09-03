import { describe, expect, test } from 'vitest';
import { z } from 'zod';

import transferCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-metadata-catalog-transfer-corpus.json' with { type: 'json' };
import {
	BRIDGE_METADATA_CATALOG_MAXIMUM_CANDIDATE_BYTES,
	BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT,
	type BridgeMetadataCatalogTransfer,
} from './bridge-metadata-catalog-transfer-contracts.js';
import { packBridgeMetadataCatalogTransfer } from './bridge-metadata-catalog-transfer-packer.js';
import { BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES } from './bridge-product-contract-primitives.js';

const fixtureEntrySchema = z.object({ itemId: z.string() }).strict();
type FixtureEntry = z.infer<typeof fixtureEntrySchema>;
const textEncoder = new TextEncoder();

describe('Bridge metadata catalog transfer packer', () => {
	test('packs zero entries as begin then commit without an empty window', () => {
		const transfers = packFixtureEntries([]);

		expect(transfers).toEqual([
			{
				catalogRevision: 4,
				expectedEntryCount: 0,
				kind: 'catalog.begin',
				transferId: 'transfer-4',
			},
			{
				catalogRevision: 4,
				entryCount: 0,
				kind: 'catalog.commit',
				transferId: 'transfer-4',
				windowCount: 0,
			},
		]);
	});

	test('packs complete entries using the supplied full envelope measurement', () => {
		const entries = Array.from({ length: 9 }, (_, index) => ({
			itemId: `${index}-`.padEnd(24_000, 'x'),
		}));
		const transfers = packFixtureEntries(entries);
		const windows = transfers.filter((transfer) => transfer.kind === 'catalog.window');

		expect(windows.length).toBeGreaterThan(1);
		expect(windows.flatMap((window) => window.entries)).toEqual(entries);
		for (const transfer of transfers) {
			expect(encodeFixtureEnvelope(transfer).byteLength).toBeLessThanOrEqual(
				BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
			);
		}
	});

	test('admits an exact 128 KiB envelope and rejects the next byte', () => {
		const emptyWindowBytes = encodeFixtureEnvelope({
			catalogRevision: 4,
			entries: [{ itemId: '' }],
			kind: 'catalog.window',
			transferId: 'transfer-4',
			windowOrdinal: 0,
		}).byteLength;
		const exactEntry = {
			itemId: 'x'.repeat(BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES - emptyWindowBytes),
		};
		const exactWindow = packFixtureEntries([exactEntry]).find(
			(transfer) => transfer.kind === 'catalog.window',
		);
		expect(exactWindow).toBeDefined();
		if (exactWindow === undefined) {
			throw new Error('Expected an exact-boundary catalog window.');
		}
		expect(encodeFixtureEnvelope(exactWindow).byteLength).toBe(
			BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
		);
		expect(() => packFixtureEntries([{ itemId: `${exactEntry.itemId}x` }])).toThrow(/indivisible/u);
	});

	test('admits exact aggregate limits and rejects either first exceeded limit', () => {
		const exactByteEntries = makeEntriesWithExactEncodedBytes(
			BRIDGE_METADATA_CATALOG_MAXIMUM_CANDIDATE_BYTES,
		);
		expect(totalEncodedEntryBytes(exactByteEntries)).toBe(
			BRIDGE_METADATA_CATALOG_MAXIMUM_CANDIDATE_BYTES,
		);
		expect(packFixtureEntries(exactByteEntries).at(-1)).toMatchObject({
			entryCount: exactByteEntries.length,
			kind: 'catalog.commit',
		});
		expect(() => packFixtureEntries([...exactByteEntries, { itemId: '' }])).toThrow(/8 MiB/u);

		const emptyEntrySchema = z.object({}).strict();
		const exactCountEntries = Array.from(
			{ length: BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT },
			() => ({}),
		);
		expect(
			packBridgeMetadataCatalogTransfer({
				catalogRevision: 1,
				encodeEnvelope: (transfer) => textEncoder.encode(JSON.stringify({ transfer })),
				entries: exactCountEntries,
				entrySchema: emptyEntrySchema,
				transferId: 'count-boundary',
			}).at(-1),
		).toMatchObject({ entryCount: BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT });
		expect(() =>
			packBridgeMetadataCatalogTransfer({
				catalogRevision: 1,
				encodeEnvelope: (transfer) => textEncoder.encode(JSON.stringify({ transfer })),
				entries: [...exactCountEntries, {}],
				entrySchema: emptyEntrySchema,
				transferId: 'count-overflow',
			}),
		).toThrow(/200,000/u);
	});

	test('preflights every entry and emits nothing when one entry cannot fit', () => {
		const emittedEnvelopes: Uint8Array[] = [];
		expect(() =>
			packBridgeMetadataCatalogTransfer({
				catalogRevision: 4,
				encodeEnvelope: (transfer) => {
					const bytes = encodeFixtureEnvelope(transfer);
					emittedEnvelopes.push(bytes);
					return bytes;
				},
				entries: [
					{ itemId: 'fits' },
					{ itemId: 'x'.repeat(BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES) },
				],
				entrySchema: fixtureEntrySchema,
				transferId: 'transfer-4',
			}),
		).toThrow(/indivisible/u);
		// Encoding is a pure preflight supplied by the caller; no transfer is returned or emitted.
		expect(emittedEnvelopes.some((bytes) => bytes.byteLength > 0)).toBe(true);
	});

	test('packs the shared large-catalog recipe into the expected bounded windows', () => {
		const recipe = transferCorpus.largeCatalogRecipe;
		const sharedEntrySchema = z
			.object({
				itemId: z.string().min(1),
				payload: z.string(),
			})
			.strict();
		const entries = Array.from({ length: recipe.entryCount }, (_, index) => ({
			itemId: `item-${index}`,
			payload: 'x'.repeat(recipe.payloadCharacterCount),
		}));

		const transfers = packBridgeMetadataCatalogTransfer({
			catalogRevision: recipe.catalogRevision,
			encodeEnvelope: (transfer) =>
				textEncoder.encode(
					JSON.stringify({
						data: { event: transfer, subscriptionKind: 'fixture.metadata' },
						kind: 'subscription.data',
					}),
				),
			entries,
			entrySchema: sharedEntrySchema,
			transferId: recipe.transferId,
		});
		const windows = transfers.filter((transfer) => transfer.kind === 'catalog.window');

		expect(windows).toHaveLength(recipe.expectedWindowCount);
		expect(windows.length).toBeGreaterThan(1);
		expect(transfers.at(0)).toMatchObject({ expectedEntryCount: recipe.entryCount });
		expect(transfers.at(-1)).toMatchObject({ entryCount: recipe.entryCount });
	});
});

function packFixtureEntries(
	entries: readonly FixtureEntry[],
): readonly BridgeMetadataCatalogTransfer<FixtureEntry>[] {
	return packBridgeMetadataCatalogTransfer({
		catalogRevision: 4,
		encodeEnvelope: encodeFixtureEnvelope,
		entries,
		entrySchema: fixtureEntrySchema,
		transferId: 'transfer-4',
	});
}

function encodeFixtureEnvelope(transfer: BridgeMetadataCatalogTransfer<FixtureEntry>): Uint8Array {
	return textEncoder.encode(
		JSON.stringify({
			data: { event: transfer, subscriptionKind: 'fixture.metadata' },
			kind: 'subscription.data',
		}),
	);
}

function totalEncodedEntryBytes(entries: readonly FixtureEntry[]): number {
	return entries.reduce(
		(totalBytes, entry) => totalBytes + textEncoder.encode(JSON.stringify(entry)).byteLength,
		0,
	);
}

function makeEntriesWithExactEncodedBytes(targetBytes: number): readonly FixtureEntry[] {
	const entries: FixtureEntry[] = [];
	let remainingBytes = targetBytes;
	const emptyEntryBytes = totalEncodedEntryBytes([{ itemId: '' }]);
	while (remainingBytes > 100_000) {
		const entryBytes = 100_000;
		entries.push({ itemId: 'x'.repeat(entryBytes - emptyEntryBytes) });
		remainingBytes -= entryBytes;
	}
	entries.push({ itemId: 'x'.repeat(remainingBytes - emptyEntryBytes) });
	return entries;
}
