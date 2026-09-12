import { z } from 'zod';

import {
	BRIDGE_METADATA_CATALOG_MAXIMUM_CANDIDATE_BYTES,
	BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT,
	createBridgeMetadataCatalogTransferSchema,
	type BridgeMetadataCatalogBegin,
	type BridgeMetadataCatalogCommit,
	type BridgeMetadataCatalogTransfer,
	type BridgeMetadataCatalogWindow,
} from './bridge-metadata-catalog-transfer-contracts.js';

export type MetadataCatalogAssemblerRejectionReason =
	| 'candidate_capacity_exceeded'
	| 'commit_count_mismatch'
	| 'entry_count_exceeded'
	| 'malformed_transfer'
	| 'noncurrent_transfer'
	| 'revision_not_newer'
	| 'unexpected_authority'
	| 'window_ordinal_mismatch';

export interface CompletedMetadataCatalog<TEntry, TAuthority> {
	readonly authority: TAuthority;
	readonly catalogRevision: number;
	readonly entries: readonly TEntry[];
	readonly transferId: string;
}

export type MetadataCatalogAssemblerResult<TEntry, TAuthority> =
	| { readonly status: 'accepted' }
	| {
			readonly catalog: CompletedMetadataCatalog<TEntry, TAuthority>;
			readonly status: 'completed';
	  }
	| {
			readonly reason: MetadataCatalogAssemblerRejectionReason;
			readonly status: 'rejected';
	  };

export interface MetadataCatalogAssemblerDiagnostics {
	readonly candidate: {
		readonly catalogRevision: number;
		readonly encodedEntryBytes: number;
		readonly entryCount: number;
		readonly nextWindowOrdinal: number;
		readonly transferId: string;
	} | null;
	readonly committed: {
		readonly catalogRevision: number;
		readonly transferId: string;
	} | null;
}

export interface MetadataCatalogAssemblerProps<TEntry, TAuthority> {
	readonly authoritiesEqual: (left: TAuthority, right: TAuthority) => boolean;
	readonly entrySchema: z.ZodType<TEntry>;
	readonly expectedAuthority: TAuthority;
	readonly maximumCandidateBytes?: number;
	readonly maximumEntryCount?: number;
}

interface MetadataCatalogCandidate<TEntry> {
	readonly catalogRevision: number;
	readonly entries: TEntry[];
	readonly expectedEntryCount: number;
	readonly transferId: string;
	encodedEntryBytes: number;
	nextWindowOrdinal: number;
}

interface CommittedMetadataCatalogIdentity {
	readonly catalogRevision: number;
	readonly transferId: string;
}

const metadataCatalogTransferIdentityProbeSchema = z
	.object({
		catalogRevision: z.number().int().nonnegative(),
		transferId: z.string(),
	})
	.loose();
const metadataCatalogEntryEncoder = new TextEncoder();

export class MetadataCatalogAssembler<TEntry, TAuthority> {
	readonly #authoritiesEqual: (left: TAuthority, right: TAuthority) => boolean;
	readonly #maximumCandidateBytes: number;
	readonly #maximumEntryCount: number;
	readonly #transferSchema: z.ZodType<BridgeMetadataCatalogTransfer<TEntry>>;
	#candidate: MetadataCatalogCandidate<TEntry> | null = null;
	#committed: CommittedMetadataCatalogIdentity | null = null;
	#expectedAuthority: TAuthority | null;

