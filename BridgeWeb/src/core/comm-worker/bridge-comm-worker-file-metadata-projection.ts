import type { BridgeCommWorkerRow } from './bridge-comm-worker-store.js';
import type { BridgeProductFileContentDescriptor } from './bridge-product-content-contracts.js';
import type { BridgeProductFileSourceIdentity } from './bridge-product-file-contracts.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import {
	bridgeWorkerFileViewContentMetadataSchema,
	type BridgeWorkerFileDisplayPatch,
	type BridgeWorkerFileViewContentMetadata,
} from './bridge-worker-contracts.js';

type FileMetadataEvent = BridgeProductSubscriptionEvent<'file.metadata'>;
type FileDescriptorReadyEvent = Extract<
	FileMetadataEvent,
	{ readonly eventKind: 'file.descriptorReady' }
>;
type FileTreeRow = Extract<
	FileMetadataEvent,
	{ readonly eventKind: 'file.treeWindow' }
>['rows'][number];
type FileTreeDisplayPatch = Extract<
	BridgeWorkerFileDisplayPatch,
	{ readonly operation: 'batch'; readonly slice: 'fileTree' }
>;
type FileTreeDisplayOperation = FileTreeDisplayPatch['payload']['operations'][number];

const bridgeCommWorkerFileDisplayOperationChunkSize = 256;

export interface BridgeCommWorkerFileViewContentRequest {
	readonly contentDescriptor: BridgeProductFileContentDescriptor;
	readonly itemId: string;
	readonly language: string | null;
	readonly path: string;
	readonly sizeBytes: number;
}

export interface BridgeCommWorkerFileMetadataSnapshot {
	readonly contentItems: readonly BridgeWorkerFileViewContentMetadata[];
	readonly contentRequests: readonly BridgeCommWorkerFileViewContentRequest[];
	readonly rows: readonly BridgeCommWorkerRow[];
	readonly treeRows: readonly FileTreeRow[];
}

export interface BridgeCommWorkerFileViewRuntimePathUpsert {
	readonly itemId: string;
	readonly path: string;
}

export type BridgeCommWorkerFileViewRuntimeMutation =
	| {
			readonly contentRequestUpserts: readonly BridgeCommWorkerFileViewContentRequest[];
			readonly contentUpserts: readonly BridgeWorkerFileViewContentMetadata[];
			readonly filePathUpserts: readonly BridgeCommWorkerFileViewRuntimePathUpsert[];
			readonly kind: 'reset';
			readonly rowUpserts: readonly BridgeCommWorkerRow[];
	  }
	| {
			readonly contentRemovals: readonly string[];
			readonly contentRequestRemovals: readonly string[];
			readonly contentRequestUpserts: readonly BridgeCommWorkerFileViewContentRequest[];
			readonly contentUpserts: readonly BridgeWorkerFileViewContentMetadata[];
			readonly filePathRemovals: readonly string[];
			readonly filePathUpserts: readonly BridgeCommWorkerFileViewRuntimePathUpsert[];
			readonly kind: 'delta';
			readonly resetContent?: true;
			readonly rowRemovals: readonly string[];
			readonly rowUpserts: readonly BridgeCommWorkerRow[];
	  };

export interface BridgeCommWorkerFileMetadataApplyResult {
	readonly patches: readonly BridgeWorkerFileDisplayPatch[];
	readonly projectionRevision: number;
	readonly runtimeMutation: BridgeCommWorkerFileViewRuntimeMutation | null;
}

export interface BridgeCommWorkerFileMetadataProjectionProps {
	readonly recordVisitedMember?: () => void;
}

export class BridgeCommWorkerFileMetadataProjection {
	readonly #childIndexesByParentPath = new Map<string, Set<number>>();
	readonly #descriptorsByFileId = new Map<string, FileDescriptorReadyEvent>();
	readonly #recordVisitedMember: () => void;
	#projectionRevision = 0;
	#source: BridgeProductFileSourceIdentity | null = null;
	readonly #treeIndexByPath = new Map<string, number>();
	readonly #treeIndexByRowId = new Map<string, number>();
	#treeRows: Array<FileTreeRow | null | undefined> = [];

	constructor(props: BridgeCommWorkerFileMetadataProjectionProps = {}) {
		this.#recordVisitedMember = props.recordVisitedMember ?? ignoreVisitedProjectionMember;
	}

