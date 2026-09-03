import type {
	BridgeCommWorkerAnnotationCatalog,
	BridgeCommWorkerAnnotationCatalogApplicatorResult,
	BridgeCommWorkerAnnotationCatalogAuthority,
} from '../core/comm-worker/bridge-comm-worker-annotation-catalog-applicator.js';
import {
	BRIDGE_METADATA_CATALOG_MAXIMUM_CANDIDATE_BYTES,
	BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT,
} from '../core/comm-worker/bridge-metadata-catalog-transfer-contracts.js';
import { BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES } from '../core/comm-worker/bridge-product-contract-primitives.js';
import {
	bridgeProductWorktreeAnnotationCatalogEntrySchema,
	type BridgeProductWorktreeAnnotationCatalogEntry,
} from '../core/comm-worker/bridge-product-worktree-annotation-contracts.js';
import type { BridgeWorkerAnnotationCatalogStagingEvent } from '../core/comm-worker/bridge-worker-annotation-contracts.js';

type AnnotationSessionEntry = Extract<
	BridgeProductWorktreeAnnotationCatalogEntry,
	{ kind: 'session' }
>;
type AnnotationThreadEntry = Extract<
	BridgeProductWorktreeAnnotationCatalogEntry,
	{ kind: 'thread' }
>;
type AnnotationMessageEntry = Extract<
	BridgeProductWorktreeAnnotationCatalogEntry,
	{ kind: 'message' }
>;

interface MainCatalogCandidate {
	readonly authority: BridgeCommWorkerAnnotationCatalogAuthority;
	readonly catalogRevision: number;
	readonly entries: BridgeProductWorktreeAnnotationCatalogEntry[];
	encodedEntryBytes: number;
	readonly expectedEntryCount: number;
	readonly messageIdsByThreadId: Map<string, string[]>;
	readonly messageOrdinalsByThreadId: Map<string, Set<number>>;
	readonly messagesById: Map<string, AnnotationMessageEntry>;
	nextWindowOrdinal: number;
	readonly orderedSessionIds: string[];
	readonly sessionsById: Map<string, AnnotationSessionEntry>;
	readonly threadIdsBySessionId: Map<string, string[]>;
	readonly threadOrdinalsBySessionId: Map<string, Set<number>>;
	readonly threadsById: Map<string, AnnotationThreadEntry>;
	readonly transferId: string;
}

const catalogStagingEncoder = new TextEncoder();

export class WorktreeAnnotationCatalogStaging {
	#candidate: MainCatalogCandidate | null = null;
	#committedRevision: number | null = null;
	#expectedAuthority: BridgeCommWorkerAnnotationCatalogAuthority | null = null;

	accept(
		event: BridgeWorkerAnnotationCatalogStagingEvent,
	): BridgeCommWorkerAnnotationCatalogApplicatorResult {
		if (
			this.#expectedAuthority === null ||
			!catalogAuthoritiesEqual(this.#expectedAuthority, event.authority)
		) {
			return rejected('unexpected_authority');
		}
		if (
			catalogStagingEncoder.encode(JSON.stringify(event)).byteLength >
			BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES
		) {
			this.#discardMatchingCandidate(event);
			return rejected('malformed_transfer');
		}
		switch (event.transfer.kind) {
			case 'catalog.begin':
				return this.#acceptBegin(event.authority, event.transfer);
			case 'catalog.window':
				return this.#acceptWindow(event.transfer);
			case 'catalog.commit':
				return this.#acceptCommit(event.transfer);
		}
		return assertNeverCatalogTransfer(event.transfer);
	}

	replaceExpectedAuthority(authority: BridgeCommWorkerAnnotationCatalogAuthority): boolean {
		if (
			this.#expectedAuthority !== null &&
			catalogAuthoritiesEqual(this.#expectedAuthority, authority)
		) {
			return false;
		}
		this.#expectedAuthority = authority;
		this.#candidate = null;
		this.#committedRevision = null;
		return true;
	}

	retireExpectedAuthority(): void {
		this.#expectedAuthority = null;
		this.#candidate = null;
		this.#committedRevision = null;
	}

	#acceptBegin(
		authority: BridgeCommWorkerAnnotationCatalogAuthority,
		transfer: Extract<
			BridgeWorkerAnnotationCatalogStagingEvent['transfer'],
			{ readonly kind: 'catalog.begin' }
		>,
	): BridgeCommWorkerAnnotationCatalogApplicatorResult {
		if (transfer.expectedEntryCount > BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT) {
			return rejected('candidate_capacity_exceeded');
		}
		const comparisonRevision = Math.max(
			this.#committedRevision ?? -1,
			this.#candidate?.catalogRevision ?? -1,
		);
		if (transfer.catalogRevision <= comparisonRevision) {
			return rejected('revision_not_newer');
		}
		this.#candidate = {
			authority,
			catalogRevision: transfer.catalogRevision,
			encodedEntryBytes: 0,
			entries: [],
			expectedEntryCount: transfer.expectedEntryCount,
			messageIdsByThreadId: new Map(),
			messageOrdinalsByThreadId: new Map(),
			messagesById: new Map(),
			nextWindowOrdinal: 0,
			orderedSessionIds: [],
			sessionsById: new Map(),
			threadIdsBySessionId: new Map(),
			threadOrdinalsBySessionId: new Map(),
			threadsById: new Map(),
			transferId: transfer.transferId,
		};
		return { status: 'accepted' };
	}

