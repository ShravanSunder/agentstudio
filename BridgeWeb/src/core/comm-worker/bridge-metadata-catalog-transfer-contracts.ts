import { z } from 'zod';

import {
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
} from './bridge-product-contract-primitives.js';

export const BRIDGE_METADATA_CATALOG_MAXIMUM_CANDIDATE_BYTES = 8 * 1024 * 1024;
export const BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT = 200_000;

export interface BridgeMetadataCatalogBegin {
	readonly catalogRevision: number;
	readonly expectedEntryCount: number;
	readonly kind: 'catalog.begin';
	readonly transferId: string;
}

export interface BridgeMetadataCatalogWindow<TEntry> {
	readonly catalogRevision: number;
	readonly entries: readonly TEntry[];
	readonly kind: 'catalog.window';
	readonly transferId: string;
	readonly windowOrdinal: number;
}

export interface BridgeMetadataCatalogCommit {
	readonly catalogRevision: number;
	readonly entryCount: number;
	readonly kind: 'catalog.commit';
	readonly transferId: string;
	readonly windowCount: number;
}

export type BridgeMetadataCatalogTransfer<TEntry> =
	| BridgeMetadataCatalogBegin
	| BridgeMetadataCatalogWindow<TEntry>
	| BridgeMetadataCatalogCommit;

export function createBridgeMetadataCatalogTransferSchema<TEntry>(
	entrySchema: z.ZodType<TEntry>,
): z.ZodType<BridgeMetadataCatalogTransfer<TEntry>> {
	return z.discriminatedUnion('kind', [
		z
			.object({
				catalogRevision: bridgeProductNonnegativeSequenceSchema,
				expectedEntryCount: bridgeProductNonnegativeSequenceSchema.max(
					BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT,
				),
				kind: z.literal('catalog.begin'),
				transferId: bridgeProductIdentifierSchema,
			})
			.strict(),
		z
			.object({
				catalogRevision: bridgeProductNonnegativeSequenceSchema,
				entries: z.array(entrySchema).min(1).max(BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT),
				kind: z.literal('catalog.window'),
				transferId: bridgeProductIdentifierSchema,
				windowOrdinal: bridgeProductNonnegativeSequenceSchema,
			})
			.strict(),
		z
			.object({
				catalogRevision: bridgeProductNonnegativeSequenceSchema,
				entryCount: bridgeProductNonnegativeSequenceSchema.max(
					BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT,
				),
				kind: z.literal('catalog.commit'),
				transferId: bridgeProductIdentifierSchema,
				windowCount: bridgeProductNonnegativeSequenceSchema,
			})
			.strict(),
	]);
}
