import type { FileTreeBatchOperation, FileTreeItemHandle } from '@pierre/trees';

import type { BridgeMainFileTreePatchStreamEntry } from '../core/comm-worker/bridge-main-file-display-patch-applier.js';

export interface BridgeFileViewerPatchableTreeModel {
	readonly batch: (operations: readonly FileTreeBatchOperation[]) => void;
	readonly getItem: (path: string) => FileTreeItemHandle | null;
	readonly resetPaths: (paths: readonly string[]) => void;
}

export interface BridgeFileViewerTreePatchTurnLimits {
	readonly maximumBytes: number;
	readonly maximumOperations: number;
}

export interface BridgeFileViewerTreePatchTurnResult {
	readonly blockedOnProjection: boolean;
	readonly hasPendingWork: boolean;
	readonly processedBytes: number;
	readonly processedOperations: number;
}

export interface BridgeFileViewerTreePatchCoordinator {
	readonly advanceNextTurn: (
		limits?: BridgeFileViewerTreePatchTurnLimits,
		isPathReady?: (path: string) => boolean,
	) => BridgeFileViewerTreePatchTurnResult;
	readonly applyEntry: (
		entry: BridgeMainFileTreePatchStreamEntry,
	) => BridgeFileViewerTreePatchTurnResult;
	readonly enqueueEntry: (entry: BridgeMainFileTreePatchStreamEntry) => void;
	readonly hasPendingWork: () => boolean;
}

export const bridgeFileViewerTreePatchTurnLimits = {
	maximumBytes: 64 * 1024,
	maximumOperations: 128,
} satisfies BridgeFileViewerTreePatchTurnLimits;

const utf8ByteEncoder = new TextEncoder();

interface PendingEntry {
	readonly entry: BridgeMainFileTreePatchStreamEntry;
	next: PendingEntry | null;
	operationIndex: number;
}

interface StagingTransaction {
	readonly paths: Set<string>;
	readonly transactionId: string;
}

interface PendingPathRemoval {
	readonly descendantPrefix: string;
	readonly pathSets: readonly Set<string>[];
	currentPath: string | null;
	iterator: IterableIterator<string> | null;
	pathSetIndex: number;
}

type ReplacementMode = 'clear' | 'query' | 'source';
type ReplacementPhase =
	| 'indexCommittedPaths'
	| 'indexTargetPaths'
	| 'deriveRemovals'
	| 'deriveAdditions'
	| 'validateOperations'
	| 'applyOperations'
	| 'expandDirectories'
	| 'complete';

interface PendingReplacement {
	readonly committedPaths: ReadonlySet<string>;
	readonly committedAndAncestors: Set<string>;
	readonly expandDirectories: boolean;
	readonly mode: ReplacementMode;
	readonly operations: FileTreeBatchOperation[];
	readonly removedRoots: Set<string>;
	readonly targetAndAncestors: Set<string>;
	readonly targetPaths: Set<string>;
	committedPathIterator: IterableIterator<string> | null;
	currentPath: string | null;
	expansionPathIterator: IterableIterator<string> | null;
	operationIndex: number;
	validationIndex: number;
	phase: ReplacementPhase;
	targetPathIterator: IterableIterator<string> | null;
	appliedOperationCount: number;
}

interface TurnWorkItem {
	readonly byteLength: number;
	readonly modelOperation?: FileTreeBatchOperation;
	readonly requiredPath?: string;
	readonly apply: () => void;
}

