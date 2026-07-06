import { describe, expect, test } from 'vitest';

import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { makeFileDescriptor } from './bridge-file-viewer-browser-test-fixtures.js';
import {
	bridgeFileViewerCodeViewItemsForPanelState,
	bridgeFileViewerSelectedCodeViewItemForPanelState,
} from './bridge-file-viewer-code-view-items.js';

describe('Bridge file viewer CodeView item adapter', () => {
	test('creates a line-count placeholder item while selected file content loads', () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'content-loading',
			fileId: 'file-loading',
			lineCount: 3,
			path: 'src/loading.ts',
		});

		const items = bridgeFileViewerCodeViewItemsForPanelState({
			openFileState: {
				status: 'loading',
				path: descriptor.path,
				descriptor,
			},
			selectedCodeViewItem: null,
		});

		expect(items).toEqual([
			{
				id: 'file-placeholder:file-loading',
				type: 'file',
				file: {
					name: 'src/loading.ts',
					contents: ' \n \n ',
					cacheKey: 'content-loading:placeholder:3',
					lang: 'text',
				},
				version: 3,
				bridgeMetadata: {
					cacheKey: 'content-loading:placeholder:3',
					contentRoles: ['file'],
					contentState: 'placeholder',
					displayPath: 'src/loading.ts',
					itemId: 'file-loading',
					lineCount: 3,
				},
			},
		]);
	});

	test('creates a Pierre file item with a content-hash cache key', () => {
		const descriptor = makeHashedFileDescriptor({
			contentHandle: 'content-ready',
			contentHash: 'hash-ready',
			fileId: 'file-ready',
			path: 'src/ready.ts',
		});

		const selectedCodeViewItem = bridgeFileViewerSelectedCodeViewItemForPanelState({
			openFileState: {
				status: 'ready',
				path: descriptor.path,
				descriptor,
			},
			renderedFileContent: {
				body: 'export const ready = true;\n',
				bodyVersion: 7,
				descriptor,
				path: descriptor.path,
			},
		});
		const items = bridgeFileViewerCodeViewItemsForPanelState({
			openFileState: {
				status: 'ready',
				path: descriptor.path,
				descriptor,
			},
			selectedCodeViewItem,
		});

		expect(items).toEqual([
			{
				id: 'file:file-ready',
				type: 'file',
				file: {
					name: 'src/ready.ts',
					contents: 'export const ready = true;\n',
					cacheKey: 'content-ready:hash-ready',
				},
				version: 7,
				bridgeMetadata: {
					cacheKey: 'content-ready:hash-ready',
					contentRoles: ['file'],
					contentState: 'hydrated',
					displayPath: 'src/ready.ts',
					itemId: 'file-ready',
					lineCount: 2,
				},
			},
		]);
	});

	test('falls back to unknown in the cache key when content hash is absent', () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'content-without-hash',
			fileId: 'file-without-hash',
			path: 'src/without-hash.ts',
		});

		const selectedCodeViewItem = bridgeFileViewerSelectedCodeViewItemForPanelState({
			openFileState: {
				status: 'ready',
				path: descriptor.path,
				descriptor,
			},
			renderedFileContent: {
				body: 'export const fallback = true;\n',
				bodyVersion: 3,
				descriptor,
				path: descriptor.path,
			},
		});
		const items = bridgeFileViewerCodeViewItemsForPanelState({
			openFileState: {
				status: 'ready',
				path: descriptor.path,
				descriptor,
			},
			selectedCodeViewItem,
		});

		expect(items[0]).toMatchObject({
			id: 'file:file-without-hash',
			type: 'file',
			file: {
				cacheKey: 'content-without-hash:unknown',
			},
			version: 3,
		});
	});

	test('reserves the selected file line-count extent with a content-hash cache key', () => {
		const retainedDescriptor = makeHashedFileDescriptor({
			contentHandle: 'content-retained',
			contentHash: 'hash-retained',
			fileId: 'file-retained',
			path: 'src/retained.ts',
		});
		const selectedDescriptor = makeFileDescriptor({
			contentHandle: 'content-selected',
			fileId: 'file-selected',
			lineCount: 5,
			path: 'src/selected.ts',
		});

		const selectedCodeViewItem = bridgeFileViewerSelectedCodeViewItemForPanelState({
			openFileState: {
				status: 'loading',
				path: selectedDescriptor.path,
				descriptor: selectedDescriptor,
			},
			renderedFileContent: {
				body: 'one\ntwo',
				bodyVersion: 11,
				descriptor: retainedDescriptor,
				path: retainedDescriptor.path,
			},
		});
		const items = bridgeFileViewerCodeViewItemsForPanelState({
			openFileState: {
				status: 'loading',
				path: selectedDescriptor.path,
				descriptor: selectedDescriptor,
			},
			selectedCodeViewItem,
		});

		const item = items[0];
		expect(item?.type).toBe('file');
		if (item?.type !== 'file') {
			throw new Error('expected a Pierre file item');
		}
		expect(item.file.contents).toBe('one\ntwo\n\n\n ');
		expect(item.file.cacheKey).toBe('content-retained:hash-retained:reserved:src/selected.ts:5');
		expect(item.file.lang).toBe('text');
		expect(item.version).toBe(16);
		expect(renderedLineCountForText(item.file.contents)).toBe(5);
	});
});

function makeHashedFileDescriptor(props: {
	readonly contentHandle: string;
	readonly contentHash: string;
	readonly fileId: string;
	readonly lineCount?: number;
	readonly path: string;
}): WorktreeFileDescriptor {
	return {
		...makeFileDescriptor(props),
		contentHash: props.contentHash,
	};
}

function renderedLineCountForText(text: string): number {
	if (text.length === 0) {
		return 0;
	}
	return (text.match(/\n/gu)?.length ?? 0) + 1;
}
