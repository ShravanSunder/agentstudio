import { compileBridgeFileTreeSearchPattern } from '../models/bridge-file-tree-search.js';
import type { BridgeCommWorkerFileDisplayEventAuthority } from './bridge-comm-worker-file-display-event-authority.js';
import {
	BRIDGE_WORKER_FILE_DISPLAY_PATCH_LIMIT,
	type BridgeWorkerFileDisplayPatch,
	type BridgeWorkerFileQueryUpdateCommand,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type {
	BridgeWorkerFileQuery,
	BridgeWorkerFileQueryDisplayPayload,
} from './bridge-worker-file-query-contracts.js';

type FileTreePatch = Extract<BridgeWorkerFileDisplayPatch, { readonly slice: 'fileTree' }>;
type FileTreeBatchPatch = Extract<FileTreePatch, { readonly operation: 'batch' }>;
type FileTreeResetPatch = Extract<FileTreePatch, { readonly operation: 'clear' | 'reset' }>;
type FileTreeOperation = FileTreeBatchPatch['payload']['operations'][number];
type FileTreeRow = Extract<FileTreeOperation, { readonly operation: 'upsert' }>['row'];
type FileItemPatch = Extract<BridgeWorkerFileDisplayPatch, { readonly slice: 'fileItem' }>;
type FileItemPayload = Extract<FileItemPatch, { readonly operation: 'upsert' }>['payload'];
type FileStatusPatch = Extract<BridgeWorkerFileDisplayPatch, { readonly slice: 'fileStatus' }>;

const defaultBridgeWorkerFileQuery: BridgeWorkerFileQuery = {
	filterMode: 'all',
	searchMode: 'text',
	searchText: '',
};
const defaultMaximumRowsPerQueryChunk = 128;

export interface BridgeCommWorkerFileQueryProjectionResult {
	readonly evaluatedRowCount: number;
	readonly patches: readonly BridgeWorkerFileDisplayPatch[];
	readonly queryTransactionId: string | null;
}

export interface BridgeCommWorkerFileQueryProjectionProps {
	readonly maximumRowsPerQueryChunk?: number;
	readonly recordEvaluatedQueryChunk?: (evaluatedRowCount: number) => void;
	readonly scheduleQueryChunk?: (runChunk: () => void) => void;
}

export class BridgeCommWorkerFileQueryProjection {
	readonly #fileItemsById = new Map<string, FileItemPayload>();
	#fileStatusPatch: Extract<FileStatusPatch, { readonly operation: 'upsert' }> | null = null;
	#fileTreeReplacementCommitted = false;
	#fileTreeResetPatch: FileTreeResetPatch = { operation: 'clear', slice: 'fileTree' };
	readonly #maximumRowsPerQueryChunk: number;
	#pendingQuery: PendingFileQueryProjection | null = null;
	#projectedRowsById = new Map<string, FileTreeRow>();
	#publishedQuery: BridgeWorkerFileQuery = defaultBridgeWorkerFileQuery;
	#publishedQueryPattern: RegExp | null = null;
	#publishedQuerySearchError: string | null = null;
	#queryGeneration = 0;
	readonly #rawRowsById = new Map<string, FileTreeRow>();
	readonly #recordEvaluatedQueryChunk: (evaluatedRowCount: number) => void;
	readonly #rowIdsByFileId = new Map<string, Set<string>>();
	readonly #scheduleQueryChunk: (runChunk: () => void) => void;

	constructor(props: BridgeCommWorkerFileQueryProjectionProps = {}) {
		this.#maximumRowsPerQueryChunk =
			props.maximumRowsPerQueryChunk ?? defaultMaximumRowsPerQueryChunk;
		if (!Number.isInteger(this.#maximumRowsPerQueryChunk) || this.#maximumRowsPerQueryChunk <= 0) {
			throw new Error('File query chunk row limit must be a positive integer.');
		}
		this.#recordEvaluatedQueryChunk = props.recordEvaluatedQueryChunk ?? ignoreQueryChunk;
		this.#scheduleQueryChunk = props.scheduleQueryChunk ?? scheduleFileQueryMacrotask;
	}

	applyDisplayPatches(
		patches: readonly BridgeWorkerFileDisplayPatch[],
	): BridgeCommWorkerFileQueryProjectionResult {
		if (patches.length === 0) return noFileQueryProjectionChange();
		let evaluatedRowCount = 0;
		let queryInputsChanged = false;
		let queryStatusChanged = false;
		let projectedTreeOperations: FileTreeOperation[] = [];
		const projectedPatches: BridgeWorkerFileDisplayPatch[] = [];
		const flushProjectedTreeOperations = (): void => {
			if (projectedTreeOperations.length === 0) return;
			projectedPatches.push(...fileTreeOperationBatches(projectedTreeOperations));
			projectedTreeOperations = [];
		};

		for (const patch of patches) {
			switch (patch.slice) {
				case 'fileTree': {
					if (patch.operation === 'replacementCommit') {
						flushProjectedTreeOperations();
						this.#fileTreeReplacementCommitted = true;
						projectedPatches.push(patch);
						break;
					}
					if (patch.operation !== 'batch') flushProjectedTreeOperations();
					const result = this.#applyFileTreePatch(patch, projectedTreeOperations);
					evaluatedRowCount += result.evaluatedRowCount;
					queryStatusChanged = result.queryStatusChanged || queryStatusChanged;
					queryInputsChanged = true;
					if (patch.operation !== 'batch') projectedPatches.push(patch);
					break;
				}
				case 'fileItem': {
					const result = this.#applyFileItemPatch(patch, projectedTreeOperations);
					evaluatedRowCount += result.evaluatedRowCount;
					queryStatusChanged = result.queryStatusChanged || queryStatusChanged;
					queryInputsChanged = true;
					projectedPatches.push(patch);
					break;
				}
				case 'fileStatus':
					this.#fileStatusPatch = patch.operation === 'upsert' ? patch : null;
					projectedPatches.push(patch);
					break;
				case 'fileQuery':
					throw new Error('File query projection cannot consume its own display patch.');
				default:
					assertNeverFileDisplayPatch(patch);
			}
		}

		flushProjectedTreeOperations();
		if (queryInputsChanged) this.#restartPendingQuery();
		return changedFileQueryProjection(
			[...projectedPatches, ...(queryStatusChanged ? [this.#publishedQueryStatusPatch()] : [])],
			evaluatedRowCount,
		);
	}

	snapshotDisplayPatches(): readonly BridgeWorkerFileDisplayPatch[] {
		const projectedTreeOperations: FileTreeOperation[] = [...this.#projectedRowsById.values()]
			.toSorted((left, right) => left.projectionIndex - right.projectionIndex)
			.map((row) => ({ operation: 'upsert', row }));
		const fileItemPatches: FileItemPatch[] = [...this.#fileItemsById.entries()]
			.toSorted(([leftItemId], [rightItemId]) => leftItemId.localeCompare(rightItemId))
			.map(([itemId, payload]) => ({ itemId, operation: 'upsert', payload, slice: 'fileItem' }));
		return [
			this.#fileTreeResetPatch,
			{ operation: 'reset', slice: 'fileItem' },
			{ operation: 'reset', slice: 'fileStatus' },
			...fileItemPatches,
			...(this.#fileStatusPatch === null ? [] : [this.#fileStatusPatch]),
			...fileTreeOperationBatches(projectedTreeOperations),
			...(this.#fileTreeReplacementCommitted && this.#fileTreeResetPatch.operation === 'reset'
				? [
						{
							operation: 'replacementCommit' as const,
							payload: this.#fileTreeResetPatch.payload,
							slice: 'fileTree' as const,
						},
					]
				: []),
			this.#publishedQueryStatusPatch(),
		];
	}

	updateQuery(props: {
		readonly publish: (result: BridgeCommWorkerFileQueryProjectionResult) => void;
		readonly query: BridgeWorkerFileQuery;
	}): boolean {
		if (
			(this.#pendingQuery !== null && fileQueriesEqual(this.#pendingQuery.query, props.query)) ||
			(this.#pendingQuery === null && fileQueriesEqual(this.#publishedQuery, props.query))
		) {
			return false;
		}
		this.#startQueryProjection(props.query, props.publish);
		return true;
	}

	#startQueryProjection(
		query: BridgeWorkerFileQuery,
		publish: (result: BridgeCommWorkerFileQueryProjectionResult) => void,
	): void {
		this.#queryGeneration += 1;
		const searchPattern = compileBridgeFileTreeSearchPattern(query);
		const pendingQuery: PendingFileQueryProjection = {
			evaluatedRowCount: 0,
			generation: this.#queryGeneration,
			nextProjectedRowsById: new Map(),
			operationBatches: [],
			pendingOperations: [],
			publish,
			query,
			rowIterator: this.#rawRowsById.values(),
			searchError: searchPattern.searchError,
			searchPattern: searchPattern.pattern,
		};
		this.#pendingQuery = pendingQuery;
		this.#scheduleQueryChunk((): void => {
			this.#runQueryChunk(pendingQuery.generation);
		});
	}

	#restartPendingQuery(): void {
		const pendingQuery = this.#pendingQuery;
		if (pendingQuery === null) return;
		this.#startQueryProjection(pendingQuery.query, pendingQuery.publish);
	}

	#runQueryChunk(generation: number): void {
		const pendingQuery = this.#pendingQuery;
		if (pendingQuery === null || pendingQuery.generation !== generation) return;
		let evaluatedRowCount = 0;
		let iteratorResult = pendingQuery.rowIterator.next();
		while (!iteratorResult.done && evaluatedRowCount < this.#maximumRowsPerQueryChunk) {
			this.#evaluatePendingQueryRow(pendingQuery, iteratorResult.value);
			evaluatedRowCount += 1;
			iteratorResult = pendingQuery.rowIterator.next();
		}
		pendingQuery.evaluatedRowCount += evaluatedRowCount;
		this.#recordEvaluatedQueryChunk(evaluatedRowCount);
		if (iteratorResult.done) {
			this.#finishPendingQuery(pendingQuery);
			return;
		}
		pendingQuery.rowIterator = prependIteratorValue(iteratorResult.value, pendingQuery.rowIterator);
		this.#scheduleQueryChunk((): void => {
			this.#runQueryChunk(generation);
		});
	}

	#evaluatePendingQueryRow(pendingQuery: PendingFileQueryProjection, row: FileTreeRow): void {
		if (
			!this.#rowMatchesQuery(
				row,
				pendingQuery.query,
				pendingQuery.searchPattern,
				pendingQuery.searchError,
			)
		) {
			return;
		}
		pendingQuery.nextProjectedRowsById.set(row.rowId, row);
	}

	#finishPendingQuery(pendingQuery: PendingFileQueryProjection): void {
		if (this.#pendingQuery?.generation !== pendingQuery.generation) return;
		for (const row of [...pendingQuery.nextProjectedRowsById.values()].toSorted(
			(left, right) => left.projectionIndex - right.projectionIndex,
		)) {
			appendPendingFileTreeOperation(pendingQuery, { operation: 'upsert', row });
		}
		flushPendingFileTreeOperations(pendingQuery);
		this.#projectedRowsById = pendingQuery.nextProjectedRowsById;
		this.#publishedQuery = pendingQuery.query;
		this.#publishedQueryPattern = pendingQuery.searchPattern;
		this.#publishedQuerySearchError = pendingQuery.searchError;
		this.#pendingQuery = null;
		pendingQuery.publish({
			evaluatedRowCount: pendingQuery.evaluatedRowCount,
			patches: [...pendingQuery.operationBatches, this.#publishedQueryStatusPatch()],
			queryTransactionId: `file-query-${String(pendingQuery.generation)}`,
		});
	}

	#applyFileTreePatch(
		patch: Exclude<FileTreePatch, { readonly operation: 'replacementCommit' }>,
		projectedOperations: FileTreeOperation[],
	): { readonly evaluatedRowCount: number; readonly queryStatusChanged: boolean } {
		if (patch.operation === 'reset' || patch.operation === 'clear') {
			this.#fileTreeReplacementCommitted = false;
			this.#fileTreeResetPatch = patch;
			this.#rawRowsById.clear();
			this.#projectedRowsById.clear();
			this.#rowIdsByFileId.clear();
			return { evaluatedRowCount: 0, queryStatusChanged: true };
		}
		let evaluatedRowCount = 0;
		let queryStatusChanged = false;
		for (const operation of patch.payload.operations) {
			if (operation.operation === 'remove') {
				const previousRow = this.#rawRowsById.get(operation.rowId);
				if (previousRow === undefined) continue;
				this.#removeRawRow(previousRow);
				const previousProjectedRow = this.#projectedRowsById.get(operation.rowId);
				if (previousProjectedRow !== undefined) {
					this.#projectedRowsById.delete(operation.rowId);
					projectedOperations.push({
						operation: 'remove',
						path: previousProjectedRow.path,
						rowId: previousProjectedRow.rowId,
					});
				}
				queryStatusChanged = true;
				continue;
			}
			const previousRow = this.#rawRowsById.get(operation.row.rowId);
			if (previousRow !== undefined) this.#removeRawRow(previousRow);
			this.#rawRowsById.set(operation.row.rowId, operation.row);
			this.#indexRawRow(operation.row);
			this.#applyPublishedQueryRowTransition(operation.row, projectedOperations);
			evaluatedRowCount += 1;
			queryStatusChanged = previousRow === undefined || queryStatusChanged;
		}
		return { evaluatedRowCount, queryStatusChanged };
	}

	#applyFileItemPatch(
		patch: FileItemPatch,
		projectedOperations: FileTreeOperation[],
	): { readonly evaluatedRowCount: number; readonly queryStatusChanged: boolean } {
		if (patch.operation === 'reset') {
			this.#fileItemsById.clear();
			return this.#reevaluatePublishedQueryRows(this.#rawRowsById.values(), projectedOperations);
		}
		if (patch.operation === 'delete') this.#fileItemsById.delete(patch.itemId);
		else this.#fileItemsById.set(patch.itemId, patch.payload);
		const rowIds = this.#rowIdsByFileId.get(patch.itemId);
		if (rowIds === undefined) return { evaluatedRowCount: 0, queryStatusChanged: false };
		const rows = [...rowIds].flatMap((rowId): readonly FileTreeRow[] => {
			const row = this.#rawRowsById.get(rowId);
			return row === undefined ? [] : [row];
		});
		return this.#reevaluatePublishedQueryRows(rows, projectedOperations);
	}

	#reevaluatePublishedQueryRows(
		rows: Iterable<FileTreeRow>,
		projectedOperations: FileTreeOperation[],
	): { readonly evaluatedRowCount: number; readonly queryStatusChanged: boolean } {
		let evaluatedRowCount = 0;
		let projectedRowCountChanged = false;
		for (const row of rows) {
			const wasProjected = this.#projectedRowsById.has(row.rowId);
			this.#applyPublishedQueryRowTransition(row, projectedOperations);
			projectedRowCountChanged =
				wasProjected !== this.#projectedRowsById.has(row.rowId) || projectedRowCountChanged;
			evaluatedRowCount += 1;
		}
		return { evaluatedRowCount, queryStatusChanged: projectedRowCountChanged };
	}

	#applyPublishedQueryRowTransition(row: FileTreeRow, operations: FileTreeOperation[]): void {
		const previousProjectedRow = this.#projectedRowsById.get(row.rowId);
		if (
			!this.#rowMatchesQuery(
				row,
				this.#publishedQuery,
				this.#publishedQueryPattern,
				this.#publishedQuerySearchError,
			)
		) {
			if (previousProjectedRow !== undefined) {
				this.#projectedRowsById.delete(row.rowId);
				operations.push({
					operation: 'remove',
					path: previousProjectedRow.path,
					rowId: previousProjectedRow.rowId,
				});
			}
			return;
		}
		this.#projectedRowsById.set(row.rowId, row);
		if (previousProjectedRow === undefined || !fileTreeRowsEqual(previousProjectedRow, row)) {
			operations.push({ operation: 'upsert', row });
		}
	}

	#rowMatchesQuery(
		row: FileTreeRow,
		query: BridgeWorkerFileQuery,
		queryPattern: RegExp | null,
		querySearchError: string | null,
	): boolean {
		if (querySearchError !== null) return false;
		if (queryPattern !== null) {
			if (row.isDirectory || !queryPattern.test(row.path)) return false;
		}
		if (row.isDirectory) return query.filterMode === 'all';
		if (query.filterMode === 'all') return true;
		const availability = row.fileId === null ? undefined : this.#fileItemsById.get(row.fileId);
		if (query.filterMode === 'fetchable') {
			return availability?.availability.kind === 'available';
		}
		return (
			availability?.availability.kind === 'binary' ||
			availability?.availability.kind === 'unavailable'
		);
	}

	#indexRawRow(row: FileTreeRow): void {
		if (row.fileId === null) return;
		const rowIds = this.#rowIdsByFileId.get(row.fileId) ?? new Set<string>();
		rowIds.add(row.rowId);
		this.#rowIdsByFileId.set(row.fileId, rowIds);
	}

	#removeRawRow(row: FileTreeRow): void {
		this.#rawRowsById.delete(row.rowId);
		if (row.fileId === null) return;
		const rowIds = this.#rowIdsByFileId.get(row.fileId);
		rowIds?.delete(row.rowId);
		if (rowIds?.size === 0) this.#rowIdsByFileId.delete(row.fileId);
	}

	#publishedQueryStatusPatch(): BridgeWorkerFileDisplayPatch {
		return queryStatusPatch({
			projectedRowCount: this.#projectedRowsById.size,
			query: this.#publishedQuery,
			searchError: this.#publishedQuerySearchError,
			totalRowCount: this.#rawRowsById.size,
		});
	}
}

