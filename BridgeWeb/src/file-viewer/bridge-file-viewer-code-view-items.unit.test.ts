import { describe, expect, test } from 'vitest';

import type { BridgeWorkerCodeViewFileItem } from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import { bridgeFileViewerCodeViewItemsForPanelState } from './bridge-file-viewer-code-view-items.js';
import type { BridgeFileViewerDisplayItem } from './bridge-file-viewer-display-model.js';

const displayItem: BridgeFileViewerDisplayItem = {
	availability: { kind: 'available' },
	displayPath: 'Sources/File.swift',
	endsMidLine: false,
	endsWithNewline: true,
	extent: { kind: 'exactLineCount', lineCount: 12_000 },
	fileExtension: 'swift',
	fileId: 'file-1',
	language: 'swift',
	path: 'Sources/File.swift',
	payloadByteCount: 100_000,
	payloadLineCount: 10_000,
	rowId: 'row-file-1',
	sizeBytes: 120_000,
	totalLineCount: 12_000,
	truncationKind: 'lineLimit',
};

const pierreItem: BridgeWorkerCodeViewFileItem = {
	id: 'file:file-1',
	type: 'file',
	file: {
		cacheKey: 'file-content:sha256',
		contents: 'export const ready = true;\n',
		lang: 'typescript',
		name: 'Sources/File.swift',
	},
	version: 1,
	bridgeMetadata: {
		cacheKey: 'file-content:sha256',
		contentRoles: ['file'],
		contentState: 'windowed',
		displayPath: 'Sources/File.swift',
		itemId: 'file-1',
		lineCount: 1,
	},
};

describe('Bridge File viewer CodeView items', () => {
	test('renders the released Pierre item as the only ready body source', () => {
		const items = bridgeFileViewerCodeViewItemsForPanelState({
			openFileState: {
				displayItem,
				fileId: 'file-1',
				path: 'Sources/File.swift',
				status: 'ready',
			},
			selectedCodeViewItem: pierreItem,
		});

		expect(items).toHaveLength(1);
		expect(items[0]).toBe(pierreItem);
		const item = items[0];
		expect(item?.type).toBe('file');
		if (item?.type !== 'file') {
			throw new Error('Expected File CodeView item');
		}
		expect(item.file.contents).toBe('export const ready = true;\n');
		expect(item.bridgeMetadata).toEqual(pierreItem.bridgeMetadata);
	});

	test('does not fabricate a Pierre item or scroll extent while complete content is loading', () => {
		const items = bridgeFileViewerCodeViewItemsForPanelState({
			openFileState: {
				displayItem: { ...displayItem, payloadLineCount: 3 },
				fileId: 'file-1',
				path: 'Sources/File.swift',
				status: 'loading',
			},
			selectedCodeViewItem: null,
		});

		expect(items).toEqual([]);
	});

	test('does not synthesize a placeholder for binary or unavailable display items', () => {
		const items = bridgeFileViewerCodeViewItemsForPanelState({
			openFileState: {
				displayItem: {
					...displayItem,
					availability: { kind: 'binary' },
					payloadByteCount: 0,
					payloadLineCount: 0,
				},
				fileId: 'file-1',
				path: 'Sources/File.swift',
				status: 'unavailable',
			},
			selectedCodeViewItem: null,
		});

		expect(items).toEqual([]);
	});
});
