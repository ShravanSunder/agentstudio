import {
	BridgeMainFileTreeDisplayIndex,
	BridgeMainImmutableStringMap,
	type BridgeMainFileItemDisplayIndex,
	type BridgeMainFileTreeIndexApplyResult,
	type BridgeMainPierreFileTreeOperation,
} from './bridge-main-file-tree-display-index.js';
import { BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES } from './bridge-product-contract-primitives.js';
import type {
	BridgeWorkerFileDisplayPatch,
	BridgeWorkerFileDisplayPatchEvent,
} from './bridge-worker-contracts.js';
import { BRIDGE_WORKER_FILE_DISPLAY_PATCH_LIMIT } from './bridge-worker-contracts.js';

export type BridgeMainFileItemDisplayPayload = Extract<
	BridgeWorkerFileDisplayPatch,
	{ readonly operation: 'upsert'; readonly slice: 'fileItem' }
>['payload'];
export type BridgeMainFileStatusDisplayPayload = Extract<
	BridgeWorkerFileDisplayPatch,
	{ readonly operation: 'upsert'; readonly slice: 'fileStatus' }
>['payload'];
export type BridgeMainFileQueryDisplayPayload = Extract<
	BridgeWorkerFileDisplayPatch,
	{ readonly operation: 'upsert'; readonly slice: 'fileQuery' }
>['payload'];

export interface BridgeMainFileDisplayFreshness {
	readonly epoch: number;
	readonly projectionRevision: number;
	readonly sequence: number;
}

export interface BridgeMainFileTreeDisplaySlice {
	readonly index: BridgeMainFileTreeDisplayIndex;
	readonly sourceGeneration: number | null;
	readonly sourceId: string | null;
}

export interface BridgeMainFileDisplayState {
	readonly fileDisplayFreshness: BridgeMainFileDisplayFreshness | null;
	readonly fileItemById: BridgeMainFileItemDisplayIndex<BridgeMainFileItemDisplayPayload>;
	readonly fileQuerySlice: BridgeMainFileQueryDisplayPayload | null;
	readonly fileStatusSlice: BridgeMainFileStatusDisplayPayload | null;
	readonly fileTreeSlice: BridgeMainFileTreeDisplaySlice;
}

export type BridgeMainFileTreePatchStreamEntry =
	| {
			readonly cursor: number;
			readonly kind: 'delta';
			readonly operations: readonly BridgeMainPierreFileTreeOperation[];
	  }
	| { readonly cursor: number; readonly kind: 'clear' }
	| { readonly cursor: number; readonly kind: 'reset' }
	| { readonly cursor: number; readonly kind: 'replacementCommit' }
	| { readonly cursor: number; readonly kind: 'queryBegin'; readonly transactionId: string }
	| { readonly cursor: number; readonly kind: 'queryAbort'; readonly transactionId: string }
	| {
			readonly cursor: number;
			readonly kind: 'queryBatch';
			readonly operations: readonly BridgeMainPierreFileTreeOperation[];
			readonly transactionId: string;
	  }
	| { readonly cursor: number; readonly kind: 'queryCommit'; readonly transactionId: string };

type BridgeMainFileTreePatchStreamEntryInput =
	BridgeMainFileTreePatchStreamEntry extends infer TEntry
		? TEntry extends BridgeMainFileTreePatchStreamEntry
			? Omit<TEntry, 'cursor'>
			: never
		: never;

export interface BridgeMainFileTreePatchStream {
	readonly getCursor: () => number;
	readonly getServerCursor: () => number;
	readonly readAfter: (cursor: number) => readonly BridgeMainFileTreePatchStreamEntry[];
	readonly subscribe: (listener: () => void) => () => void;
}

export type BridgeMainFileDisplayResyncReason =
	| 'acknowledgementMismatch'
	| 'acknowledgementTimeout'
	| 'bufferOverflow'
	| 'protocolViolation';

export interface BridgeMainFileDisplayResyncRequest {
	readonly reason: BridgeMainFileDisplayResyncReason;
	readonly transactionId: string | null;
}

export interface BridgeMainFileDisplayPatchApplierProps {
	readonly acknowledgementTimeoutMilliseconds?: number;
	readonly maximumBufferedBytes?: number;
	readonly maximumBufferedEvents?: number;
	readonly requestResync?: (request: BridgeMainFileDisplayResyncRequest) => void;
	readonly scheduleTimeout?: (callback: () => void, delayMilliseconds: number) => () => void;
}