	apply(event: FileMetadataEvent): BridgeCommWorkerFileMetadataApplyResult {
		let patches: readonly BridgeWorkerFileDisplayPatch[];
		let runtimeMutation: BridgeCommWorkerFileViewRuntimeMutation | null;
		if (event.eventKind === 'file.sourceAccepted') {
			this.#source = event.source;
			this.#treeRows = [];
			this.#childIndexesByParentPath.clear();
			this.#treeIndexByPath.clear();
			this.#treeIndexByRowId.clear();
			this.#descriptorsByFileId.clear();
			patches = fileSourceResetDisplayPatches(event.source);
			runtimeMutation = emptyFileRuntimeResetMutation();
			return this.#applyResult(patches, runtimeMutation);
		}
		this.#assertCurrentSource(event.source);
		switch (event.eventKind) {
			case 'file.treeWindow': {
				const change = this.#applyTreeWindow(event);
				patches = [
					...fileTreeDisplayOperationBatches(change.displayOperations),
					...(event.finalWindow ? [fileTreeReplacementCommitDisplayPatch(event.source)] : []),
				];
				runtimeMutation = finalizeFileRuntimeDeltaMutation(change.runtimeMutation);
				break;
			}
			case 'file.treeDelta': {
				const change = this.#applyTreeDelta(event);
				patches = fileTreeDisplayOperationBatches(change.displayOperations);
				runtimeMutation = finalizeFileRuntimeDeltaMutation(change.runtimeMutation);
				break;
			}
			case 'file.statusPatch': {
				patches = this.#applyStatusPatch(event);
				runtimeMutation = null;
				break;
			}
			case 'file.descriptorReady': {
				this.#recordVisitedMember();
				const previousDescriptor = this.#descriptorsByFileId.get(event.fileId);
				if (
					previousDescriptor !== undefined &&
					fileDescriptorRuntimeFactsEqual(previousDescriptor, event)
				) {
					patches = [];
					runtimeMutation = null;
					break;
				}
				this.#descriptorsByFileId.set(event.fileId, event);
				patches = [fileItemDisplayUpsertPatch(event)];
				runtimeMutation = fileDescriptorRuntimeMutation(event);
				break;
			}
			case 'file.invalidated': {
				runtimeMutation = this.#applyInvalidation(event);
				patches = fileInvalidationDisplayPatches(event);
				break;
			}
			default:
				assertNeverFileMetadataEvent(event);
		}
		return this.#applyResult(patches, runtimeMutation);
	}

