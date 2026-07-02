import type {
	WorktreeFileDescriptor,
	WorktreeTreeOperation,
	WorktreeTreeRowMetadata,
	WorktreeTreeVirtualizedSizeFacts,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';

export function applyWorktreeTreeOperationsToFileViewerState(props: {
	readonly descriptorsByFileId: Map<string, WorktreeFileDescriptor>;
	readonly fallbackRowHeightPixels: number;
	readonly operations: readonly WorktreeTreeOperation[];
	readonly pruneEmptyDirectories: (treeRowsByPath: Map<string, WorktreeTreeRowMetadata>) => void;
	readonly treeRowsByPath: Map<string, WorktreeTreeRowMetadata>;
	readonly treeSizeFacts: WorktreeTreeVirtualizedSizeFacts | null;
}): WorktreeTreeVirtualizedSizeFacts | null {
	let treeSizeFacts = props.treeSizeFacts;
	for (const operation of props.operations) {
		switch (operation.op) {
			case 'upsertRows':
				treeSizeFacts = applyWorktreeTreeUpserts({
					rows: operation.rows,
					treeRowsByPath: props.treeRowsByPath,
					treeSizeFacts,
				});
				break;
			case 'removeRows':
				treeSizeFacts = applyWorktreeTreeRemovals({
					descriptorsByFileId: props.descriptorsByFileId,
					paths: operation.paths,
					rowIds: operation.rowIds,
					treeRowsByPath: props.treeRowsByPath,
					treeSizeFacts,
				});
				break;
			case 'moveSubtree':
				applyWorktreeTreeSubtreeMove({
					descriptorsByFileId: props.descriptorsByFileId,
					operation,
					treeRowsByPath: props.treeRowsByPath,
				});
				break;
			case 'replaceWindow':
				treeSizeFacts = applyWorktreeTreeWindowReplacement({
					fallbackRowHeightPixels: props.fallbackRowHeightPixels,
					operation,
					treeRowsByPath: props.treeRowsByPath,
					treeSizeFacts,
				});
				break;
		}
	}
	props.pruneEmptyDirectories(props.treeRowsByPath);
	return treeSizeFacts;
}

function applyWorktreeTreeUpserts(props: {
	readonly rows: readonly WorktreeTreeRowMetadata[];
	readonly treeRowsByPath: Map<string, WorktreeTreeRowMetadata>;
	readonly treeSizeFacts: WorktreeTreeVirtualizedSizeFacts | null;
}): WorktreeTreeVirtualizedSizeFacts | null {
	let addedRowCount = 0;
	for (const treeRow of props.rows) {
		if (!props.treeRowsByPath.has(treeRow.path)) {
			addedRowCount += 1;
		}
		props.treeRowsByPath.set(treeRow.path, treeRow);
	}
	return adjustExactPathCount(props.treeSizeFacts, addedRowCount);
}

function applyWorktreeTreeRemovals(props: {
	readonly descriptorsByFileId: Map<string, WorktreeFileDescriptor>;
	readonly paths: readonly string[] | undefined;
	readonly rowIds: readonly string[];
	readonly treeRowsByPath: Map<string, WorktreeTreeRowMetadata>;
	readonly treeSizeFacts: WorktreeTreeVirtualizedSizeFacts | null;
}): WorktreeTreeVirtualizedSizeFacts | null {
	const pathsToDelete = new Set(props.paths ?? []);
	const rowIdsToDelete = new Set(props.rowIds);
	for (const treeRow of props.treeRowsByPath.values()) {
		if (rowIdsToDelete.has(treeRow.rowId)) {
			pathsToDelete.add(treeRow.path);
		}
	}
	let removedRowCount = 0;
	for (const path of pathsToDelete) {
		const removedTreeRow = props.treeRowsByPath.get(path);
		if (removedTreeRow === undefined) {
			continue;
		}
		props.treeRowsByPath.delete(path);
		removedRowCount += 1;
		if (removedTreeRow.fileId !== undefined) {
			props.descriptorsByFileId.delete(removedTreeRow.fileId);
		}
		for (const [fileId, descriptor] of props.descriptorsByFileId) {
			if (descriptor.path === removedTreeRow.path) {
				props.descriptorsByFileId.delete(fileId);
			}
		}
	}
	return adjustExactPathCount(props.treeSizeFacts, -removedRowCount);
}

function applyWorktreeTreeSubtreeMove(props: {
	readonly descriptorsByFileId: Map<string, WorktreeFileDescriptor>;
	readonly operation: Extract<WorktreeTreeOperation, { readonly op: 'moveSubtree' }>;
	readonly treeRowsByPath: Map<string, WorktreeTreeRowMetadata>;
}): void {
	const oldPrefix = `${props.operation.oldPath.replace(/\/+$/, '')}/`;
	const movedRows: WorktreeTreeRowMetadata[] = [];
	for (const treeRow of props.treeRowsByPath.values()) {
		if (treeRow.path === props.operation.oldPath || treeRow.path.startsWith(oldPrefix)) {
			movedRows.push(treeRow);
		}
	}
	for (const treeRow of movedRows) {
		props.treeRowsByPath.delete(treeRow.path);
		if (treeRow.fileId !== undefined) {
			props.descriptorsByFileId.delete(treeRow.fileId);
		}
		for (const [fileId, descriptor] of props.descriptorsByFileId) {
			if (descriptor.path === treeRow.path || descriptor.path.startsWith(oldPrefix)) {
				props.descriptorsByFileId.delete(fileId);
			}
		}
	}
	for (const treeRow of movedRows) {
		const nextPath =
			treeRow.path === props.operation.oldPath
				? props.operation.newPath
				: `${props.operation.newPath}/${treeRow.path.slice(oldPrefix.length)}`;
		props.treeRowsByPath.set(nextPath, {
			...treeRow,
			path: nextPath,
			name: pathBasename(nextPath),
			parentPath:
				treeRow.path === props.operation.oldPath
					? props.operation.newParentPath
					: parentPathForWorktreePath(nextPath),
			depth: Math.max(treeRow.depth + props.operation.depthDelta, 0),
		});
	}
}

function applyWorktreeTreeWindowReplacement(props: {
	readonly fallbackRowHeightPixels: number;
	readonly operation: Extract<WorktreeTreeOperation, { readonly op: 'replaceWindow' }>;
	readonly treeRowsByPath: Map<string, WorktreeTreeRowMetadata>;
	readonly treeSizeFacts: WorktreeTreeVirtualizedSizeFacts | null;
}): WorktreeTreeVirtualizedSizeFacts | null {
	const currentRows = [...props.treeRowsByPath.values()];
	const replacementRowCount =
		props.treeSizeFacts?.windowStartIndex === props.operation.startIndex &&
		props.treeSizeFacts.windowRowCount !== undefined
			? props.treeSizeFacts.windowRowCount
			: props.operation.rows.length;
	const replacedRows = currentRows.slice(
		props.operation.startIndex,
		props.operation.startIndex + replacementRowCount,
	);
	for (const treeRow of replacedRows) {
		props.treeRowsByPath.delete(treeRow.path);
	}
	for (const treeRow of props.operation.rows) {
		props.treeRowsByPath.set(treeRow.path, treeRow);
	}
	if (props.operation.totalRowCount === undefined) {
		return props.treeSizeFacts;
	}
	return {
		...(props.treeSizeFacts ?? {
			extentKind: 'exactPathCount',
			rowHeightPixels: props.fallbackRowHeightPixels,
		}),
		extentKind: 'exactPathCount',
		pathCount: props.operation.totalRowCount,
		windowStartIndex: props.operation.startIndex,
		windowRowCount: props.operation.rows.length,
	};
}

function adjustExactPathCount(
	treeSizeFacts: WorktreeTreeVirtualizedSizeFacts | null,
	delta: number,
): WorktreeTreeVirtualizedSizeFacts | null {
	if (
		treeSizeFacts === null ||
		treeSizeFacts.extentKind !== 'exactPathCount' ||
		treeSizeFacts.pathCount === undefined ||
		delta === 0
	) {
		return treeSizeFacts;
	}
	return {
		...treeSizeFacts,
		pathCount: Math.max(treeSizeFacts.pathCount + delta, 0),
	};
}

function parentPathForWorktreePath(path: string): string | null {
	const lastSeparatorIndex = path.lastIndexOf('/');
	return lastSeparatorIndex === -1 ? null : path.slice(0, lastSeparatorIndex);
}

function pathBasename(path: string): string {
	return path.split('/').at(-1) ?? path;
}
