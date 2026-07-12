import type { FileTreeBatchOperation } from '@pierre/trees';

import type { BridgeMainFileTreePatchStreamEntry } from '../core/comm-worker/bridge-main-file-display-patch-applier.js';

export interface BridgeFileViewerPatchableTreeModel {
	readonly batch: (operations: readonly FileTreeBatchOperation[]) => void;
	readonly resetPaths: (paths: readonly string[]) => void;
}

export interface BridgeFileViewerTreePatchCoordinator {
	readonly applyEntry: (entry: BridgeMainFileTreePatchStreamEntry) => void;
}

export function createBridgeFileViewerTreePatchCoordinator(props: {
	readonly initialPaths?: readonly string[];
	readonly model: BridgeFileViewerPatchableTreeModel;
	readonly onQueryTransactionReady: (transactionId: string) => boolean;
}): BridgeFileViewerTreePatchCoordinator {
	let committedPaths = new Set(props.initialPaths ?? []);
	let replacementPublishesIncrementally = false;
	let replacementResetPending = false;
	let replacementPaths: Set<string> | null = null;
	let stagingTransaction: {
		readonly paths: Set<string>;
		readonly transactionId: string;
	} | null = null;

	return {
		applyEntry: (entry): void => {
			switch (entry.kind) {
				case 'delta':
					if (entry.operations.length === 0) return;
					if (replacementResetPending && replacementPaths !== null) {
						applyOperationsToStagedPaths(replacementPaths, entry.operations);
						if (replacementPublishesIncrementally) {
							props.model.batch(entry.operations);
							committedPaths = new Set(replacementPaths);
						}
					} else {
						const nextCommittedPaths = new Set(committedPaths);
						applyOperationsToStagedPaths(nextCommittedPaths, entry.operations);
						props.model.batch(entry.operations);
						committedPaths = nextCommittedPaths;
					}
					return;
				case 'clear':
					replacementPublishesIncrementally = false;
					replacementResetPending = false;
					replacementPaths = null;
					stagingTransaction = null;
					props.model.resetPaths([]);
					committedPaths = new Set();
					return;
				case 'reset':
					replacementPublishesIncrementally = committedPaths.size === 0;
					replacementResetPending = true;
					replacementPaths = new Set();
					stagingTransaction = null;
					return;
				case 'replacementCommit':
					if (!replacementResetPending || replacementPaths === null) return;
					committedPaths = replaceCommittedPaths({
						committedPaths,
						model: props.model,
						nextPaths: replacementPaths,
					});
					replacementResetPending = false;
					replacementPublishesIncrementally = false;
					replacementPaths = null;
					return;
				case 'queryBegin':
					stagingTransaction = { paths: new Set(), transactionId: entry.transactionId };
					return;
				case 'queryBatch':
					if (
						stagingTransaction?.transactionId === entry.transactionId &&
						entry.operations.length > 0
					) {
						applyOperationsToStagedPaths(stagingTransaction.paths, entry.operations);
					}
					return;
				case 'queryAbort':
					if (stagingTransaction?.transactionId !== entry.transactionId) return;
					stagingTransaction = null;
					return;
				case 'queryCommit':
					if (stagingTransaction?.transactionId !== entry.transactionId) return;
					if (!props.onQueryTransactionReady(entry.transactionId)) {
						stagingTransaction = null;
						return;
					}
					committedPaths = replaceCommittedPaths({
						committedPaths,
						model: props.model,
						nextPaths: stagingTransaction.paths,
					});
					replacementResetPending = false;
					replacementPublishesIncrementally = false;
					replacementPaths = null;
					stagingTransaction = null;
					return;
				default:
					assertNeverPatchStreamEntry(entry);
			}
		},
	};
}

function replaceCommittedPaths(props: {
	readonly committedPaths: ReadonlySet<string>;
	readonly model: BridgeFileViewerPatchableTreeModel;
	readonly nextPaths: ReadonlySet<string>;
}): Set<string> {
	const operations = replacementOperationsBetween(props.committedPaths, props.nextPaths);
	if (operations.length > 0) props.model.batch(operations);
	return new Set(props.nextPaths);
}

function replacementOperationsBetween(
	committedPaths: ReadonlySet<string>,
	nextPaths: ReadonlySet<string>,
): readonly FileTreeBatchOperation[] {
	const removedRoots: string[] = [];
	const removalCandidates = [...committedPaths]
		.filter((path) => !nextPaths.has(path))
		.toSorted((left, right) => left.length - right.length || left.localeCompare(right));
	for (const path of removalCandidates) {
		if (removedRoots.some((rootPath) => pathIsSameOrDescendant(path, rootPath))) continue;
		removedRoots.push(path);
	}
	const operations: FileTreeBatchOperation[] = removedRoots.map((path) => ({
		path,
		recursive: true,
		type: 'remove',
	}));
	for (const path of nextPaths) {
		const removedWithAncestor = removedRoots.some((rootPath) =>
			pathIsSameOrDescendant(path, rootPath),
		);
		if (!committedPaths.has(path) || removedWithAncestor) operations.push({ path, type: 'add' });
	}
	return operations;
}

function pathIsSameOrDescendant(path: string, rootPath: string): boolean {
	if (path === rootPath) return true;
	const descendantPrefix = rootPath.endsWith('/') ? rootPath : `${rootPath}/`;
	return path.startsWith(descendantPrefix);
}

function applyOperationsToStagedPaths(
	paths: Set<string>,
	operations: readonly FileTreeBatchOperation[],
): void {
	for (const operation of operations) {
		if (operation.type === 'add') {
			paths.add(operation.path);
			continue;
		}
		if (operation.type === 'move') {
			paths.delete(operation.from);
			paths.add(operation.to);
			continue;
		}
		paths.delete(operation.path);
		if (operation.recursive !== true) continue;
		const descendantPrefix = operation.path.endsWith('/') ? operation.path : `${operation.path}/`;
		for (const path of paths) {
			if (path.startsWith(descendantPrefix)) paths.delete(path);
		}
	}
}

function assertNeverPatchStreamEntry(entry: never): never {
	throw new Error(`Unhandled File tree patch stream entry: ${JSON.stringify(entry)}`);
}