export function createBridgeFileViewerTreePatchCoordinator(props: {
	readonly initialPaths?: readonly string[];
	readonly model: BridgeFileViewerPatchableTreeModel;
}): BridgeFileViewerTreePatchCoordinator {
	let committedPaths = new Set(props.initialPaths ?? []);
	let replacementPublishesIncrementally = false;
	let replacementResetPending = false;
	let replacementPaths: Set<string> | null = null;
	let stagingTransaction: StagingTransaction | null = null;
	let pendingPathRemoval: PendingPathRemoval | null = null;
	let pendingReplacement: PendingReplacement | null = null;
	let pendingEntryHead: PendingEntry | null = null;
	let pendingEntryTail: PendingEntry | null = null;
	let mostRecentQueuedQueryId: string | null = null;
	const supersededQueryIds = new Set<string>();

	const hasPendingWork = (): boolean =>
		pendingEntryHead !== null || pendingPathRemoval !== null || pendingReplacement !== null;

	const enqueueEntry = (entry: BridgeMainFileTreePatchStreamEntry): void => {
		if (entry.kind === 'queryBegin') {
			if (mostRecentQueuedQueryId !== null && mostRecentQueuedQueryId !== entry.transactionId) {
				supersededQueryIds.add(mostRecentQueuedQueryId);
				if (stagingTransaction?.transactionId === mostRecentQueuedQueryId) {
					stagingTransaction = null;
				}
			}
			if (pendingReplacement?.mode === 'query' && pendingReplacement.appliedOperationCount === 0) {
				pendingReplacement = null;
			}
			mostRecentQueuedQueryId = entry.transactionId;
		} else if (entry.kind === 'reset') {
			if (pendingReplacement?.mode === 'source' && pendingReplacement.appliedOperationCount === 0) {
				pendingReplacement = null;
			}
		} else if (
			entry.kind === 'clear' &&
			pendingReplacement !== null &&
			pendingReplacement.appliedOperationCount === 0
		) {
			pendingReplacement = null;
		}

		const pendingEntry: PendingEntry = { entry, next: null, operationIndex: 0 };
		if (pendingEntryTail === null) {
			pendingEntryHead = pendingEntry;
		} else {
			pendingEntryTail.next = pendingEntry;
		}
		pendingEntryTail = pendingEntry;
	};

	const applyEntry = (
		entry: BridgeMainFileTreePatchStreamEntry,
	): BridgeFileViewerTreePatchTurnResult => {
		enqueueEntry(entry);
		return advanceNextTurn();
	};

	const advanceNextTurn = (
		limits: BridgeFileViewerTreePatchTurnLimits = bridgeFileViewerTreePatchTurnLimits,
		isPathReady: (path: string) => boolean = (): boolean => true,
	): BridgeFileViewerTreePatchTurnResult => {
		validateTurnLimits(limits);
		let processedOperations = 0;
		let processedBytes = 0;
		const modelOperations: FileTreeBatchOperation[] = [];
		let mustPublishBeforeExpansion = false;
		let blockedOnProjection = false;

		const canProcess = (byteLength: number): boolean => {
			if (byteLength > limits.maximumBytes) {
				throw new RangeError('One File tree work item exceeds the per-turn byte limit.');
			}
			return (
				processedOperations < limits.maximumOperations &&
				processedBytes + byteLength <= limits.maximumBytes
			);
		};
		const recordWork = (byteLength: number): void => {
			processedOperations += 1;
			processedBytes += byteLength;
		};

		while (
			processedOperations < limits.maximumOperations &&
			processedBytes < limits.maximumBytes &&
			!mustPublishBeforeExpansion
		) {
			if (pendingPathRemoval !== null) {
				const pathRemovalStep = nextPathRemovalStep(pendingPathRemoval);
				if (pathRemovalStep === null) {
					pendingPathRemoval = null;
					continue;
				}
				if (!canProcess(pathRemovalStep.byteLength)) break;
				pathRemovalStep.apply();
				recordWork(pathRemovalStep.byteLength);
				continue;
			}

			if (pendingReplacement !== null) {
				const replacementStep = nextReplacementStep(pendingReplacement, props.model);
				if (replacementStep === null) {
					if (pendingReplacement.phase === 'expandDirectories') {
						mustPublishBeforeExpansion = true;
						continue;
					}
					completeReplacement(pendingReplacement);
					continue;
				}
				if (!canProcess(replacementStep.byteLength)) break;
				if (
					replacementStep.requiredPath !== undefined &&
					!isPathReady(replacementStep.requiredPath)
				) {
					blockedOnProjection = true;
					break;
				}
				if (replacementStep.modelOperation !== undefined) {
					modelOperations.push(replacementStep.modelOperation);
				}
				replacementStep.apply();
				recordWork(replacementStep.byteLength);
				continue;
			}

			const pendingEntry = pendingEntryHead;
			if (pendingEntry === null) break;
			const { entry } = pendingEntry;
			const transactionId = queryTransactionId(entry);
			if (transactionId !== null && supersededQueryIds.has(transactionId)) {
				const byteLength = utf8ByteLength(transactionId);
				if (!canProcess(byteLength)) break;
				if (entry.kind === 'queryCommit' || entry.kind === 'queryAbort') {
					supersededQueryIds.delete(transactionId);
				}
				if (stagingTransaction?.transactionId === transactionId) {
					stagingTransaction = null;
				}
				consumePendingEntry();
				recordWork(byteLength);
				continue;
			}

			if (entry.kind === 'delta' || entry.kind === 'queryBatch') {
				if (pendingEntry.operationIndex >= entry.operations.length) {
					const isEmptyEntry = pendingEntry.operationIndex === 0;
					const byteLength =
						isEmptyEntry && transactionId !== null ? utf8ByteLength(transactionId) : 0;
					if (isEmptyEntry && !canProcess(byteLength)) break;
					consumePendingEntry();
					if (isEmptyEntry) recordWork(byteLength);
					continue;
				}

				const operation = entry.operations[pendingEntry.operationIndex];
				if (operation === undefined) {
					throw new Error('File tree patch operation index was out of bounds.');
				}
				const requiredPath = requiredFileTreePath(operation);
				if (requiredPath !== null && !isPathReady(requiredPath)) {
					blockedOnProjection = true;
					break;
				}
				const byteLength = fileTreeOperationByteLength(operation);
				if (!canProcess(byteLength)) break;
				pendingEntry.operationIndex += 1;
				if (entry.kind === 'delta') {
					const shouldPublishDelta =
						!replacementResetPending ||
						replacementPaths === null ||
						replacementPublishesIncrementally;
					if (shouldPublishDelta) modelOperations.push(operation);
					applyOperationToPathSets(pathSetsForDelta(), operation, (value): void => {
						pendingPathRemoval = value;
					});
				} else if (stagingTransaction?.transactionId === entry.transactionId) {
					applyOperationToPathSets([stagingTransaction.paths], operation, (value): void => {
						pendingPathRemoval = value;
					});
				}
				recordWork(byteLength);
				if (pendingEntry.operationIndex >= entry.operations.length && pendingPathRemoval === null) {
					consumePendingEntry();
				}
				continue;
			}

			const controlByteLength = transactionId === null ? 0 : utf8ByteLength(transactionId);
			if (!canProcess(controlByteLength)) break;
			processControlEntry(entry);
			consumePendingEntry();
			recordWork(controlByteLength);
		}

		if (modelOperations.length > 0) {
			props.model.batch(modelOperations);
		}
		return {
			blockedOnProjection,
			hasPendingWork: hasPendingWork(),
			processedBytes,
			processedOperations,
		};
	};

	const pathSetsForDelta = (): readonly Set<string>[] => {
		if (replacementResetPending && replacementPaths !== null) {
			return replacementPublishesIncrementally
				? [committedPaths, replacementPaths]
				: [replacementPaths];
		}
		return [committedPaths];
	};

	const processControlEntry = (entry: BridgeMainFileTreePatchStreamEntry): void => {
		switch (entry.kind) {
			case 'queryBegin':
				stagingTransaction = { paths: new Set(), transactionId: entry.transactionId };
				return;
			case 'queryAbort':
				if (stagingTransaction?.transactionId === entry.transactionId) {
					stagingTransaction = null;
				}
				if (mostRecentQueuedQueryId === entry.transactionId) {
					mostRecentQueuedQueryId = null;
				}
				return;
			case 'queryCommit':
				if (stagingTransaction?.transactionId !== entry.transactionId) return;
				beginReplacement(stagingTransaction.paths, 'query', false);
				stagingTransaction = null;
				if (mostRecentQueuedQueryId === entry.transactionId) {
					mostRecentQueuedQueryId = null;
				}
				return;
			case 'clear':
				replacementPublishesIncrementally = false;
				replacementResetPending = false;
				replacementPaths = null;
				stagingTransaction = null;
				beginReplacement(new Set(), 'clear', false);
				return;
			case 'reset':
				replacementPublishesIncrementally = committedPaths.size === 0;
				replacementResetPending = true;
				replacementPaths = new Set();
				stagingTransaction = null;
				return;
			case 'replacementCommit':
				if (!replacementResetPending || replacementPaths === null) return;
				beginReplacement(replacementPaths, 'source', true);
				return;
			case 'delta':
			case 'queryBatch':
				return;
			default:
				assertNeverPatchStreamEntry(entry);
		}
	};

	const beginReplacement = (
		targetPaths: Set<string>,
		mode: ReplacementMode,
		expandDirectories: boolean,
	): void => {
		pendingReplacement = {
			appliedOperationCount: 0,
			committedPathIterator: committedPaths.values(),
			committedAndAncestors: new Set(),
			committedPaths,
			currentPath: null,
			expansionPathIterator: null,
			expandDirectories,
			mode,
			operationIndex: 0,
			operations: [],
			phase: 'indexCommittedPaths',
			removedRoots: new Set(),
			targetAndAncestors: new Set(),
			targetPathIterator: null,
			targetPaths,
			validationIndex: 0,
		};
	};

	const nextReplacementStep = (
		work: PendingReplacement,
		model: BridgeFileViewerPatchableTreeModel,
	): TurnWorkItem | null => {
		while (true) {
			switch (work.phase) {
				case 'indexCommittedPaths': {
					const path = currentReplacementPath(work, work.committedPathIterator);
					if (path === null) {
						work.phase = 'indexTargetPaths';
						work.committedPathIterator = null;
						work.targetPathIterator = work.targetPaths.values();
						work.currentPath = null;
						continue;
					}
					return {
						byteLength: utf8ByteLength(path),
						apply: (): void => {
							addPathAndAncestors(work.committedAndAncestors, path);
							work.currentPath = null;
						},
					};
				}
				case 'indexTargetPaths': {
					const path = currentReplacementPath(work, work.targetPathIterator);
					if (path === null) {
						work.phase = 'deriveRemovals';
						work.targetPathIterator = null;
						work.committedPathIterator = work.committedPaths.values();
						work.currentPath = null;
						continue;
					}
					return {
						byteLength: utf8ByteLength(path),
						apply: (): void => {
							addPathAndAncestors(work.targetAndAncestors, path);
							work.currentPath = null;
						},
					};
				}
				case 'deriveRemovals': {
					const path = currentReplacementPath(work, work.committedPathIterator);
					if (path === null) {
						work.phase = 'deriveAdditions';
						work.committedPathIterator = null;
						work.targetPathIterator = work.targetPaths.values();
						work.currentPath = null;
						continue;
					}
					return {
						byteLength: utf8ByteLength(path),
						apply: (): void => {
							if (!work.targetPaths.has(path)) {
								const removalRoot = shallowestObsoleteAncestor(path, work.targetAndAncestors);
								if (
									removalRoot !== null &&
									!pathHasRemovedAncestor(removalRoot, work.removedRoots)
								) {
									work.removedRoots.add(removalRoot);
									work.operations.push({
										path: removalRoot,
										recursive: true,
										type: 'remove',
									});
								}
							}
							work.currentPath = null;
						},
					};
				}
				case 'deriveAdditions': {
					const path = currentReplacementPath(work, work.targetPathIterator);
					if (path === null) {
						work.phase = 'validateOperations';
						work.targetPathIterator = null;
						work.currentPath = null;
						continue;
					}
					return {
						byteLength: utf8ByteLength(path),
						apply: (): void => {
							const normalizedPath = path.replace(/\/$/u, '');
							const pathAlreadyRendered =
								work.committedAndAncestors.has(path) ||
								work.committedAndAncestors.has(normalizedPath);
							const removedWithAncestor = pathHasRemovedAncestor(path, work.removedRoots);
							if (!pathAlreadyRendered || removedWithAncestor) {
								work.operations.push({ path, type: 'add' });
							}
							work.currentPath = null;
						},
					};
				}
				case 'validateOperations': {
					const operation = work.operations[work.validationIndex];
					if (operation === undefined) {
						work.phase = 'applyOperations';
						work.operationIndex = 0;
						continue;
					}
					const requiredPath = requiredFileTreePath(operation);
					return {
						byteLength: fileTreeOperationByteLength(operation),
						...(requiredPath === null ? {} : { requiredPath }),
						apply: (): void => {
							work.validationIndex += 1;
						},
					};
				}
				case 'applyOperations': {
					const operation = work.operations[work.operationIndex];
					if (operation === undefined) {
						if (work.expandDirectories) {
							work.phase = 'expandDirectories';
							work.expansionPathIterator = work.targetAndAncestors.values();
							return null;
						}
						work.phase = 'complete';
						continue;
					}
					return {
						byteLength: fileTreeOperationByteLength(operation),
						modelOperation: operation,
						apply: (): void => {
							work.operationIndex += 1;
							work.appliedOperationCount += 1;
						},
					};
				}
				case 'expandDirectories': {
					const path = currentReplacementPath(work, work.expansionPathIterator);
					if (path === null) {
						work.phase = 'complete';
						work.expansionPathIterator = null;
						continue;
					}
					return {
						byteLength: utf8ByteLength(path),
						apply: (): void => {
							if (!path.endsWith('/')) {
								const item = model.getItem(path);
								if (item !== null && 'expand' in item) item.expand();
							}
							work.currentPath = null;
						},
					};
				}
				case 'complete':
					return null;
				default:
					return assertNeverReplacementPhase(work.phase);
			}
		}
	};

	const completeReplacement = (work: PendingReplacement): void => {
		if (work.phase !== 'complete') return;
		committedPaths = new Set(work.targetPaths);
		if (work.mode === 'source') {
			replacementResetPending = false;
			replacementPublishesIncrementally = false;
			replacementPaths = null;
		}
		pendingReplacement = null;
	};

	const consumePendingEntry = (): void => {
		pendingEntryHead = pendingEntryHead?.next ?? null;
		if (pendingEntryHead === null) pendingEntryTail = null;
	};

	return { advanceNextTurn, applyEntry, enqueueEntry, hasPendingWork };
}