interface PendingFileQueryProjection {
	evaluatedRowCount: number;
	readonly generation: number;
	readonly nextProjectedRowsById: Map<string, FileTreeRow>;
	readonly operationBatches: BridgeWorkerFileDisplayPatch[];
	readonly pendingOperations: FileTreeOperation[];
	readonly publish: (result: BridgeCommWorkerFileQueryProjectionResult) => void;
	readonly query: BridgeWorkerFileQuery;
	rowIterator: Iterator<FileTreeRow>;
	readonly searchError: string | null;
	readonly searchPattern: RegExp | null;
}

export function applyBridgeCommWorkerFileQueryUpdateCommand(props: {
	readonly command: BridgeWorkerFileQueryUpdateCommand;
	readonly eventAuthority: BridgeCommWorkerFileDisplayEventAuthority;
	readonly getWorkerDerivationEpoch: () => number;
	readonly projection: BridgeCommWorkerFileQueryProjection;
	readonly publishMessages: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
}): readonly BridgeWorkerServerToMainMessage[] {
	props.projection.updateQuery({
		publish: (result): void => {
			if (result.queryTransactionId === null) return;
			props.publishMessages(
				props.eventAuthority.publishQueryTransaction({
					epoch: props.getWorkerDerivationEpoch(),
					patches: result.patches,
					transactionId: result.queryTransactionId,
				}),
			);
		},
		query: props.command.query,
	});
	return [];
}