const bridgeMainFileQueryAcknowledgementTimeoutMilliseconds = 5_000;
const bridgeMainFileDisplayEventEncoder = new TextEncoder();

export class BridgeMainFileDisplayPatchApplier {
	readonly #fileTreePatchStream = new MutableBridgeMainFileTreePatchStream();
	readonly #acknowledgementTimeoutMilliseconds: number;
	readonly #maximumBufferedBytes: number;
	readonly #maximumBufferedEvents: number;
	readonly #requestResync: (request: BridgeMainFileDisplayResyncRequest) => void;
	readonly #scheduleTimeout: (callback: () => void, delayMilliseconds: number) => () => void;
	#pendingQueryTransaction: PendingFileQueryTransaction | null = null;
	#state: BridgeMainFileDisplayState = emptyBridgeMainFileDisplayState();

	constructor(props: BridgeMainFileDisplayPatchApplierProps = {}) {
		this.#acknowledgementTimeoutMilliseconds =
			props.acknowledgementTimeoutMilliseconds ??
			bridgeMainFileQueryAcknowledgementTimeoutMilliseconds;
		this.#maximumBufferedBytes =
			props.maximumBufferedBytes ?? BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES;
		this.#maximumBufferedEvents =
			props.maximumBufferedEvents ?? BRIDGE_WORKER_FILE_DISPLAY_PATCH_LIMIT;
		this.#requestResync = props.requestResync ?? ((): void => {});
		this.#scheduleTimeout = props.scheduleTimeout ?? defaultScheduleTimeout;
	}

	get state(): BridgeMainFileDisplayState {
		return this.#state;
	}

	get fileTreePatchStream(): BridgeMainFileTreePatchStream {
		return this.#fileTreePatchStream;
	}

	applyEvent(event: BridgeWorkerFileDisplayPatchEvent): BridgeMainFileDisplayState | null {
		if (this.#pendingQueryTransaction?.workerCommitReceived === true) {
			return this.#bufferEventAfterTerminalCommit(event);
		}
		if (event.queryTransaction?.phase === 'abort') return this.#applyQueryAbortEvent(event);
		if (event.queryTransaction?.phase === 'batch') return this.#applyQueryTransactionEvent(event);
		if (this.#pendingQueryTransaction !== null) {
			this.#failPendingQueryTransaction('protocolViolation');
			return null;
		}
		if (!fileDisplayEventIsFresh(this.#state.fileDisplayFreshness, event)) return null;
		return this.#applyVisibleEvent(event);
	}

	#applyVisibleEvent(event: BridgeWorkerFileDisplayPatchEvent): BridgeMainFileDisplayState {
		let nextState =
			this.#state.fileDisplayFreshness !== null &&
			event.epoch > this.#state.fileDisplayFreshness.epoch
				? emptyBridgeMainFileDisplayState()
				: this.#state;
		for (const patch of event.patches) nextState = this.#applyVisiblePatch(nextState, patch);
		this.#state = { ...nextState, fileDisplayFreshness: freshnessForEvent(event) };
		return this.#state;
	}

	completeQueryTransaction(transactionId: string): BridgeMainFileDisplayState | null {
		const pendingTransaction = this.#pendingQueryTransaction;
		if (pendingTransaction === null) return null;
		if (
			pendingTransaction.transactionId !== transactionId ||
			!pendingTransaction.workerCommitReceived
		) {
			this.#failPendingQueryTransaction('acknowledgementMismatch');
			return null;
		}
		pendingTransaction.cancelAcknowledgementTimeout?.();
		this.#state = {
			...this.#state,
			fileDisplayFreshness: pendingTransaction.finalFreshness,
			fileQuerySlice: pendingTransaction.query,
			fileTreeSlice: pendingTransaction.treeSlice,
		};
		this.#pendingQueryTransaction = null;
		for (const bufferedEvent of pendingTransaction.bufferedEvents) {
			this.applyEvent(bufferedEvent);
		}
		return this.#state;
	}