	snapshot(): BridgeCommWorkerFileMetadataSnapshot {
		const indexedTreeRows = this.#treeRows.flatMap((row, index) =>
			row === null || row === undefined ? [] : [{ index, row }],
		);
		const treeRows = indexedTreeRows.map(({ row }) => row);
		const rowIdByPath = new Map(treeRows.map((row) => [row.path, fileRuntimeRowId(row)]));
		const descriptorEvents = [...this.#descriptorsByFileId.values()].toSorted((left, right) =>
			left.path.localeCompare(right.path),
		);
		return {
			contentItems: descriptorEvents.map(fileContentMetadataFromDescriptor),
			contentRequests: descriptorEvents.flatMap(fileContentRequestFromDescriptor),
			rows: indexedTreeRows.map(({ index, row }) => ({
				id: fileRuntimeRowId(row),
				index,
				parentId: row.parentPath === null ? null : (rowIdByPath.get(row.parentPath) ?? null),
			})),
			treeRows,
		};
	}

	#applyTreeWindow(
		event: Extract<FileMetadataEvent, { readonly eventKind: 'file.treeWindow' }>,
	): FileProjectionTreeChange {
		const change = emptyFileProjectionTreeChange();
		for (const [offset, row] of event.rows.entries()) {
			this.#writeTreeRow(event.startIndex + offset, row, change);
		}
		if (event.finalWindow && event.totalRowCount !== null) {
			for (let index = event.totalRowCount; index < this.#treeRows.length; index += 1) {
				this.#removeTreeRow(index, change);
			}
			this.#treeRows.length = event.totalRowCount;
		}
		return change;
	}

	#applyTreeDelta(
		event: Extract<FileMetadataEvent, { readonly eventKind: 'file.treeDelta' }>,
	): FileProjectionTreeChange {
		const change = emptyFileProjectionTreeChange();
		for (const operation of event.operations) {
			if (operation.op === 'removeRows') {
				for (const path of operation.paths) {
					const index = this.#treeIndexByPath.get(path);
					if (index !== undefined) this.#removeTreeRow(index, change);
				}
				for (const rowId of operation.rowIds) {
					const index = this.#treeIndexByRowId.get(rowId);
					if (index !== undefined) this.#removeTreeRow(index, change);
				}
				continue;
			}
			for (const row of operation.rows) {
				const existingIndex =
					this.#treeIndexByRowId.get(row.rowId) ?? this.#treeIndexByPath.get(row.path);
				this.#writeTreeRow(existingIndex ?? this.#treeRows.length, row, change);
			}
		}
		return change;
	}

	#applyStatusPatch(
		event: Extract<FileMetadataEvent, { readonly eventKind: 'file.statusPatch' }>,
	): readonly BridgeWorkerFileDisplayPatch[] {
		const patch = event.patch;
		if (patch.patchKind !== 'path') return [fileStatusDisplayPatch(patch)];
		this.#recordVisitedMember();
		const rowIndex = this.#treeIndexByPath.get(patch.path);
		if (rowIndex === undefined) return [];
		const row = this.#treeRows[rowIndex];
		if (row === null || row === undefined || row.changeStatus === patch.status) return [];
		this.#treeRows[rowIndex] = { ...row, changeStatus: patch.status };
		return fileTreeDisplayOperationBatches([
			{
				operation: 'upsert',
				row: { ...this.#treeRows[rowIndex], projectionIndex: rowIndex },
			},
		]);
	}

	#applyInvalidation(
		event: Extract<FileMetadataEvent, { readonly eventKind: 'file.invalidated' }>,
	): BridgeCommWorkerFileViewRuntimeMutation | null {
		this.#recordVisitedMember();
		if (event.reason === 'sourceReset' && event.fileId === null) {
			this.#descriptorsByFileId.clear();
			this.#treeRows = [];
			this.#childIndexesByParentPath.clear();
			this.#treeIndexByPath.clear();
			this.#treeIndexByRowId.clear();
			const mutation = emptyFileRuntimeResetMutation();
			if (event.replacementDescriptor === null) return mutation;
			const replacement = descriptorReadyEventFromInvalidation(event.replacementDescriptor);
			this.#descriptorsByFileId.set(replacement.fileId, replacement);
			return appendDescriptorToResetMutation(mutation, replacement);
		}
		if (event.fileId === null) {
			this.#descriptorsByFileId.clear();
			const mutation = emptyFileRuntimeDeltaMutation();
			mutation.resetContent = true;
			if (event.replacementDescriptor === null) return mutation;
			const replacement = descriptorReadyEventFromInvalidation(event.replacementDescriptor);
			this.#descriptorsByFileId.set(replacement.fileId, replacement);
			appendDescriptorToDeltaMutation(mutation, replacement);
			return mutation;
		}
		const mutation = emptyFileRuntimeDeltaMutation();
		this.#descriptorsByFileId.delete(event.fileId);
		mutation.contentRemovals.push(event.fileId);
		mutation.contentRequestRemovals.push(event.fileId);
		if (event.replacementDescriptor !== null) {
			const replacement = descriptorReadyEventFromInvalidation(event.replacementDescriptor);
			this.#descriptorsByFileId.set(replacement.fileId, replacement);
			appendDescriptorToDeltaMutation(mutation, replacement);
		}
		return finalizeFileRuntimeDeltaMutation(mutation);
	}

	#writeTreeRow(index: number, row: FileTreeRow, change: FileProjectionTreeChange): void {
		this.#recordVisitedMember();
		const conflictingIndex =
			this.#treeIndexByRowId.get(row.rowId) ?? this.#treeIndexByPath.get(row.path);
		if (conflictingIndex !== undefined && conflictingIndex !== index) {
			this.#removeTreeRow(conflictingIndex, change);
		}
		const previousRow = this.#treeRows[index];
		if (previousRow !== null && previousRow !== undefined && fileTreeRowsEqual(previousRow, row)) {
			return;
		}
		const previousRuntimeRow =
			previousRow === null || previousRow === undefined
				? null
				: this.#runtimeRow(previousRow, index);
		if (previousRow !== null && previousRow !== undefined) {
			this.#detachTreeRow(previousRow, index);
			if (previousRow.rowId !== row.rowId || previousRow.path !== row.path) {
				change.displayOperations.push({
					operation: 'remove',
					path: previousRow.path,
					rowId: previousRow.rowId,
				});
			}
			if (fileRuntimeRowId(previousRow) !== fileRuntimeRowId(row)) {
				change.runtimeMutation.rowRemovals.push(fileRuntimeRowId(previousRow));
			}
			if (
				previousRow.fileId !== null &&
				(previousRow.fileId !== row.fileId || previousRow.path !== row.path)
			) {
				change.runtimeMutation.filePathRemovals.push(previousRow.fileId);
			}
		}
		this.#treeRows[index] = row;
		this.#treeIndexByPath.set(row.path, index);
		this.#treeIndexByRowId.set(row.rowId, index);
		if (row.parentPath !== null) {
			const childIndexes = this.#childIndexesByParentPath.get(row.parentPath) ?? new Set<number>();
			childIndexes.add(index);
			this.#childIndexesByParentPath.set(row.parentPath, childIndexes);
		}
		change.displayOperations.push({ operation: 'upsert', row: { ...row, projectionIndex: index } });
		const nextRuntimeRow = this.#runtimeRow(row, index);
		if (previousRuntimeRow === null || !fileRuntimeRowsEqual(previousRuntimeRow, nextRuntimeRow)) {
			change.runtimeMutation.rowUpserts.push(nextRuntimeRow);
		}
		if (
			row.fileId !== null &&
			(previousRow === null ||
				previousRow === undefined ||
				previousRow.fileId !== row.fileId ||
				previousRow.path !== row.path)
		) {
			change.runtimeMutation.filePathUpserts.push({ itemId: row.fileId, path: row.path });
		}
		if (previousRow !== null && previousRow !== undefined) {
			this.#appendDirectChildRuntimeRepairs(previousRow.path, index, change);
		}
		this.#appendDirectChildRuntimeRepairs(row.path, index, change);
	}

	#removeTreeRow(index: number, change: FileProjectionTreeChange): void {
		const row = this.#treeRows[index];
		if (row === null || row === undefined) return;
		this.#recordVisitedMember();
		this.#detachTreeRow(row, index);
		this.#treeRows[index] = null;
		change.displayOperations.push({ operation: 'remove', path: row.path, rowId: row.rowId });
		appendRuntimeRowRemoval(change.runtimeMutation, row);
		this.#appendDirectChildRuntimeRepairs(row.path, index, change);
	}

	#detachTreeRow(row: FileTreeRow, index: number): void {
		if (this.#treeIndexByPath.get(row.path) === index) this.#treeIndexByPath.delete(row.path);
		if (this.#treeIndexByRowId.get(row.rowId) === index) this.#treeIndexByRowId.delete(row.rowId);
		if (row.parentPath !== null) {
			const childIndexes = this.#childIndexesByParentPath.get(row.parentPath);
			childIndexes?.delete(index);
			if (childIndexes?.size === 0) this.#childIndexesByParentPath.delete(row.parentPath);
		}
	}

	#appendDirectChildRuntimeRepairs(
		parentPath: string,
		parentIndex: number,
		change: FileProjectionTreeChange,
	): void {
		const childIndexes = this.#childIndexesByParentPath.get(parentPath);
		if (childIndexes === undefined) return;
		for (const childIndex of childIndexes) {
			if (childIndex === parentIndex) continue;
			const childRow = this.#treeRows[childIndex];
			if (childRow === null || childRow === undefined) continue;
			const childRuntimeId = fileRuntimeRowId(childRow);
			this.#recordVisitedMember();
			const repairedRow = this.#runtimeRow(childRow, childIndex);
			const pendingIndex = change.repairedRuntimeRowIndexById.get(childRuntimeId);
			if (pendingIndex === undefined) {
				change.repairedRuntimeRowIndexById.set(
					childRuntimeId,
					change.runtimeMutation.rowUpserts.length,
				);
				change.runtimeMutation.rowUpserts.push(repairedRow);
			} else {
				change.runtimeMutation.rowUpserts[pendingIndex] = repairedRow;
			}
		}
	}

	#runtimeRow(row: FileTreeRow, index: number): BridgeCommWorkerRow {
		const parentIndex =
			row.parentPath === null ? undefined : this.#treeIndexByPath.get(row.parentPath);
		const parentRow = parentIndex === undefined ? null : (this.#treeRows[parentIndex] ?? null);
		return {
			id: fileRuntimeRowId(row),
			index,
			parentId: parentRow === null ? null : fileRuntimeRowId(parentRow),
		};
	}

	#assertCurrentSource(source: BridgeProductFileSourceIdentity): void {
		if (this.#source === null || !fileSourceIdentitiesEqual(this.#source, source)) {
			throw new Error('Bridge File metadata event does not match the active worker source.');
		}
	}

	#applyResult(
		patches: readonly BridgeWorkerFileDisplayPatch[],
		runtimeMutation: BridgeCommWorkerFileViewRuntimeMutation | null,
	): BridgeCommWorkerFileMetadataApplyResult {
		this.#projectionRevision += 1;
		return {
			patches,
			projectionRevision: this.#projectionRevision,
			runtimeMutation,
		};
	}
}