function applyOperationToPathSets(
	paths: readonly Set<string>[],
	operation: FileTreeBatchOperation,
	setPendingRemoval: (removal: PendingPathRemoval) => void,
): void {
	for (const pathSet of paths) {
		switch (operation.type) {
			case 'add':
				pathSet.add(operation.path);
				break;
			case 'move':
				pathSet.delete(operation.from);
				pathSet.add(operation.to);
				break;
			case 'remove':
				pathSet.delete(operation.path);
				break;
			default:
				assertNeverTreeOperation(operation);
		}
	}
	if (operation.type === 'remove' && operation.recursive === true) {
		setPendingRemoval({
			currentPath: null,
			descendantPrefix: operation.path.endsWith('/') ? operation.path : `${operation.path}/`,
			iterator: null,
			pathSetIndex: 0,
			pathSets: paths,
		});
	}
}

function nextPathRemovalStep(removal: PendingPathRemoval): TurnWorkItem | null {
	while (removal.pathSetIndex < removal.pathSets.length) {
		const pathSet = removal.pathSets[removal.pathSetIndex];
		if (pathSet === undefined) return null;
		removal.iterator ??= pathSet.values();
		if (removal.currentPath === null) {
			const nextPath = removal.iterator.next();
			if (nextPath.done) {
				removal.pathSetIndex += 1;
				removal.iterator = null;
				continue;
			}
			removal.currentPath = nextPath.value;
		}
		const path = removal.currentPath;
		return {
			byteLength: utf8ByteLength(path),
			apply: (): void => {
				if (path.startsWith(removal.descendantPrefix)) pathSet.delete(path);
				removal.currentPath = null;
			},
		};
	}
	return null;
}