	#applyVisiblePatch(
		state: BridgeMainFileDisplayState,
		patch: BridgeWorkerFileDisplayPatch,
	): BridgeMainFileDisplayState {
		switch (patch.slice) {
			case 'fileTree':
				return this.#applyVisibleTreePatch(state, patch);
			case 'fileItem':
				return applyFileItemPatch(state, patch);
			case 'fileStatus':
				return {
					...state,
					fileStatusSlice: patch.operation === 'upsert' ? patch.payload : null,
				};
			case 'fileQuery':
				return { ...state, fileQuerySlice: patch.payload };
			default:
				return assertNeverFileDisplayPatch(patch);
		}
	}

	#applyVisibleTreePatch(
		state: BridgeMainFileDisplayState,
		patch: Extract<BridgeWorkerFileDisplayPatch, { readonly slice: 'fileTree' }>,
	): BridgeMainFileDisplayState {
		if (patch.operation === 'replacementCommit') {
			this.#fileTreePatchStream.append({ kind: 'replacementCommit' });
			return state;
		}
		if (patch.operation === 'reset') {
			this.#fileTreePatchStream.append({ kind: 'reset' });
			return {
				...state,
				fileTreeSlice: {
					index: BridgeMainFileTreeDisplayIndex.empty(),
					sourceGeneration: patch.payload.sourceGeneration,
					sourceId: patch.payload.sourceId,
				},
			};
		}
		if (patch.operation === 'clear') {
			this.#fileTreePatchStream.append({ kind: 'clear' });
			return {
				...state,
				fileTreeSlice: emptyBridgeMainFileTreeSlice(),
			};
		}
		const result = state.fileTreeSlice.index.applyOperations(patch.payload.operations);
		if (result.pierreOperations.length > 0) {
			this.#fileTreePatchStream.append({
				kind: 'delta',
				operations: result.pierreOperations,
			});
		}
		return {
			...state,
			fileTreeSlice: { ...state.fileTreeSlice, index: result.index },
		};
	}

	#applyQueryTransactionEvent(
		event: BridgeWorkerFileDisplayPatchEvent,
	): BridgeMainFileDisplayState | null {
		const transaction = event.queryTransaction;
		if (transaction?.phase !== 'batch') return null;
		const pendingFreshness = this.#pendingQueryTransaction?.finalFreshness ?? null;
		if (!fileDisplayEventIsFresh(pendingFreshness ?? this.#state.fileDisplayFreshness, event)) {
			return null;
		}
		if (transaction.batchIndex === 0) {
			if (this.#pendingQueryTransaction !== null) {
				this.#failPendingQueryTransaction('protocolViolation');
				return null;
			}
			this.#pendingQueryTransaction = {
				batchCount: transaction.batchCount,
				bufferedByteCount: 0,
				bufferedEvents: [],
				cancelAcknowledgementTimeout: null,
				epoch: event.epoch,
				finalFreshness: freshnessForEvent(event),
				nextBatchIndex: 0,
				query: this.#state.fileQuerySlice,
				transactionId: transaction.transactionId,
				treeSlice: {
					index: BridgeMainFileTreeDisplayIndex.empty(),
					sourceGeneration: this.#state.fileTreeSlice.sourceGeneration,
					sourceId: this.#state.fileTreeSlice.sourceId,
				},
				workerCommitReceived: false,
			};
			this.#fileTreePatchStream.append({
				kind: 'queryBegin',
				transactionId: transaction.transactionId,
			});
		}
		let pendingTransaction = this.#pendingQueryTransaction;
		if (!queryTransactionEventMatchesPending(pendingTransaction, event)) {
			this.#failPendingQueryTransaction('protocolViolation');
			return null;
		}
		let nextQuery = pendingTransaction.query;
		let nextTreeSlice = pendingTransaction.treeSlice;
		for (const patch of event.patches) {
			if (patch.slice === 'fileTree' && patch.operation === 'batch') {
				const result: BridgeMainFileTreeIndexApplyResult = nextTreeSlice.index.applyOperations(
					patch.payload.operations,
				);
				nextTreeSlice = { ...nextTreeSlice, index: result.index };
				if (result.pierreOperations.length > 0) {
					this.#fileTreePatchStream.append({
						kind: 'queryBatch',
						operations: result.pierreOperations,
						transactionId: transaction.transactionId,
					});
				}
			} else if (patch.slice === 'fileQuery') {
				nextQuery = patch.payload;
			}
		}
		const nextBatchIndex = transaction.batchIndex + 1;
		pendingTransaction = {
			...pendingTransaction,
			finalFreshness: freshnessForEvent(event),
			nextBatchIndex,
			query: nextQuery,
			treeSlice: nextTreeSlice,
			workerCommitReceived: nextBatchIndex === transaction.batchCount,
		};
		this.#pendingQueryTransaction = pendingTransaction;
		if (pendingTransaction.workerCommitReceived) {
			const transactionId = transaction.transactionId;
			pendingTransaction = {
				...pendingTransaction,
				cancelAcknowledgementTimeout: this.#scheduleTimeout((): void => {
					if (this.#pendingQueryTransaction?.transactionId === transactionId) {
						this.#failPendingQueryTransaction('acknowledgementTimeout');
					}
				}, this.#acknowledgementTimeoutMilliseconds),
			};
			this.#pendingQueryTransaction = pendingTransaction;
			this.#fileTreePatchStream.append({
				kind: 'queryCommit',
				transactionId: transaction.transactionId,
			});
		}
		return null;
	}

	#applyQueryAbortEvent(
		event: BridgeWorkerFileDisplayPatchEvent,
	): BridgeMainFileDisplayState | null {
		const transaction = event.queryTransaction;
		const pendingTransaction = this.#pendingQueryTransaction;
		if (
			transaction?.phase !== 'abort' ||
			pendingTransaction === null ||
			pendingTransaction.workerCommitReceived ||
			pendingTransaction.transactionId !== transaction.transactionId ||
			!fileDisplayEventIsFresh(pendingTransaction.finalFreshness, event)
		) {
			this.#failPendingQueryTransaction('protocolViolation');
			return null;
		}
		this.#pendingQueryTransaction = null;
		this.#fileTreePatchStream.append({
			kind: 'queryAbort',
			transactionId: transaction.transactionId,
		});
		return null;
	}

	#bufferEventAfterTerminalCommit(
		event: BridgeWorkerFileDisplayPatchEvent,
	): BridgeMainFileDisplayState | null {
		const pendingTransaction = this.#pendingQueryTransaction;
		if (pendingTransaction === null || !pendingTransaction.workerCommitReceived) return null;
		const latestBufferedEvent = pendingTransaction.bufferedEvents.at(-1);
		const freshness =
			latestBufferedEvent === undefined
				? pendingTransaction.finalFreshness
				: freshnessForEvent(latestBufferedEvent);
		if (!fileDisplayEventIsFresh(freshness, event)) {
			this.#failPendingQueryTransaction('protocolViolation');
			return null;
		}
		const eventByteCount = encodedFileDisplayEventByteCount(event);
		if (
			pendingTransaction.bufferedEvents.length >= this.#maximumBufferedEvents ||
			pendingTransaction.bufferedByteCount + eventByteCount > this.#maximumBufferedBytes
		) {
			this.#failPendingQueryTransaction('bufferOverflow');
			return null;
		}
		this.#pendingQueryTransaction = {
			...pendingTransaction,
			bufferedByteCount: pendingTransaction.bufferedByteCount + eventByteCount,
			bufferedEvents: pendingTransaction.bufferedEvents.concat(event),
		};
		return null;
	}

	#failPendingQueryTransaction(reason: BridgeMainFileDisplayResyncReason): void {
		const pendingTransaction = this.#pendingQueryTransaction;
		if (pendingTransaction === null) return;
		pendingTransaction.cancelAcknowledgementTimeout?.();
		this.#pendingQueryTransaction = null;
		this.#fileTreePatchStream.append({
			kind: 'queryAbort',
			transactionId: pendingTransaction.transactionId,
		});
		this.#requestResync({ reason, transactionId: pendingTransaction.transactionId });
	}
}