function appendPendingFileTreeOperation(
	pendingQuery: PendingFileQueryProjection,
	operation: FileTreeOperation,
): void {
	pendingQuery.pendingOperations.push(operation);
	if (pendingQuery.pendingOperations.length === BRIDGE_WORKER_FILE_DISPLAY_PATCH_LIMIT) {
		flushPendingFileTreeOperations(pendingQuery);
	}
}

function flushPendingFileTreeOperations(pendingQuery: PendingFileQueryProjection): void {
	if (pendingQuery.pendingOperations.length === 0) return;
	pendingQuery.operationBatches.push({
		operation: 'batch',
		payload: { operations: pendingQuery.pendingOperations.splice(0) },
		slice: 'fileTree',
	});
}

function prependIteratorValue<TValue>(value: TValue, iterator: Iterator<TValue>): Iterator<TValue> {
	let pendingValue: TValue | undefined = value;
	return {
		next: (): IteratorResult<TValue> => {
			if (pendingValue !== undefined) {
				const nextValue = pendingValue;
				pendingValue = undefined;
				return { done: false, value: nextValue };
			}
			return iterator.next();
		},
	};
}

function queryStatusPatch(props: {
	readonly projectedRowCount: number;
	readonly query: BridgeWorkerFileQuery;
	readonly searchError: string | null;
	readonly totalRowCount: number;
}): BridgeWorkerFileDisplayPatch {
	const payload: BridgeWorkerFileQueryDisplayPayload = {
		...props.query,
		projectedRowCount: props.projectedRowCount,
		searchError: props.searchError,
		totalRowCount: props.totalRowCount,
	};
	return { operation: 'upsert', payload, slice: 'fileQuery' };
}