function currentReplacementPath(
	work: PendingReplacement,
	iterator: IterableIterator<string> | null,
): string | null {
	if (work.currentPath !== null) return work.currentPath;
	if (iterator === null) return null;
	const nextPath = iterator.next();
	if (nextPath.done) return null;
	work.currentPath = nextPath.value;
	return work.currentPath;
}

function addPathAndAncestors(paths: Set<string>, path: string): void {
	const normalizedPath = path.replace(/\/$/u, '');
	const segments = normalizedPath.split('/').filter((segment): boolean => segment.length > 0);
	for (let segmentCount = 1; segmentCount <= segments.length; segmentCount += 1) {
		paths.add(segments.slice(0, segmentCount).join('/'));
	}
	paths.add(path);
}

function shallowestObsoleteAncestor(
	path: string,
	targetAndAncestors: ReadonlySet<string>,
): string | null {
	const segments = path
		.replace(/\/$/u, '')
		.split('/')
		.filter((segment): boolean => segment.length > 0);
	for (let segmentCount = 1; segmentCount <= segments.length; segmentCount += 1) {
		const candidatePath = segments.slice(0, segmentCount).join('/');
		if (!targetAndAncestors.has(candidatePath)) return candidatePath;
	}
	return null;
}

function pathHasRemovedAncestor(path: string, removedRoots: ReadonlySet<string>): boolean {
	const segments = path
		.replace(/\/$/u, '')
		.split('/')
		.filter((segment): boolean => segment.length > 0);
	for (let segmentCount = 1; segmentCount <= segments.length; segmentCount += 1) {
		if (removedRoots.has(segments.slice(0, segmentCount).join('/'))) return true;
	}
	return false;
}