interface PendingFileQueryTransaction {
	readonly batchCount: number;
	readonly bufferedByteCount: number;
	readonly bufferedEvents: readonly BridgeWorkerFileDisplayPatchEvent[];
	readonly cancelAcknowledgementTimeout: (() => void) | null;
	readonly epoch: number;
	readonly finalFreshness: BridgeMainFileDisplayFreshness;
	readonly nextBatchIndex: number;
	readonly query: BridgeMainFileQueryDisplayPayload | null;
	readonly transactionId: string;
	readonly treeSlice: BridgeMainFileTreeDisplaySlice;
	readonly workerCommitReceived: boolean;
}

class MutableBridgeMainFileTreePatchStream implements BridgeMainFileTreePatchStream {
	#cursor = 0;
	#entries: BridgeMainFileTreePatchStreamEntry[] = [];
	readonly #listeners = new Set<() => void>();

	readonly getCursor = (): number => this.#cursor;
	readonly getServerCursor = (): number => this.#cursor;

	readAfter = (cursor: number): readonly BridgeMainFileTreePatchStreamEntry[] =>
		this.#entries.filter((entry) => entry.cursor > cursor);

	subscribe = (listener: () => void): (() => void) => {
		this.#listeners.add(listener);
		return (): void => {
			this.#listeners.delete(listener);
		};
	};

