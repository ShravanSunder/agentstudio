import { describe, expect, test } from 'vitest';

import { BridgeMainFileTreeDisplayIndex } from './bridge-main-file-tree-display-index.js';

describe('Bridge main File tree display index', () => {
	test('preserves prior snapshots and returns one bounded Pierre delta for one row', () => {
		const initial = BridgeMainFileTreeDisplayIndex.empty().applyOperations([
			upsertRow('row-a', 'Sources/A.swift', 0),
			upsertRow('row-b', 'Sources/B.swift', 1),
		]).index;

		const result = initial.applyOperations([upsertRow('row-c', 'Sources/C.swift', 2)]);

		expect(initial.size).toBe(2);
		expect(initial.rowForId('row-c')).toBeUndefined();
		expect(initial.rowForPath('Sources/C.swift')).toBeUndefined();
		expect(result.index.size).toBe(3);
		expect(result.index.rowForId('row-c')?.path).toBe('Sources/C.swift');
		expect(result.pierreOperations).toEqual([{ path: 'Sources/C.swift', type: 'add' }]);
	});

	test('updates both identity indexes without mutating the prior path mapping', () => {
		const initial = BridgeMainFileTreeDisplayIndex.empty().applyOperations([
			upsertRow('row-a', 'Sources/A.swift', 0),
		]).index;

		const result = initial.applyOperations([upsertRow('row-a', 'Sources/Renamed.swift', 0)]);

		expect(initial.rowForPath('Sources/A.swift')?.rowId).toBe('row-a');
		expect(initial.rowForPath('Sources/Renamed.swift')).toBeUndefined();
		expect(result.index.rowForPath('Sources/A.swift')).toBeUndefined();
		expect(result.index.rowForPath('Sources/Renamed.swift')?.rowId).toBe('row-a');
		expect(result.pierreOperations).toEqual([
			{ path: 'Sources/A.swift', recursive: true, type: 'remove' },
			{ path: 'Sources/Renamed.swift', type: 'add' },
		]);
	});
});

function upsertRow(
	rowId: string,
	path: string,
	projectionIndex: number,
): Parameters<BridgeMainFileTreeDisplayIndex['applyOperations']>[0][number] {
	return {
		operation: 'upsert' as const,
		row: {
			changeStatus: 'modified' as const,
			depth: 1,
			fileId: `file-${rowId}`,
			isDirectory: false,
			lineCount: 10,
			name: path.split('/').at(-1) ?? path,
			parentPath: 'Sources',
			path,
			projectionIndex,
			rowId,
			sizeBytes: 100,
		},
	};
}