function fileSourceResetDisplayPatches(
	source: BridgeProductFileSourceIdentity,
): readonly BridgeWorkerFileDisplayPatch[] {
	return [
		{
			operation: 'reset',
			payload: {
				sourceGeneration: source.subscriptionGeneration,
				sourceId: source.sourceId,
			},
			slice: 'fileTree',
		},
		{ operation: 'reset', slice: 'fileItem' },
		{ operation: 'reset', slice: 'fileStatus' },
	];
}

function fileTreeReplacementCommitDisplayPatch(
	source: BridgeProductFileSourceIdentity,
): BridgeWorkerFileDisplayPatch {
	return {
		operation: 'replacementCommit',
		payload: {
			sourceGeneration: source.subscriptionGeneration,
			sourceId: source.sourceId,
		},
		slice: 'fileTree',
	};
}

interface MutableBridgeCommWorkerFileViewRuntimeDeltaMutation {
	readonly contentRemovals: string[];
	readonly contentRequestRemovals: string[];
	readonly contentRequestUpserts: BridgeCommWorkerFileViewContentRequest[];
	readonly contentUpserts: BridgeWorkerFileViewContentMetadata[];
	readonly filePathRemovals: string[];
	readonly filePathUpserts: BridgeCommWorkerFileViewRuntimePathUpsert[];
	readonly kind: 'delta';
	resetContent?: true;
	readonly rowRemovals: string[];
	readonly rowUpserts: BridgeCommWorkerRow[];
}