	constructor(props: MetadataCatalogAssemblerProps<TEntry, TAuthority>) {
		this.#authoritiesEqual = props.authoritiesEqual;
		this.#expectedAuthority = props.expectedAuthority;
		this.#maximumCandidateBytes = validateCapacityLimit(
			props.maximumCandidateBytes ?? BRIDGE_METADATA_CATALOG_MAXIMUM_CANDIDATE_BYTES,
			BRIDGE_METADATA_CATALOG_MAXIMUM_CANDIDATE_BYTES,
			'byte',
		);
		this.#maximumEntryCount = validateCapacityLimit(
			props.maximumEntryCount ?? BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT,
			BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT,
			'entry',
		);
		this.#transferSchema = createBridgeMetadataCatalogTransferSchema(props.entrySchema);
	}

	get diagnostics(): MetadataCatalogAssemblerDiagnostics {
		return {
			candidate:
				this.#candidate === null
					? null
					: {
							catalogRevision: this.#candidate.catalogRevision,
							encodedEntryBytes: this.#candidate.encodedEntryBytes,
							entryCount: this.#candidate.entries.length,
							nextWindowOrdinal: this.#candidate.nextWindowOrdinal,
							transferId: this.#candidate.transferId,
						},
			committed: this.#committed === null ? null : { ...this.#committed },
		};
	}

	accept(
		authority: TAuthority,
		value: unknown,
	): MetadataCatalogAssemblerResult<TEntry, TAuthority> {
		if (
			this.#expectedAuthority === null ||
			!this.#authoritiesEqual(authority, this.#expectedAuthority)
		) {
			return rejected('unexpected_authority');
		}

		const parsedTransfer = this.#transferSchema.safeParse(value);
		if (!parsedTransfer.success) {
			this.#discardCandidateIfIdentityMatches(value);
			return rejected('malformed_transfer');
		}
		const transfer = parsedTransfer.data;
		switch (transfer.kind) {
			case 'catalog.begin':
				return this.#acceptBegin(transfer);
			case 'catalog.window':
				return this.#acceptWindow(transfer);
			case 'catalog.commit':
				return this.#acceptCommit(authority, transfer);
		}
		return assertNever(transfer);
	}

	replaceExpectedAuthority(authority: TAuthority): void {
		if (
			this.#expectedAuthority !== null &&
			this.#authoritiesEqual(this.#expectedAuthority, authority)
		) {
			return;
		}
		this.#expectedAuthority = authority;
		this.#candidate = null;
		this.#committed = null;
	}

	retireExpectedAuthority(): void {
		this.#expectedAuthority = null;
		this.#candidate = null;
		this.#committed = null;
	}

	#acceptBegin(
		begin: BridgeMetadataCatalogBegin,
	): MetadataCatalogAssemblerResult<TEntry, TAuthority> {
		if (begin.expectedEntryCount > this.#maximumEntryCount) {
			return rejected('candidate_capacity_exceeded');
		}
		const comparisonRevision = Math.max(
			this.#committed?.catalogRevision ?? -1,
			this.#candidate?.catalogRevision ?? -1,
		);
		if (begin.catalogRevision <= comparisonRevision) {
			return rejected('revision_not_newer');
		}
		this.#candidate = {
			catalogRevision: begin.catalogRevision,
			encodedEntryBytes: 0,
			entries: [],
			expectedEntryCount: begin.expectedEntryCount,
			nextWindowOrdinal: 0,
			transferId: begin.transferId,
		};
		return { status: 'accepted' };
	}

	#acceptWindow(
		window: BridgeMetadataCatalogWindow<TEntry>,
	): MetadataCatalogAssemblerResult<TEntry, TAuthority> {
		if (!this.#matchesCurrentCandidate(window)) {
			return rejected('noncurrent_transfer');
		}
		const candidate = this.#candidate;
		if (candidate === null) {
			return rejected('noncurrent_transfer');
		}
		if (window.windowOrdinal !== candidate.nextWindowOrdinal) {
			this.#candidate = null;
			return rejected('window_ordinal_mismatch');
		}
		if (
			candidate.entries.length + window.entries.length > candidate.expectedEntryCount ||
			candidate.entries.length + window.entries.length > this.#maximumEntryCount
		) {
			this.#candidate = null;
			return rejected('entry_count_exceeded');
		}

		let windowEncodedEntryBytes = 0;
		for (const entry of window.entries) {
			windowEncodedEntryBytes += encodedEntryByteLength(entry);
		}
		if (candidate.encodedEntryBytes + windowEncodedEntryBytes > this.#maximumCandidateBytes) {
			this.#candidate = null;
			return rejected('candidate_capacity_exceeded');
		}

		candidate.entries.push(...window.entries);
		candidate.encodedEntryBytes += windowEncodedEntryBytes;
		candidate.nextWindowOrdinal += 1;
		return { status: 'accepted' };
	}

	#acceptCommit(
		authority: TAuthority,
		commit: BridgeMetadataCatalogCommit,
	): MetadataCatalogAssemblerResult<TEntry, TAuthority> {
		if (!this.#matchesCurrentCandidate(commit)) {
			return rejected('noncurrent_transfer');
		}
		const candidate = this.#candidate;
		if (candidate === null) {
			return rejected('noncurrent_transfer');
		}
		if (
			commit.windowCount !== candidate.nextWindowOrdinal ||
			commit.entryCount !== candidate.entries.length ||
			commit.entryCount !== candidate.expectedEntryCount
		) {
			this.#candidate = null;
			return rejected('commit_count_mismatch');
		}

		const completedCatalog: CompletedMetadataCatalog<TEntry, TAuthority> = {
			authority,
			catalogRevision: candidate.catalogRevision,
			entries: Object.freeze([...candidate.entries]),
			transferId: candidate.transferId,
		};
		this.#committed = {
			catalogRevision: candidate.catalogRevision,
			transferId: candidate.transferId,
		};
		this.#candidate = null;
		return { catalog: completedCatalog, status: 'completed' };
	}

	#discardCandidateIfIdentityMatches(value: unknown): void {
		const identity = metadataCatalogTransferIdentityProbeSchema.safeParse(value);
		if (
			identity.success &&
			this.#candidate !== null &&
			identity.data.transferId === this.#candidate.transferId &&
			identity.data.catalogRevision === this.#candidate.catalogRevision
		) {
			this.#candidate = null;
		}
	}

	#matchesCurrentCandidate(
		transfer: BridgeMetadataCatalogWindow<TEntry> | BridgeMetadataCatalogCommit,
	): boolean {
		return (
			this.#candidate !== null &&
			transfer.transferId === this.#candidate.transferId &&
			transfer.catalogRevision === this.#candidate.catalogRevision
		);
	}
}

function encodedEntryByteLength(entry: unknown): number {
	const encodedJSON = JSON.stringify(entry);
	if (encodedJSON === undefined) {
		throw new Error('Bridge metadata catalog entries must have a JSON encoding.');
	}
	return metadataCatalogEntryEncoder.encode(encodedJSON).byteLength;
}

function assertNever(value: never): never {
	throw new Error(`Unhandled Bridge metadata catalog transfer: ${JSON.stringify(value)}`);
}

function rejected<TEntry, TAuthority>(
	reason: MetadataCatalogAssemblerRejectionReason,
): MetadataCatalogAssemblerResult<TEntry, TAuthority> {
	return { reason, status: 'rejected' };
}

function validateCapacityLimit(value: number, maximum: number, name: 'byte' | 'entry'): number {
	if (!Number.isSafeInteger(value) || value <= 0 || value > maximum) {
		throw new Error(`Bridge metadata catalog ${name} capacity must fit the protocol ceiling.`);
	}
	return value;
}
