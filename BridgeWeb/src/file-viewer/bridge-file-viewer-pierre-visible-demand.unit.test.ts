import { describe, expect, test } from 'vitest';

import type { BridgeFileViewerDisplayTreeRow } from './bridge-file-viewer-display-model.js';
import { visibleFileDemandChangeForPierreVisibleFileRows } from './bridge-file-viewer-pierre-visible-demand.js';

describe('Bridge File viewer Pierre visible demand', () => {
	test('performs one indexed lookup per visible row instead of scanning the corpus', () => {
		let lookupCount = 0;
		const rowsByPath = new Map([
			['Sources/A.swift', fileRow('file-a', 'Sources/A.swift', 10)],
			['Sources/B.swift', fileRow('file-b', 'Sources/B.swift', 11)],
			['Sources/C.swift', fileRow('file-c', 'Sources/C.swift', 12)],
		]);

		const change = visibleFileDemandChangeForPierreVisibleFileRows({
			rowElements: [
				rowElement('Sources/A.swift'),
				rowElement('Sources/B.swift'),
				rowElement('Sources/C.swift'),
			],
			treeRowByPath: {
				get(path) {
					lookupCount += 1;
					return rowsByPath.get(path);
				},
			},
		});

		expect(lookupCount).toBe(3);
		expect(change).toMatchObject({
			firstVisibleIndex: 10,
			lastVisibleIndex: 12,
			visibleItemIds: ['file-a', 'file-b', 'file-c'],
			visibleItemIndexes: [10, 11, 12],
		});
	});
});

function rowElement(path: string): {
	readonly getAttribute: (attributeName: string) => string | null;
} {
	return {
		getAttribute(attributeName: string): string | null {
			return attributeName === 'data-item-path' ? path : null;
		},
	};
}

function fileRow(
	fileId: string,
	path: string,
	projectionIndex: number,
): BridgeFileViewerDisplayTreeRow {
	return {
		changeStatus: 'modified' as const,
		depth: 1,
		fileId,
		isDirectory: false,
		lineCount: 10,
		name: path.split('/').at(-1) ?? path,
		parentPath: 'Sources',
		path,
		projectionIndex,
		rowId: `row-${fileId}`,
		sizeBytes: 100,
	};
}