interface FileProjectionTreeChange {
	readonly displayOperations: FileTreeDisplayOperation[];
	readonly repairedRuntimeRowIndexById: Map<string, number>;
	readonly runtimeMutation: MutableBridgeCommWorkerFileViewRuntimeDeltaMutation;
}

function emptyFileProjectionTreeChange(): FileProjectionTreeChange {
	return {
		displayOperations: [],
		repairedRuntimeRowIndexById: new Map(),
		runtimeMutation: emptyFileRuntimeDeltaMutation(),
	};
}

function emptyFileRuntimeResetMutation(): Extract<
	BridgeCommWorkerFileViewRuntimeMutation,
	{ readonly kind: 'reset' }
> {
	return {
		contentRequestUpserts: [],
		contentUpserts: [],
		filePathUpserts: [],
		kind: 'reset',
		rowUpserts: [],
	};
}

function emptyFileRuntimeDeltaMutation(): MutableBridgeCommWorkerFileViewRuntimeDeltaMutation {
	return {
		contentRemovals: [],
		contentRequestRemovals: [],
		contentRequestUpserts: [],
		contentUpserts: [],
		filePathRemovals: [],
		filePathUpserts: [],
		kind: 'delta',
		rowRemovals: [],
		rowUpserts: [],
	};
}

function finalizeFileRuntimeDeltaMutation(
	mutation: MutableBridgeCommWorkerFileViewRuntimeDeltaMutation,
): BridgeCommWorkerFileViewRuntimeMutation | null {
	return mutation.resetContent === true ||
		mutation.contentRemovals.length > 0 ||
		mutation.contentRequestRemovals.length > 0 ||
		mutation.contentRequestUpserts.length > 0 ||
		mutation.contentUpserts.length > 0 ||
		mutation.filePathRemovals.length > 0 ||
		mutation.filePathUpserts.length > 0 ||
		mutation.rowRemovals.length > 0 ||
		mutation.rowUpserts.length > 0
		? mutation
		: null;
}

