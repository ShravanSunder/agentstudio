import { describe, expect, test } from 'vitest';

import { BridgeMainFileTreeDisplayIndex } from '../core/comm-worker/bridge-main-file-tree-display-index.js';
import type { BridgeMainRenderSnapshot } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import {
	bridgeFileViewerDisplayModelForSnapshot,
	bridgeFileViewerOpenStateForSelection,
} from './bridge-file-viewer-display-model.js';

const fileDisplaySnapshot: Pick<
	BridgeMainRenderSnapshot,
	'fileDisplayFreshness' | 'fileItemById' | 'fileQuerySlice' | 'fileStatusSlice' | 'fileTreeSlice'
> = {
	fileDisplayFreshness: { epoch: 4, projectionRevision: 8, sequence: 12 },
	fileItemById: new Map(
		Object.entries({
			'file-readme': {
				availability: { kind: 'available' },
				displayPath: 'README.md',
				endsMidLine: false,
				endsWithNewline: true,
				extent: { kind: 'exactLineCount', lineCount: 12 },
				fileExtension: 'md',
				language: 'markdown',
				payloadByteCount: 128,
				payloadLineCount: 12,
				rowId: 'row-readme',
				sizeBytes: 128,
				totalLineCount: 12,
				truncationKind: 'none',
			},
			'file-binary': {
				availability: { kind: 'binary' },
				displayPath: 'assets/logo.bin',
				endsMidLine: false,
				endsWithNewline: false,
				extent: { kind: 'unavailable' },
				fileExtension: 'bin',
				language: null,
				payloadByteCount: 0,
				payloadLineCount: 0,
				rowId: 'row-binary',
				sizeBytes: 4096,
				totalLineCount: null,
				truncationKind: 'none',
			},
		}),
	),
	fileQuerySlice: {
		filterMode: 'all',
		projectedRowCount: 3,
		searchError: null,
		searchMode: 'text',
		searchText: '',
		totalRowCount: 3,
	},
	fileStatusSlice: {
		ahead: 1,
		behind: 0,
		branchName: 'main',
		staged: 2,
		state: 'ready',
		unstaged: 3,
		untracked: 4,
	},
	fileTreeSlice: {
		index: BridgeMainFileTreeDisplayIndex.empty().applyOperations([
			{
				operation: 'upsert',
				row: {
					changeStatus: null,
					depth: 0,
					documentLocation: null,
					fileId: null,
					fileClass: null,
					isDirectory: true,
					lineCount: null,
					name: 'assets',
					parentPath: null,
					path: 'assets',
					projectionIndex: 1,
					rowId: 'row-assets',
					sizeBytes: null,
				},
			},
			{
				operation: 'upsert',
				row: {
					changeStatus: 'untracked',
					depth: 1,
					documentLocation: null,
					fileId: 'file-binary',
					fileClass: 'unknown',
					isDirectory: false,
					lineCount: null,
					name: 'logo.bin',
					parentPath: 'assets',
					path: 'assets/logo.bin',
					projectionIndex: 2,
					rowId: 'row-binary',
					sizeBytes: 4096,
				},
			},
			{
				operation: 'upsert',
				row: {
					changeStatus: 'modified',
					depth: 0,
					documentLocation: null,
					fileId: 'file-readme',
					fileClass: 'docs',
					isDirectory: false,
					lineCount: 12,
					name: 'README.md',
					parentPath: null,
					path: 'README.md',
					projectionIndex: 0,
					rowId: 'row-readme',
					sizeBytes: 128,
				},
			},
		]).index,
		sourceGeneration: 7,
		sourceId: 'source-worktree',
	},
};

