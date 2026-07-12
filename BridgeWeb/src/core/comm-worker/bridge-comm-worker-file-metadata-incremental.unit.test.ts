import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerFileMetadataProjection } from './bridge-comm-worker-file-metadata-projection.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';

const source = {
	repoId: '00000000-0000-4000-8000-000000000001',
	rootRevisionToken: 'root-revision-large',
	sourceCursor: 'source-cursor-large',
	sourceId: 'file-source-large',
	subscriptionGeneration: 9,
	worktreeId: '00000000-0000-4000-8000-000000000002',
} as const;

describe('Bridge comm worker incremental File metadata projection', () => {
	test('repairs a child when its parent arrives after the child', () => {
		const projection = new BridgeCommWorkerFileMetadataProjection();
		projection.apply({ eventKind: 'file.sourceAccepted', source });
		const child = projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: false,
			lineage: { lane: 'visible', loadedBy: 'visible' },
			pathScope: [],
			rows: [makeFileTreeRow(1)],
			source,
			startIndex: 1,
			totalRowCount: null,
		});

		const parent = projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'visible', loadedBy: 'visible' },
			pathScope: [],
			rows: [makeSourcesRow('row-sources')],
			source,
			startIndex: 0,
			totalRowCount: 2,
		});

		expect(child.runtimeMutation).toMatchObject({
			rowUpserts: [{ id: 'file-1', index: 1, parentId: null }],
		});
		expect(parent.runtimeMutation).toMatchObject({
			rowUpserts: [
				{ id: 'row-sources', index: 0, parentId: null },
				{ id: 'file-1', index: 1, parentId: 'row-sources' },
			],
		});
	});

	test('repairs direct children when a parent is removed or replaced', () => {
		const projection = new BridgeCommWorkerFileMetadataProjection();
		projection.apply({ eventKind: 'file.sourceAccepted', source });
		projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'visible', loadedBy: 'startup_window' },
			pathScope: [],
			rows: [makeSourcesRow('row-sources'), makeFileTreeRow(1)],
			source,
			startIndex: 0,
			totalRowCount: 2,
		});

		const removed = projection.apply({
			eventKind: 'file.treeDelta',
			operations: [{ op: 'removeRows', paths: ['Sources'], rowIds: ['row-sources'] }],
			source,
		});
		const replaced = projection.apply({
			eventKind: 'file.treeDelta',
			operations: [{ op: 'upsertRows', rows: [makeSourcesRow('row-sources-next')] }],
			source,
		});

		expect(removed.runtimeMutation).toMatchObject({
			rowRemovals: ['row-sources'],
			rowUpserts: [{ id: 'file-1', index: 1, parentId: null }],
		});
		expect(replaced.runtimeMutation).toMatchObject({
			rowUpserts: [
				{ id: 'row-sources-next', index: 2, parentId: null },
				{ id: 'file-1', index: 1, parentId: 'row-sources-next' },
			],
		});
	});

	test('publishes the final child parent when one delta removes and replaces its parent', () => {
		const projection = new BridgeCommWorkerFileMetadataProjection();
		projection.apply({ eventKind: 'file.sourceAccepted', source });
		projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'visible', loadedBy: 'startup_window' },
			pathScope: [],
			rows: [makeSourcesRow('row-sources'), makeFileTreeRow(1)],
			source,
			startIndex: 0,
			totalRowCount: 2,
		});

		const replaced = projection.apply({
			eventKind: 'file.treeDelta',
			operations: [
				{ op: 'removeRows', paths: ['Sources'], rowIds: ['row-sources'] },
				{ op: 'upsertRows', rows: [makeSourcesRow('row-sources-next')] },
			],
			source,
		});

		expect(replaced.runtimeMutation).toMatchObject({
			rowUpserts: [
				{ id: 'file-1', index: 1, parentId: 'row-sources-next' },
				{ id: 'row-sources-next', index: 2, parentId: null },
			],
		});
	});

	test('keeps one status and descriptor delta bounded after 3,420 rows', () => {
		let visitedMembers = 0;
		const projection = new BridgeCommWorkerFileMetadataProjection({
			recordVisitedMember: (): void => {
				visitedMembers += 1;
			},
		});
		projection.apply({ eventKind: 'file.sourceAccepted', source });
		projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'visible', loadedBy: 'startup_window' },
			pathScope: [],
			rows: Array.from({ length: 3_420 }, (_, index) => makeFileTreeRow(index)),
			source,
			startIndex: 0,
			totalRowCount: 3_420,
		});
		visitedMembers = 0;

		const status = projection.apply({
			eventKind: 'file.statusPatch',
			patch: { patchKind: 'path', path: 'Sources/File1710.swift', status: 'added' },
			source,
		});
		const statusVisitedMembers = visitedMembers;
		visitedMembers = 0;
		const descriptor = projection.apply(makeDescriptorReadyEvent(1_710));
		const descriptorVisitedMembers = visitedMembers;

		expect(statusVisitedMembers).toBeLessThanOrEqual(2);
		expect(status.runtimeMutation).toBeNull();
		expect(descriptorVisitedMembers).toBeLessThanOrEqual(2);
		expect(descriptor.runtimeMutation).toMatchObject({
			contentRemovals: [],
			contentRequestRemovals: [],
			contentRequestUpserts: [{ itemId: 'file-1710' }],
			contentUpserts: [{ itemId: 'file-1710' }],
			filePathRemovals: [],
			filePathUpserts: [],
			kind: 'delta',
			rowRemovals: [],
			rowUpserts: [],
		});
	});

	test('does not publish runtime source for unchanged row, status, or descriptor facts', () => {
		let visitedMembers = 0;
		const projection = new BridgeCommWorkerFileMetadataProjection({
			recordVisitedMember: (): void => {
				visitedMembers += 1;
			},
		});
		projection.apply({ eventKind: 'file.sourceAccepted', source });
		projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'visible', loadedBy: 'startup_window' },
			pathScope: [],
			rows: Array.from({ length: 3_420 }, (_, index) => makeFileTreeRow(index)),
			source,
			startIndex: 0,
			totalRowCount: 3_420,
		});
		projection.apply(makeDescriptorReadyEvent(1_710));
		projection.apply({
			eventKind: 'file.statusPatch',
			patch: { patchKind: 'path', path: 'Sources/File1710.swift', status: 'modified' },
			source,
		});
		visitedMembers = 0;

		const row = projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: false,
			lineage: { lane: 'visible', loadedBy: 'visible' },
			pathScope: [],
			rows: [makeFileTreeRow(1_710)],
			source,
			startIndex: 1_710,
			totalRowCount: 3_420,
		});
		const status = projection.apply({
			eventKind: 'file.statusPatch',
			patch: { patchKind: 'path', path: 'Sources/File1710.swift', status: 'modified' },
			source,
		});
		const descriptor = projection.apply(makeDescriptorReadyEvent(1_710));

		expect(visitedMembers).toBeLessThanOrEqual(6);
		expect(row.runtimeMutation).toBeNull();
		expect(status.runtimeMutation).toBeNull();
		expect(descriptor.runtimeMutation).toBeNull();
		expect(row.patches).toEqual([]);
		expect(status.patches).toEqual([]);
		expect(descriptor.patches).toEqual([]);
	});
});