function appendRuntimeRowRemoval(
	mutation: MutableBridgeCommWorkerFileViewRuntimeDeltaMutation,
	row: FileTreeRow,
): void {
	mutation.rowRemovals.push(fileRuntimeRowId(row));
	if (row.fileId !== null) mutation.filePathRemovals.push(row.fileId);
}

function fileTreeDisplayOperationBatches(
	operations: readonly FileTreeDisplayOperation[],
): readonly FileTreeDisplayPatch[] {
	if (operations.length === 0) return [];
	const patches: FileTreeDisplayPatch[] = [];
	for (
		let startIndex = 0;
		startIndex < operations.length;
		startIndex += bridgeCommWorkerFileDisplayOperationChunkSize
	) {
		patches.push({
			operation: 'batch',
			payload: {
				operations: operations.slice(
					startIndex,
					startIndex + bridgeCommWorkerFileDisplayOperationChunkSize,
				),
			},
			slice: 'fileTree',
		});
	}
	return patches;
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
		left.rowId === right.rowId &&
		left.sizeBytes === right.sizeBytes
	);
}

function fileRuntimeRowsEqual(left: BridgeCommWorkerRow, right: BridgeCommWorkerRow): boolean {
	return left.id === right.id && left.index === right.index && left.parentId === right.parentId;
}

function fileStatusDisplayPatch(
	patch: Extract<FileMetadataEvent, { readonly eventKind: 'file.statusPatch' }>['patch'],
): BridgeWorkerFileDisplayPatch {
	if (patch.patchKind === 'invalidated') {
		return { operation: 'upsert', payload: { state: 'stale' }, slice: 'fileStatus' };
	}
	if (patch.patchKind === 'summary') {
		return {
			operation: 'upsert',
			payload: {
				ahead: patch.ahead,
				behind: patch.behind,
				branchName: patch.branchName,
				staged: patch.staged,
				state: 'ready',
				unstaged: patch.unstaged,
				untracked: patch.untracked,
			},
			slice: 'fileStatus',
		};
	}
	throw new Error('Path File status patches are projected through the File tree.');
}

function fileItemDisplayUpsertPatch(
	descriptor: FileDescriptorReadyEvent,
): BridgeWorkerFileDisplayPatch {
	return {
		itemId: descriptor.fileId,
		operation: 'upsert',
		payload: {
			availability: fileItemDisplayAvailability(descriptor),
			displayPath: descriptor.path,
			endsMidLine: descriptor.endsMidLine,
			endsWithNewline: descriptor.endsWithNewline,
			extent: fileItemDisplayExtent(descriptor),
			fileExtension: descriptor.fileExtension,
			language: descriptor.language,
			payloadByteCount: descriptor.payloadByteCount,
			payloadLineCount: descriptor.payloadLineCount,
			rowId: descriptor.rowId,
			sizeBytes: descriptor.sizeBytes,
			totalLineCount: descriptor.totalLineCount,
			truncationKind: descriptor.truncationKind,
		},
		slice: 'fileItem',
	};
}

function fileItemDisplayAvailability(
	descriptor: FileDescriptorReadyEvent,
): Extract<
	BridgeWorkerFileDisplayPatch,
	{ readonly operation: 'upsert'; readonly slice: 'fileItem' }
>['payload']['availability'] {
	if (descriptor.availability.availabilityKind === 'available') return { kind: 'available' };
	if (descriptor.availability.availabilityKind === 'binary') return { kind: 'binary' };
	return { kind: 'unavailable', reason: descriptor.availability.reason };
}

function fileItemDisplayExtent(
	descriptor: FileDescriptorReadyEvent,
): Extract<
	BridgeWorkerFileDisplayPatch,
	{ readonly operation: 'upsert'; readonly slice: 'fileItem' }