	#acceptWindow(
		transfer: Extract<
			BridgeWorkerAnnotationCatalogStagingEvent['transfer'],
			{ readonly kind: 'catalog.window' }
		>,
	): BridgeCommWorkerAnnotationCatalogApplicatorResult {
		const candidate = this.#matchingCandidate(transfer);
		if (candidate === null) return rejected('noncurrent_transfer');
		if (transfer.windowOrdinal !== candidate.nextWindowOrdinal) {
			this.#candidate = null;
			return rejected('window_ordinal_mismatch');
		}
		if (
			candidate.entries.length + transfer.entries.length > candidate.expectedEntryCount ||
			candidate.entries.length + transfer.entries.length >
				BRIDGE_METADATA_CATALOG_MAXIMUM_ENTRY_COUNT
		) {
			this.#candidate = null;
			return rejected('entry_count_exceeded');
		}
		for (const unknownEntry of transfer.entries) {
			const entry = bridgeProductWorktreeAnnotationCatalogEntrySchema.parse(unknownEntry);
			candidate.encodedEntryBytes += encodedEntryByteLength(entry);
			if (candidate.encodedEntryBytes > BRIDGE_METADATA_CATALOG_MAXIMUM_CANDIDATE_BYTES) {
				this.#candidate = null;
				return rejected('candidate_capacity_exceeded');
			}
			const rejection = applyEntry(candidate, entry);
			if (rejection !== null) {
				this.#candidate = null;
				return rejected(rejection);
			}
			candidate.entries.push(entry);
		}
		candidate.nextWindowOrdinal += 1;
		return { status: 'accepted' };
	}

	#acceptCommit(
		transfer: Extract<
			BridgeWorkerAnnotationCatalogStagingEvent['transfer'],
			{ readonly kind: 'catalog.commit' }
		>,
	): BridgeCommWorkerAnnotationCatalogApplicatorResult {
		const candidate = this.#matchingCandidate(transfer);
		if (candidate === null) return rejected('noncurrent_transfer');
		if (
			transfer.windowCount !== candidate.nextWindowOrdinal ||
			transfer.entryCount !== candidate.entries.length ||
			transfer.entryCount !== candidate.expectedEntryCount
		) {
			this.#candidate = null;
			return rejected('commit_count_mismatch');
		}
		const catalog: BridgeCommWorkerAnnotationCatalog = {
			authority: candidate.authority,
			catalogRevision: candidate.catalogRevision,
			entries: candidate.entries,
			messageIdsByThreadId: candidate.messageIdsByThreadId,
			messagesById: candidate.messagesById,
			orderedSessionIds: candidate.orderedSessionIds,
			sessionsById: candidate.sessionsById,
			threadIdsBySessionId: candidate.threadIdsBySessionId,
			threadsById: candidate.threadsById,
			transferId: candidate.transferId,
		};
		this.#committedRevision = candidate.catalogRevision;
		this.#candidate = null;
		return { catalog, status: 'completed' };
	}

	#discardMatchingCandidate(event: BridgeWorkerAnnotationCatalogStagingEvent): void {
		if (this.#matchingCandidate(event.transfer) !== null) this.#candidate = null;
	}

	#matchingCandidate(
		transfer: BridgeWorkerAnnotationCatalogStagingEvent['transfer'],
	): MainCatalogCandidate | null {
		const candidate = this.#candidate;
		return candidate !== null &&
			candidate.transferId === transfer.transferId &&
			candidate.catalogRevision === transfer.catalogRevision
			? candidate
			: null;
	}
}