	append(entry: BridgeMainFileTreePatchStreamEntryInput): void {
		this.#cursor += 1;
		const nextEntry = { ...entry, cursor: this.#cursor } as BridgeMainFileTreePatchStreamEntry;
		if (entry.kind === 'reset') this.#entries = [nextEntry];
		else this.#entries.push(nextEntry);
		for (const listener of this.#listeners) listener();
	}
}

function applyFileItemPatch(
	state: BridgeMainFileDisplayState,
	patch: Extract<BridgeWorkerFileDisplayPatch, { readonly slice: 'fileItem' }>,
): BridgeMainFileDisplayState {
	if (patch.operation === 'reset') {
		return { ...state, fileItemById: BridgeMainImmutableStringMap.empty() };
	}
	const fileItems =
		state.fileItemById as BridgeMainImmutableStringMap<BridgeMainFileItemDisplayPayload>;
	return {
		...state,
		fileItemById:
			patch.operation === 'delete'
				? fileItems.delete(patch.itemId)
				: fileItems.set(patch.itemId, patch.payload),
	};
}

function emptyBridgeMainFileDisplayState(): BridgeMainFileDisplayState {
	return {
		fileDisplayFreshness: null,
		fileItemById: BridgeMainImmutableStringMap.empty(),
		fileQuerySlice: null,
		fileStatusSlice: null,
		fileTreeSlice: emptyBridgeMainFileTreeSlice(),
	};
}

function emptyBridgeMainFileTreeSlice(): BridgeMainFileTreeDisplaySlice {
	return {
		index: BridgeMainFileTreeDisplayIndex.empty(),
		sourceGeneration: null,
		sourceId: null,
	};
}

function freshnessForEvent(
	event: BridgeWorkerFileDisplayPatchEvent,
): BridgeMainFileDisplayFreshness {
	return {
		epoch: event.epoch,
		projectionRevision: event.projectionRevision,
		sequence: event.sequence,
	};
}

function fileDisplayEventIsFresh(
	current: BridgeMainFileDisplayFreshness | null,
	event: BridgeWorkerFileDisplayPatchEvent,
): boolean {
	if (current === null || event.epoch > current.epoch) return true;
	return (
		event.epoch === current.epoch &&
		event.sequence > current.sequence &&
		event.projectionRevision > current.projectionRevision
	);
}

function queryTransactionEventMatchesPending(
	pending: PendingFileQueryTransaction | null,
	event: BridgeWorkerFileDisplayPatchEvent,
): pending is PendingFileQueryTransaction {
	const transaction = event.queryTransaction;
	return (
		pending !== null &&
		transaction?.phase === 'batch' &&
		pending.transactionId === transaction.transactionId &&
		pending.batchCount === transaction.batchCount &&
		pending.epoch === event.epoch &&
		pending.nextBatchIndex === transaction.batchIndex
	);
}

function encodedFileDisplayEventByteCount(event: BridgeWorkerFileDisplayPatchEvent): number {
	return bridgeMainFileDisplayEventEncoder.encode(JSON.stringify(event)).byteLength;
}

function defaultScheduleTimeout(callback: () => void, delayMilliseconds: number): () => void {
	const timeoutId = setTimeout(callback, delayMilliseconds);
	return (): void => {
		clearTimeout(timeoutId);
	};
}

function assertNeverFileDisplayPatch(patch: never): never {
	throw new Error(`Unhandled File display patch: ${JSON.stringify(patch)}`);
}