function fileTreeOperationByteLength(operation: FileTreeBatchOperation): number {
	switch (operation.type) {
		case 'add':
		case 'remove':
			return utf8ByteLength(operation.path);
		case 'move':
			return utf8ByteLength(operation.from) + utf8ByteLength(operation.to);
		default:
			return assertNeverTreeOperation(operation);
	}
}

function requiredFileTreePath(operation: FileTreeBatchOperation): string | null {
	switch (operation.type) {
		case 'add':
			return operation.path;
		case 'move':
			return operation.to;
		case 'remove':
			return null;
		default:
			return assertNeverTreeOperation(operation);
	}
}

function utf8ByteLength(value: string): number {
	return utf8ByteEncoder.encode(value).byteLength;
}

function queryTransactionId(entry: BridgeMainFileTreePatchStreamEntry): string | null {
	return 'transactionId' in entry ? entry.transactionId : null;
}

function validateTurnLimits(limits: BridgeFileViewerTreePatchTurnLimits): void {
	if (
		!Number.isSafeInteger(limits.maximumBytes) ||
		limits.maximumBytes <= 0 ||
		!Number.isSafeInteger(limits.maximumOperations) ||
		limits.maximumOperations <= 0
	) {
		throw new RangeError('File tree patch turn limits must be positive safe integers.');
	}
}

function assertNeverPatchStreamEntry(entry: never): never {
	throw new Error(`Unhandled File tree patch stream entry: ${JSON.stringify(entry)}`);
}

function assertNeverTreeOperation(operation: never): never {
	throw new Error(`Unhandled File tree operation: ${JSON.stringify(operation)}`);
}

function assertNeverReplacementPhase(phase: never): never {
	throw new Error(`Unhandled File tree replacement phase: ${String(phase)}`);
}