function applyEntry(
	candidate: MainCatalogCandidate,
	entry: BridgeProductWorktreeAnnotationCatalogEntry,
):
	| 'duplicate_message_id'
	| 'duplicate_message_ordinal'
	| 'duplicate_session_id'
	| 'duplicate_thread_id'
	| 'duplicate_thread_ordinal'
	| 'unknown_session'
	| 'unknown_thread'
	| null {
	switch (entry.kind) {
		case 'session':
			if (candidate.sessionsById.has(entry.sessionId)) return 'duplicate_session_id';
			candidate.sessionsById.set(entry.sessionId, entry);
			candidate.orderedSessionIds.push(entry.sessionId);
			return null;
		case 'thread': {
			if (!candidate.sessionsById.has(entry.sessionId)) return 'unknown_session';
			if (candidate.threadsById.has(entry.threadId)) return 'duplicate_thread_id';
			const ordinals = candidate.threadOrdinalsBySessionId.get(entry.sessionId) ?? new Set();
			if (ordinals.has(entry.createdOrdinal)) return 'duplicate_thread_ordinal';
			ordinals.add(entry.createdOrdinal);
			candidate.threadOrdinalsBySessionId.set(entry.sessionId, ordinals);
			candidate.threadsById.set(entry.threadId, entry);
			const threadIds = candidate.threadIdsBySessionId.get(entry.sessionId) ?? [];
			threadIds.push(entry.threadId);
			candidate.threadIdsBySessionId.set(entry.sessionId, threadIds);
			return null;
		}
		case 'message': {
			if (!candidate.threadsById.has(entry.threadId)) return 'unknown_thread';
			if (candidate.messagesById.has(entry.messageId)) return 'duplicate_message_id';
			const ordinals = candidate.messageOrdinalsByThreadId.get(entry.threadId) ?? new Set();
			if (ordinals.has(entry.ordinal)) return 'duplicate_message_ordinal';
			ordinals.add(entry.ordinal);
			candidate.messageOrdinalsByThreadId.set(entry.threadId, ordinals);
			candidate.messagesById.set(entry.messageId, entry);
			const messageIds = candidate.messageIdsByThreadId.get(entry.threadId) ?? [];
			messageIds.push(entry.messageId);
			candidate.messageIdsByThreadId.set(entry.threadId, messageIds);
			return null;
		}
	}
	return assertNeverCatalogEntry(entry);
}

function catalogAuthoritiesEqual(
	left: BridgeCommWorkerAnnotationCatalogAuthority,
	right: BridgeCommWorkerAnnotationCatalogAuthority,
): boolean {
	return (
		left.subscriptionId === right.subscriptionId &&
		left.workerDerivationEpoch === right.workerDerivationEpoch &&
		left.worktreeId === right.worktreeId
	);
}

function encodedEntryByteLength(entry: BridgeProductWorktreeAnnotationCatalogEntry): number {
	return catalogStagingEncoder.encode(JSON.stringify(entry)).byteLength;
}

function rejected(
	reason: Exclude<
		BridgeCommWorkerAnnotationCatalogApplicatorResult,
		{ readonly status: 'accepted' | 'completed' }
	>['reason'],
): BridgeCommWorkerAnnotationCatalogApplicatorResult {
	return { reason, status: 'rejected' };
}

function assertNeverCatalogTransfer(value: never): never {
	throw new Error(`Unhandled annotation catalog transfer: ${JSON.stringify(value)}`);
}

function assertNeverCatalogEntry(value: never): never {
	throw new Error(`Unhandled annotation catalog entry: ${JSON.stringify(value)}`);
}