function makeFileTreeRow(index: number): FileTreeRow {
	return {
		changeStatus: 'modified',
		depth: 1,
		fileId: `file-${index}`,
		isDirectory: false,
		lineCount: 3,
		name: `File${index}.swift`,
		parentPath: 'Sources',
		path: `Sources/File${index}.swift`,
		rowId: `row-file-${index}`,
		sizeBytes: 24,
	};
}

function makeSourcesRow(rowId: string): FileTreeRow {
	return {
		changeStatus: null,
		depth: 0,
		fileId: null,
		isDirectory: true,
		lineCount: null,
		name: 'Sources',
		parentPath: null,
		path: 'Sources',
		rowId,
		sizeBytes: null,
	};
}

function makeDescriptorReadyEvent(index: number): FileDescriptorReadyEvent {
	return {
		availability: {
			availabilityKind: 'available',
			contentDescriptor: {
				contentKind: 'file.content',
				declaredByteLength: 24,
				descriptorId: `descriptor-file-${index}`,
				encoding: 'utf-8',
				expectedSha256: 'a'.repeat(64),
				fileId: `file-${index}`,
				maximumBytes: 2 * 1024 * 1024,
				source,
				window: {
					kind: 'prefix',
					maximumBytes: 2 * 1024 * 1024,
					maximumLines: 10_000,
					startByte: 0,
				},
			},
		},
		encoding: 'utf-8',
		endsMidLine: false,
		endsWithNewline: true,
		estimatedContentHeightPixels: null,
		eventKind: 'file.descriptorReady',
		fileExtension: 'swift',
		fileId: `file-${index}`,
		language: 'swift',
		modifiedAtUnixMilliseconds: 1,
		path: `Sources/File${index}.swift`,
		payloadByteCount: 24,
		payloadLineCount: 3,
		rowId: `row-file-${index}`,
		sizeBytes: 24,
		source,
		totalLineCount: 3,
		truncationKind: 'none',
		virtualizedExtentKind: 'exactLineCount',
	};
}

type FileMetadataEvent = BridgeProductSubscriptionEvent<'file.metadata'>;
type FileDescriptorReadyEvent = Extract<
	FileMetadataEvent,
	{ readonly eventKind: 'file.descriptorReady' }
>;
type FileTreeRow = Extract<
	FileMetadataEvent,
	{ readonly eventKind: 'file.treeWindow' }
>['rows'][number];