>['payload']['extent'] {
	if (descriptor.virtualizedExtentKind === 'unavailable') return { kind: 'unavailable' };
	if (descriptor.virtualizedExtentKind === 'previewBounded') return { kind: 'previewBounded' };
	if (descriptor.virtualizedExtentKind === 'exactLineCount' && descriptor.totalLineCount !== null) {
		return { kind: 'exactLineCount', lineCount: descriptor.totalLineCount };
	}
	throw new Error('Bridge File metadata descriptor carries an unsupported display extent.');
}

function fileInvalidationDisplayPatches(
	event: Extract<FileMetadataEvent, { readonly eventKind: 'file.invalidated' }>,
): readonly BridgeWorkerFileDisplayPatch[] {
	if (event.reason === 'sourceReset' && event.fileId === null) {
		return [
			...fileSourceResetDisplayPatches(event.source),
			...(event.replacementDescriptor === null
				? []
				: [
						fileItemDisplayUpsertPatch({
							...event.replacementDescriptor,
							eventKind: 'file.descriptorReady',
						}),
					]),
		];
	}
	if (event.fileId === null) {
		return [
			{ operation: 'reset', slice: 'fileItem' },
			...(event.replacementDescriptor === null
				? []
				: [
						fileItemDisplayUpsertPatch({
							...event.replacementDescriptor,
							eventKind: 'file.descriptorReady',
						}),
					]),
		];
	}
	if (event.replacementDescriptor === null) {
		return [{ itemId: event.fileId, operation: 'delete', slice: 'fileItem' }];
	}
	const replacementPatch = fileItemDisplayUpsertPatch({
		...event.replacementDescriptor,
		eventKind: 'file.descriptorReady',
	});
	return event.replacementDescriptor.fileId === event.fileId
		? [replacementPatch]
		: [{ itemId: event.fileId, operation: 'delete', slice: 'fileItem' }, replacementPatch];
}

function fileContentMetadataFromDescriptor(
	descriptor: FileDescriptorReadyEvent,
): BridgeWorkerFileViewContentMetadata {
	const contentDescriptor =
		descriptor.availability.availabilityKind === 'available'
			? descriptor.availability.contentDescriptor
			: null;
	const descriptorId =
		contentDescriptor?.descriptorId ??
		`unavailable:${descriptor.source.sourceId}:${descriptor.fileId}`;
	const contentHash = contentDescriptor?.expectedSha256 ?? null;
	return bridgeWorkerFileViewContentMetadataSchema.parse({
		cacheKey: `file-content:${descriptorId}:${contentHash ?? 'unknown'}`,
		canFetchContent: contentDescriptor !== null,
		...(contentHash === null ? {} : { contentHash }),
		descriptorId,
		encoding: descriptor.encoding,
		endsMidLine: descriptor.endsMidLine,
		endsWithNewline: descriptor.endsWithNewline,
		isBinary: descriptor.availability.availabilityKind === 'binary',
		itemId: descriptor.fileId,
		language: descriptor.language,
		metadataKind: 'fileView',
		path: descriptor.path,
		payloadByteCount: descriptor.payloadByteCount,
		payloadLineCount: descriptor.payloadLineCount,
		sizeBytes: descriptor.sizeBytes,
		totalLineCount: descriptor.totalLineCount,
		truncationKind: descriptor.truncationKind,
		virtualizedExtentKind: descriptor.virtualizedExtentKind,
	});
}

function fileContentRequestFromDescriptor(
	descriptor: FileDescriptorReadyEvent,
): readonly BridgeCommWorkerFileViewContentRequest[] {
	if (descriptor.availability.availabilityKind !== 'available') return [];
	return [
		{
			contentDescriptor: descriptor.availability.contentDescriptor,
			itemId: descriptor.fileId,
			language: descriptor.language,
			path: descriptor.path,
			sizeBytes: descriptor.sizeBytes,
		},
	];
}

function fileDescriptorRuntimeMutation(
	descriptor: FileDescriptorReadyEvent,
): BridgeCommWorkerFileViewRuntimeMutation {
	const mutation = emptyFileRuntimeDeltaMutation();
	appendDescriptorToDeltaMutation(mutation, descriptor);
	return mutation;
}

function appendDescriptorToDeltaMutation(
	mutation: MutableBridgeCommWorkerFileViewRuntimeDeltaMutation,
	descriptor: FileDescriptorReadyEvent,
): void {
	mutation.contentUpserts.push(fileContentMetadataFromDescriptor(descriptor));
	const requests = fileContentRequestFromDescriptor(descriptor);
	if (requests.length === 0) {
		mutation.contentRequestRemovals.push(descriptor.fileId);
	} else {
		mutation.contentRequestUpserts.push(...requests);
	}
}

