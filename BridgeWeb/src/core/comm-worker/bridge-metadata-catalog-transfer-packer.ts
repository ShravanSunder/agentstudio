import type { z } from 'zod';

import {
	BRIDGE_METADATA_CATALOG_MAXIMUM_CANDIDATE_BYTES,
	BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT,
	createBridgeMetadataCatalogTransferSchema,
	type BridgeMetadataCatalogTransfer,
	type BridgeMetadataCatalogWindow,
} from './bridge-metadata-catalog-transfer-contracts.js';
import { BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES } from './bridge-product-contract-primitives.js';

export interface PackBridgeMetadataCatalogTransferProps<TEntry> {
	readonly catalogRevision: number;
	readonly encodeEnvelope: (transfer: BridgeMetadataCatalogTransfer<TEntry>) => Uint8Array;
	readonly entries: readonly TEntry[];
	readonly entrySchema: z.ZodType<TEntry>;
	readonly transferId: string;
}

const bridgeMetadataCatalogEntryEncoder = new TextEncoder();

export function packBridgeMetadataCatalogTransfer<TEntry>(
	props: PackBridgeMetadataCatalogTransferProps<TEntry>,
): readonly BridgeMetadataCatalogTransfer<TEntry>[] {
	if (props.entries.length > BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT) {
		throw new Error('Bridge metadata catalog cannot contain more than 200,000 entries.');
	}

	const transferSchema = createBridgeMetadataCatalogTransferSchema(props.entrySchema);
	const parsedEntries: TEntry[] = [];
	let encodedEntryBytes = 0;
	for (const entry of props.entries) {
		const parsedEntry = props.entrySchema.parse(entry);
		const entryByteLength = encodedEntryByteLength(parsedEntry);
		encodedEntryBytes += entryByteLength;
		if (encodedEntryBytes > BRIDGE_METADATA_CATALOG_MAXIMUM_CANDIDATE_BYTES) {
			throw new Error('Bridge metadata catalog cannot exceed 8 MiB of encoded entries.');
		}
		parsedEntries.push(parsedEntry);
	}

	const begin = transferSchema.parse({
		catalogRevision: props.catalogRevision,
		expectedEntryCount: parsedEntries.length,
		kind: 'catalog.begin',
		transferId: props.transferId,
	});
	assertEnvelopeFits(props.encodeEnvelope(begin), 'begin');

	for (const entry of parsedEntries) {
		const individualWindow = transferSchema.parse({
			catalogRevision: props.catalogRevision,
			entries: [entry],
			kind: 'catalog.window',
			transferId: props.transferId,
			windowOrdinal: 0,
		});
		if (
			props.encodeEnvelope(individualWindow).byteLength >
			BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES
		) {
			throw new Error('Bridge metadata catalog contains an indivisible entry over 128 KiB.');
		}
	}

	const windows: BridgeMetadataCatalogWindow<TEntry>[] = [];
	let entryOffset = 0;
	while (entryOffset < parsedEntries.length) {
		const windowOrdinal = windows.length;
		const windowEnd = largestFittingWindowEnd({
			catalogRevision: props.catalogRevision,
			encodeEnvelope: props.encodeEnvelope,
			entries: parsedEntries,
			entryOffset,
			transferId: props.transferId,
			transferSchema,
			windowOrdinal,
		});
		if (windowEnd === entryOffset) {
			throw new Error('Bridge metadata catalog contains an indivisible entry over 128 KiB.');
		}
		const window = transferSchema.parse({
			catalogRevision: props.catalogRevision,
			entries: parsedEntries.slice(entryOffset, windowEnd),
			kind: 'catalog.window',
			transferId: props.transferId,
			windowOrdinal,
		});
		if (window.kind !== 'catalog.window') {
			throw new Error('Bridge metadata catalog packer produced an invalid window kind.');
		}
		windows.push(window);
		entryOffset = windowEnd;
	}

	const commit = transferSchema.parse({
		catalogRevision: props.catalogRevision,
		entryCount: parsedEntries.length,
		kind: 'catalog.commit',
		transferId: props.transferId,
		windowCount: windows.length,
	});
	assertEnvelopeFits(props.encodeEnvelope(commit), 'commit');

	return Object.freeze([begin, ...windows, commit]);
}

interface LargestFittingWindowEndProps<TEntry> {
	readonly catalogRevision: number;
	readonly encodeEnvelope: (transfer: BridgeMetadataCatalogTransfer<TEntry>) => Uint8Array;
	readonly entries: readonly TEntry[];
	readonly entryOffset: number;
	readonly transferId: string;
	readonly transferSchema: z.ZodType<BridgeMetadataCatalogTransfer<TEntry>>;
	readonly windowOrdinal: number;
}

function largestFittingWindowEnd<TEntry>(props: LargestFittingWindowEndProps<TEntry>): number {
	let lowerEnd = props.entryOffset + 1;
	let upperEnd = props.entries.length;
	let largestFittingEnd = props.entryOffset;
	while (lowerEnd <= upperEnd) {
		const prospectiveEnd = lowerEnd + Math.floor((upperEnd - lowerEnd) / 2);
		const prospectiveWindow = props.transferSchema.parse({
			catalogRevision: props.catalogRevision,
			entries: props.entries.slice(props.entryOffset, prospectiveEnd),
			kind: 'catalog.window',
			transferId: props.transferId,
			windowOrdinal: props.windowOrdinal,
		});
		if (
			props.encodeEnvelope(prospectiveWindow).byteLength <=
			BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES
		) {
			largestFittingEnd = prospectiveEnd;
			lowerEnd = prospectiveEnd + 1;
		} else {
			upperEnd = prospectiveEnd - 1;
		}
	}
	return largestFittingEnd;
}

function encodedEntryByteLength(entry: unknown): number {
	const encodedJSON = JSON.stringify(entry);
	if (encodedJSON === undefined) {
		throw new Error('Bridge metadata catalog entries must have a JSON encoding.');
	}
	return bridgeMetadataCatalogEntryEncoder.encode(encodedJSON).byteLength;
}

function assertEnvelopeFits(
	encodedEnvelope: Uint8Array,
	transferBoundary: 'begin' | 'commit',
): void {
	if (encodedEnvelope.byteLength > BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES) {
		throw new Error(`Bridge metadata catalog ${transferBoundary} envelope exceeds 128 KiB.`);
	}
}
