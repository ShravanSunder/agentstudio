export function countFlattenedWorktreeFileTreeRows(paths: readonly string[]): number {
	const rootNode: WorktreeFileTreeDirectoryNode = { directories: new Map(), fileCount: 0 };
	for (const path of paths) {
		const parts = path.split('/').filter((part) => part.length > 0);
		if (parts.length === 0) {
			continue;
		}
		let currentNode = rootNode;
		for (let index = 0; index < parts.length - 1; index += 1) {
			const directoryName = parts[index];
			if (directoryName === undefined) {
				continue;
			}
			let childNode = currentNode.directories.get(directoryName);
			if (childNode === undefined) {
				childNode = { directories: new Map(), fileCount: 0 };
				currentNode.directories.set(directoryName, childNode);
			}
			currentNode = childNode;
		}
		currentNode.fileCount += 1;
	}
	return countFlattenedWorktreeDirectoryRows(rootNode, true);
}

interface WorktreeFileTreeDirectoryNode {
	readonly directories: Map<string, WorktreeFileTreeDirectoryNode>;
	fileCount: number;
}

function countFlattenedWorktreeDirectoryRows(
	node: WorktreeFileTreeDirectoryNode,
	isRoot: boolean,
): number {
	let visibleChildRows = node.fileCount;
	for (const childNode of node.directories.values()) {
		visibleChildRows += countFlattenedWorktreeDirectoryRows(childNode, false);
	}
	if (isRoot) {
		return visibleChildRows;
	}
	const childCount = node.fileCount + node.directories.size;
	const onlyChildIsDirectory = node.fileCount === 0 && node.directories.size === 1;
	if (childCount === 1 && onlyChildIsDirectory) {
		return visibleChildRows;
	}
	return 1 + visibleChildRows;
}