function appendDescriptorToResetMutation(
	mutation: Extract<BridgeCommWorkerFileViewRuntimeMutation, { readonly kind: 'reset' }>,
	descriptor: FileDescriptorReadyEvent,
): BridgeCommWorkerFileViewRuntimeMutation {
	return {
		...mutation,
		contentRequestUpserts: fileContentRequestFromDescriptor(descriptor),
		contentUpserts: [fileContentMetadataFromDescriptor(descriptor)],
	};
}

function descriptorReadyEventFromInvalidation(
	descriptor: NonNullable<
		Extract<FileMetadataEvent, { readonly eventKind: 'file.invalidated' }>['replacementDescriptor']
	>,
): FileDescriptorReadyEvent {
	return { ...descriptor, eventKind: 'file.descriptorReady' };
}

function fileDescriptorRuntimeFactsEqual(
	left: FileDescriptorReadyEvent,
	right: FileDescriptorReadyEvent,
): boolean {
	const leftMetadata = fileContentMetadataFromDescriptor(left);
	const rightMetadata = fileContentMetadataFromDescriptor(right);
	if (!fileContentMetadataEqual(leftMetadata, rightMetadata)) return false;
	const leftRequest = fileContentRequestFromDescriptor(left)[0] ?? null;
	const rightRequest = fileContentRequestFromDescriptor(right)[0] ?? null;
	return fileContentRequestsEqual(leftRequest, rightRequest);
}

function fileContentMetadataEqual(
	left: BridgeWorkerFileViewContentMetadata,
	right: BridgeWorkerFileViewContentMetadata,
): boolean {
	return (
		left.cacheKey === right.cacheKey &&
		left.canFetchContent === right.canFetchContent &&
		(left.contentHash ?? null) === (right.contentHash ?? null) &&
		left.descriptorId === right.descriptorId &&
		left.encoding === right.encoding &&
		left.endsMidLine === right.endsMidLine &&
		left.endsWithNewline === right.endsWithNewline &&
		left.isBinary === right.isBinary &&
		left.itemId === right.itemId &&
		left.language === right.language &&
		left.path === right.path &&
		left.payloadByteCount === right.payloadByteCount &&
		left.payloadLineCount === right.payloadLineCount &&
		left.sizeBytes === right.sizeBytes &&
		left.totalLineCount === right.totalLineCount &&
		left.truncationKind === right.truncationKind &&
		left.virtualizedExtentKind === right.virtualizedExtentKind
	);
}

function fileContentRequestsEqual(
	left: BridgeCommWorkerFileViewContentRequest | null,
	right: BridgeCommWorkerFileViewContentRequest | null,
): boolean {
	if (left === null || right === null) return left === right;
	return (
		left.itemId === right.itemId &&
		left.language === right.language &&
		left.path === right.path &&
		left.sizeBytes === right.sizeBytes &&
		left.contentDescriptor.descriptorId === right.contentDescriptor.descriptorId &&
		left.contentDescriptor.expectedSha256 === right.contentDescriptor.expectedSha256 &&
		left.contentDescriptor.source.sourceCursor === right.contentDescriptor.source.sourceCursor &&
		left.contentDescriptor.source.subscriptionGeneration ===
			right.contentDescriptor.source.subscriptionGeneration
	);
}

function fileRuntimeRowId(row: FileTreeRow): string {
	return row.fileId ?? row.rowId;
}

function fileSourceIdentitiesEqual(
	left: BridgeProductFileSourceIdentity,
	right: BridgeProductFileSourceIdentity,
): boolean {
	return (
		left.repoId === right.repoId &&
		left.rootRevisionToken === right.rootRevisionToken &&
		left.sourceCursor === right.sourceCursor &&
		left.sourceId === right.sourceId &&
		left.subscriptionGeneration === right.subscriptionGeneration &&
		left.worktreeId === right.worktreeId
	);
}

function assertNeverFileMetadataEvent(event: never): never {
	throw new Error(`Unhandled Bridge File metadata event: ${JSON.stringify(event)}`);
}

function ignoreVisitedProjectionMember(): void {}