describe('Bridge File viewer worker display model', () => {
	test('projects ordered tree, display-only items, and status without product descriptors', () => {
		const model = bridgeFileViewerDisplayModelForSnapshot(fileDisplaySnapshot);

		expect(model.projectedRowCount).toBe(3);
		expect(model.treeRowByPath.get('README.md')).toMatchObject({
			fileId: 'file-readme',
			projectionIndex: 0,
		});
		expect(model.treeRowByPath.get('assets/logo.bin')).toMatchObject({
			fileId: 'file-binary',
			projectionIndex: 2,
		});
		expect(model.firstFileRow).toMatchObject({
			fileId: 'file-readme',
			path: 'README.md',
		});
		expect(model.fileItemById.get('file-readme')).toMatchObject({
			availability: { kind: 'available' },
			fileId: 'file-readme',
			path: 'README.md',
			payloadLineCount: 12,
		});
		expect(model.source).toEqual({ generation: 7, sourceId: 'source-worktree' });
		expect(model.status).toMatchObject({ state: 'ready', branchName: 'main' });
		expect(JSON.stringify(model)).not.toMatch(
			/contentDescriptor|descriptorId|expectedSha256|leaseId|sourceCursor/u,
		);
	});

	test('keeps equal relative paths from two member groups and an opened document distinct', () => {
		// Arrange
		const collectionSnapshot = {
			...fileDisplaySnapshot,
			fileTreeSlice: {
				index: BridgeMainFileTreeDisplayIndex.empty().applyOperations([
					collectionDirectoryRow('frontend', 0),
					collectionFileRow({ fileId: 'file-frontend-app', path: 'frontend/app.ts', index: 1 }),
					collectionDirectoryRow('backend', 2),
					collectionFileRow({ fileId: 'file-backend-app', path: 'backend/app.ts', index: 3 }),
					collectionDirectoryRow('Open Files', 4),
					collectionFileRow({
						documentLocation: '/private/tmp/notes.md',
						fileId: 'file-opened-notes',
						index: 5,
						path: 'Open Files/notes.md',
					}),
				]).index,
				sourceGeneration: 9,
				sourceId: 'collection-source-1',
			},
		};

		// Act
		const model = bridgeFileViewerDisplayModelForSnapshot(collectionSnapshot);

		// Assert
		expect(model.treeRowByPath.get('frontend/app.ts')).toMatchObject({
			documentLocation: null,
			fileId: 'file-frontend-app',
		});
		expect(model.treeRowByPath.get('backend/app.ts')).toMatchObject({
			documentLocation: null,
			fileId: 'file-backend-app',
		});
		expect(model.treeRowByPath.get('Open Files/notes.md')).toMatchObject({
			documentLocation: '/private/tmp/notes.md',
			fileId: 'file-opened-notes',
		});
		expect(model.firstFileRow).toMatchObject({ path: 'frontend/app.ts' });
	});

	test('derives selected loading, ready, binary, and stale presentation from worker facts', () => {
		const model = bridgeFileViewerDisplayModelForSnapshot(fileDisplaySnapshot);
		const readme = model.fileItemById.get('file-readme');
		const binary = model.fileItemById.get('file-binary');
		expect(readme).toBeDefined();
		expect(binary).toBeDefined();

		expect(
			bridgeFileViewerOpenStateForSelection({
				contentAvailability: { state: 'loading' },
				displayItem: readme ?? null,
				hasPierreItem: false,
				selection: { fileId: 'file-readme', path: 'README.md' },
				status: fileDisplaySnapshot.fileStatusSlice,
			}),
		).toMatchObject({ status: 'loading', fileId: 'file-readme', path: 'README.md' });
		expect(
			bridgeFileViewerOpenStateForSelection({
				contentAvailability: { state: 'ready' },
				displayItem: readme ?? null,
				hasPierreItem: true,
				selection: { fileId: 'file-readme', path: 'README.md' },
				status: fileDisplaySnapshot.fileStatusSlice,
			}),
		).toMatchObject({ status: 'ready' });
		expect(
			bridgeFileViewerOpenStateForSelection({
				contentAvailability: null,
				displayItem: binary ?? null,
				hasPierreItem: false,
				selection: { fileId: 'file-binary', path: 'assets/logo.bin' },
				status: fileDisplaySnapshot.fileStatusSlice,
			}),
		).toMatchObject({ status: 'unavailable' });
		expect(
			bridgeFileViewerOpenStateForSelection({
				contentAvailability: { state: 'ready' },
				displayItem: readme ?? null,
				hasPierreItem: true,
				selection: { fileId: 'file-readme', path: 'README.md' },
				status: { state: 'stale' },
			}),
		).toMatchObject({ status: 'ready' });
	});
});

function collectionDirectoryRow(
	path: string,
	index: number,
): Parameters<
	ReturnType<typeof BridgeMainFileTreeDisplayIndex.empty>['applyOperations']
>[0][number] {
	return {
		operation: 'upsert',
		row: {
			changeStatus: null,
			depth: 0,
			documentLocation: null,
			fileId: null,
			fileClass: null,
			isDirectory: true,
			lineCount: null,
			name: path,
			parentPath: null,
			path,
			projectionIndex: index,
			rowId: `row-${path}`,
			sizeBytes: null,
		},
	};
}

function collectionFileRow(props: {
	readonly documentLocation?: string;
	readonly fileId: string;
	readonly index: number;
	readonly path: string;
}): Parameters<
	ReturnType<typeof BridgeMainFileTreeDisplayIndex.empty>['applyOperations']
>[0][number] {
	const segments = props.path.split('/');
	return {
		operation: 'upsert',
		row: {
			changeStatus: null,
			depth: segments.length - 1,
			documentLocation: props.documentLocation ?? null,
			fileId: props.fileId,
			fileClass: 'source',
			isDirectory: false,
			lineCount: 1,
			name: segments.at(-1) ?? props.path,
			parentPath: segments.slice(0, -1).join('/'),
			path: props.path,
			projectionIndex: props.index,
			rowId: `row-${props.fileId}`,
			sizeBytes: 10,
		},
	};
}
