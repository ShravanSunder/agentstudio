import { describe, expect, test } from 'vitest';

import type { BridgeFileViewerDisplayTreeRow } from './bridge-file-viewer-display-model.js';
import { createBridgeFileViewerTreeSelectionCoordinator } from './bridge-file-viewer-pierre-tree-runtime.js';
import {
	visibleFileDemandChangeForPierreVisibleFileRows,
	type PierreVisibleFileRowElement,
} from './bridge-file-viewer-pierre-visible-demand.js';

const rows: readonly BridgeFileViewerDisplayTreeRow[] = [
	{
		changeStatus: null,
		depth: 0,
		fileId: 'file-a',
		isDirectory: false,
		lineCount: 1,
		name: 'a.ts',
		parentPath: null,
		path: 'a.ts',
		projectionIndex: 7,
		rowId: 'row-a',
		sizeBytes: 1,
	},
	{
		changeStatus: 'modified',
		depth: 0,
		fileId: 'file-b',
		isDirectory: false,
		lineCount: 2,
		name: 'b.ts',
		parentPath: null,
		path: 'b.ts',
		projectionIndex: 9,
		rowId: 'row-b',
		sizeBytes: 2,
	},
];

describe('Bridge File viewer tree display adapter', () => {
	test('deduplicates Pierre click and selection callbacks without descriptor requests', () => {
		const selectedPaths: string[] = [];
		const coordinator = createBridgeFileViewerTreeSelectionCoordinator({
			selectPath: (path): void => {
				selectedPaths.push(path);
			},
		});

		coordinator.recordPierreSelectionPath('a.ts');
		coordinator.handleClickedPath('a.ts');
		coordinator.handleClickedPath('a.ts');

		expect(selectedPaths).toEqual(['a.ts', 'a.ts']);
	});

	test('deduplicates the asynchronous click-before-selection callback order', () => {
		const selectedPaths: string[] = [];
		const coordinator = createBridgeFileViewerTreeSelectionCoordinator({
			selectPath: (path): void => {
				selectedPaths.push(path);
			},
		});

		coordinator.handleClickedPath('a.ts');
		coordinator.recordPierreSelectionPath('a.ts');
		coordinator.handleClickedPath('a.ts');

		expect(selectedPaths).toEqual(['a.ts', 'a.ts']);
	});

	test('publishes only visible worker item ids and worker projection indexes', () => {
		const demand = visibleFileDemandChangeForPierreVisibleFileRows({
			rowElements: [visibleRow('b.ts'), visibleRow('a.ts'), visibleRow('a.ts')],
			treeRowByPath: new Map(rows.map((row) => [row.path, row])),
		});

		expect(demand).toEqual({
			descriptorRefs: [],
			firstVisibleIndex: 7,
			lastVisibleIndex: 9,
			visibleFileCount: 2,
			visibleItemIds: ['file-b', 'file-a'],
			visibleItemIndexes: [9, 7],
		});
	});

	test('ignores directories and unknown Pierre paths', () => {
		const directory: BridgeFileViewerDisplayTreeRow = {
			changeStatus: null,
			depth: 0,
			fileId: null,
			isDirectory: true,
			lineCount: null,
			name: 'Sources',
			parentPath: null,
			path: 'Sources',
			projectionIndex: 0,
			rowId: 'row-sources',
			sizeBytes: null,
		};
		const demand = visibleFileDemandChangeForPierreVisibleFileRows({
			rowElements: [visibleRow('Sources'), visibleRow('missing')],
			treeRowByPath: new Map([[directory.path, directory]]),
		});

		expect(demand).toBeNull();
	});
});

function visibleRow(path: string): PierreVisibleFileRowElement {
	return {
		getAttribute: (name: string): string | null => (name === 'data-item-path' ? path : null),
	} as PierreVisibleFileRowElement;
}
