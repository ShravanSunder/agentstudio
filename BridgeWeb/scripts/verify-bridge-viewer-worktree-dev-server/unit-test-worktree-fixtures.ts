import type { WorktreeFileTreeRow } from './types.ts';

export function makeWorktreeFileTreeRow(path: string, rowId: string): WorktreeFileTreeRow {
	return {
		changeStatus: 'modified',
		depth: 0,
		fileId: `file-${rowId}`,
		isDirectory: false,
		lineCount: 1,
		name: path,
		parentPath: null,
		path,
		rowId,
		sizeBytes: 1,
	};
}