function changedFileQueryProjection(
	patches: readonly BridgeWorkerFileDisplayPatch[],
	evaluatedRowCount: number,
): BridgeCommWorkerFileQueryProjectionResult {
	return patches.length === 0
		? noFileQueryProjectionChange()
		: { evaluatedRowCount, patches, queryTransactionId: null };
}

function noFileQueryProjectionChange(): BridgeCommWorkerFileQueryProjectionResult {
	return { evaluatedRowCount: 0, patches: [], queryTransactionId: null };
}

function fileTreeOperationBatches(
	operations: readonly FileTreeOperation[],
): readonly BridgeWorkerFileDisplayPatch[] {
	const patches: BridgeWorkerFileDisplayPatch[] = [];
	for (
		let startIndex = 0;
		startIndex < operations.length;
		startIndex += BRIDGE_WORKER_FILE_DISPLAY_PATCH_LIMIT
	) {
		patches.push({
			operation: 'batch',
			payload: {
				operations: operations.slice(
					startIndex,
					startIndex + BRIDGE_WORKER_FILE_DISPLAY_PATCH_LIMIT,
				),
			},
			slice: 'fileTree',
		});
	}
	return patches;
}

function fileQueriesEqual(left: BridgeWorkerFileQuery, right: BridgeWorkerFileQuery): boolean {
	return (
		left.filterMode === right.filterMode &&
		left.searchMode === right.searchMode &&
		left.searchText === right.searchText
	);
}

function fileTreeRowsEqual(left: FileTreeRow, right: FileTreeRow): boolean {
	return (
		left.changeStatus === right.changeStatus &&
		left.depth === right.depth &&
		left.fileId === right.fileId &&
		left.isDirectory === right.isDirectory &&
		left.lineCount === right.lineCount &&
		left.name === right.name &&
		left.parentPath === right.parentPath &&
		left.path === right.path &&
		left.projectionIndex === right.projectionIndex &&
		left.rowId === right.rowId &&
		left.sizeBytes === right.sizeBytes
	);
}

function scheduleFileQueryMacrotask(runChunk: () => void): void {
	setTimeout(runChunk, 0);
}

function ignoreQueryChunk(_evaluatedRowCount: number): void {}

function assertNeverFileDisplayPatch(patch: never): never {
	throw new Error(`Unhandled File display patch: ${JSON.stringify(patch)}`);
}
