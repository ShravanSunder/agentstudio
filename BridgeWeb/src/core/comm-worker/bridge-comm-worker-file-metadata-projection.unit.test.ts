import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerFileMetadataProjection } from './bridge-comm-worker-file-metadata-projection.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import { bridgeWorkerFileDisplayPatchSchema } from './bridge-worker-contracts.js';

const source = {
	repoId: '00000000-0000-4000-8000-000000000001',
	rootRevisionToken: 'root-revision-1',
	sourceCursor: 'source-cursor-1',
	sourceId: 'file-source-1',
	subscriptionGeneration: 3,
	worktreeId: '00000000-0000-4000-8000-000000000002',
} as const;

describe('Bridge comm worker File metadata projection', () => {
	test('maps every File metadata event kind to bounded strict display patches', () => {
		// Arrange
		const projection = new BridgeCommWorkerFileMetadataProjection();

		// Act
		const sourceAccepted = projection.apply({ eventKind: 'file.sourceAccepted', source });
		const treeWindow = projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'visible', loadedBy: 'startup_window' },
			pathScope: [],
			rows: [makeFileTreeRow()],
			source,
			startIndex: 0,
			totalRowCount: 1,
		});
		const treeDelta = projection.apply({
			eventKind: 'file.treeDelta',
			operations: [
				{
					op: 'upsertRows',
					rows: [{ ...makeFileTreeRow(), changeStatus: 'added' }],
				},
			],
			source,
		});
		const statusPatch = projection.apply({
			eventKind: 'file.statusPatch',
			patch: {
				ahead: 1,
				behind: 2,
				branchName: 'main',
				patchKind: 'summary',
				staged: 3,
				unstaged: 4,
				untracked: 5,
			},
			source,
		});
		const descriptorReady = projection.apply(makeAvailableDescriptorReadyEvent());
		const invalidated = projection.apply({
			eventKind: 'file.invalidated',
			fileId: 'file-1',
			path: 'Sources/File.swift',
			reason: 'contentChanged',
			replacementDescriptor: null,
			source,
		});

		// Assert
		expect(sourceAccepted).toMatchObject({
			patches: [
				{
					operation: 'reset',
					payload: { sourceGeneration: 3, sourceId: 'file-source-1' },
					slice: 'fileTree',
				},
				{ operation: 'reset', slice: 'fileItem' },
				{ operation: 'reset', slice: 'fileStatus' },
			],
			projectionRevision: 1,
		});
		expect(treeWindow.patches).toEqual([
			{
				operation: 'batch',
				payload: {
					operations: [
						{
							operation: 'upsert',
							row: { ...makeFileTreeRow(), projectionIndex: 0 },
						},
					],
				},
				slice: 'fileTree',
			},
			{
				operation: 'replacementCommit',
				payload: { sourceGeneration: 3, sourceId: 'file-source-1' },
				slice: 'fileTree',
			},
		]);
		expect(treeDelta.patches).toEqual([
			{
				operation: 'batch',
				payload: {
					operations: [
						{
							operation: 'upsert',
							row: { ...makeFileTreeRow(), changeStatus: 'added', projectionIndex: 0 },
						},
					],
				},
				slice: 'fileTree',
			},
		]);
		expect(statusPatch.patches).toEqual([
			{
				operation: 'upsert',
				payload: {
					ahead: 1,
					behind: 2,
					branchName: 'main',
					staged: 3,
					state: 'ready',
					unstaged: 4,
					untracked: 5,
				},
				slice: 'fileStatus',
			},
		]);
		expect(descriptorReady.patches).toEqual([
			{
				itemId: 'file-1',
				operation: 'upsert',
				payload: {
					availability: { kind: 'available' },
					displayPath: 'Sources/File.swift',
					endsMidLine: false,
					endsWithNewline: true,
					extent: { kind: 'exactLineCount', lineCount: 3 },
					fileExtension: 'swift',
					language: 'swift',
					payloadByteCount: 24,
					payloadLineCount: 3,
					rowId: 'row-file-1',
					sizeBytes: 24,
					totalLineCount: 3,
					truncationKind: 'none',
				},
				slice: 'fileItem',
			},
		]);
		expect(invalidated).toMatchObject({
			patches: [{ itemId: 'file-1', operation: 'delete', slice: 'fileItem' }],
			projectionRevision: 6,
		});
		for (const result of [
			sourceAccepted,
			treeWindow,
			treeDelta,
			statusPatch,
			descriptorReady,
			invalidated,
		]) {
			for (const patch of result.patches) {
				expect(bridgeWorkerFileDisplayPatchSchema.safeParse(patch).success).toBe(true);
			}
		}
		expect(JSON.stringify(descriptorReady.patches)).not.toMatch(
			/contentDescriptor|descriptorId|expectedSha256|sourceCursor|leaseId/,
		);
	});

	test('diffs replacement windows and chunks 257 tree operations into 256 plus one', () => {
		// Arrange
		const projection = new BridgeCommWorkerFileMetadataProjection();
		projection.apply({ eventKind: 'file.sourceAccepted', source });
		projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'visible', loadedBy: 'startup_window' },
			pathScope: [],
			rows: [makeIndexedFileTreeRow(999)],
			source,
			startIndex: 0,
			totalRowCount: 1,
		});

		// Act
		const result = projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'visible', loadedBy: 'replacement' },
			pathScope: [],
			rows: Array.from({ length: 256 }, (_, index) => makeIndexedFileTreeRow(index)),
			source,
			startIndex: 0,
			totalRowCount: 256,
		});

		// Assert
		expect(result.patches).toHaveLength(3);
		expect(
			result.patches.map((patch) =>
				patch.slice === 'fileTree' && patch.operation === 'batch'
					? patch.payload.operations.length
					: null,
			),
		).toEqual([256, 1, null]);
		const firstPatch = result.patches[0];
		expect(firstPatch).toMatchObject({ operation: 'batch', slice: 'fileTree' });
		expect(
			firstPatch?.slice === 'fileTree' && firstPatch.operation === 'batch'
				? firstPatch.payload.operations[0]
				: null,
		).toEqual({
			operation: 'remove',
			path: 'Sources/File999.swift',
			rowId: 'row-file-999',
		});
		expect(result.patches.at(-1)).toEqual({
			operation: 'replacementCommit',
			payload: { sourceGeneration: 3, sourceId: 'file-source-1' },
			slice: 'fileTree',
		});
	});

	test('emits delta replacements and removals without shifting unaffected projection indexes', () => {
		// Arrange
		const projection = new BridgeCommWorkerFileMetadataProjection();
		projection.apply({ eventKind: 'file.sourceAccepted', source });
		projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'visible', loadedBy: 'startup_window' },
			pathScope: [],
			rows: [makeIndexedFileTreeRow(0), makeIndexedFileTreeRow(1), makeIndexedFileTreeRow(2)],
			source,
			startIndex: 0,
			totalRowCount: 3,
		});

		// Act
		const result = projection.apply({
			eventKind: 'file.treeDelta',
			operations: [
				{
					op: 'removeRows',
					paths: ['Sources/File0.swift'],
					rowIds: ['row-file-0'],
				},
				{
					op: 'upsertRows',
					rows: [
						{
							...makeIndexedFileTreeRow(2),
							fileId: 'file-replacement',
							name: 'Replacement.swift',
							path: 'Sources/Replacement.swift',
							rowId: 'row-file-2',
						},
					],
				},
			],
			source,
		});

		// Assert
		const operations = result.patches.flatMap((patch) =>
			patch.slice === 'fileTree' && patch.operation === 'batch' ? patch.payload.operations : [],
		);
		expect(operations).toEqual([
			{ operation: 'remove', path: 'Sources/File0.swift', rowId: 'row-file-0' },
			{ operation: 'remove', path: 'Sources/File2.swift', rowId: 'row-file-2' },
			{
				operation: 'upsert',
				row: {
					...makeIndexedFileTreeRow(2),
					fileId: 'file-replacement',
					name: 'Replacement.swift',
					path: 'Sources/Replacement.swift',
					projectionIndex: 2,
					rowId: 'row-file-2',
				},
			},
		]);
	});

	test('preserves absolute projection indexes for sparse tree windows', () => {
		// Arrange
		const projection = new BridgeCommWorkerFileMetadataProjection();
		projection.apply({ eventKind: 'file.sourceAccepted', source });

		// Act
		const result = projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: false,
			lineage: { lane: 'visible', loadedBy: 'visible' },
			pathScope: [],
			rows: [makeIndexedFileTreeRow(2)],
			source,
			startIndex: 2,
			totalRowCount: null,
		});

		// Assert
		expect(result.runtimeMutation).toMatchObject({
			kind: 'delta',
			rowUpserts: [{ id: 'file-2', index: 2, parentId: null }],
		});
		expect(result.patches).toEqual([
			{
				operation: 'batch',
				payload: {
					operations: [
						{
							operation: 'upsert',
							row: { ...makeIndexedFileTreeRow(2), projectionIndex: 2 },
						},
					],
				},
				slice: 'fileTree',
			},
		]);
	});

	test('keeps projection revisions monotonic across source resets and emits all slice resets', () => {
		// Arrange
		const projection = new BridgeCommWorkerFileMetadataProjection();
		const nextSource = {
			...source,
			rootRevisionToken: 'root-revision-2',
			sourceCursor: 'source-cursor-2',
			sourceId: 'file-source-2',
			subscriptionGeneration: 4,
		};

		// Act
		const first = projection.apply({ eventKind: 'file.sourceAccepted', source });
		const second = projection.apply({ eventKind: 'file.sourceAccepted', source: nextSource });
		const third = projection.apply({
			eventKind: 'file.invalidated',
			fileId: null,
			path: 'Sources',
			reason: 'sourceReset',
			replacementDescriptor: null,
			source: nextSource,
		});

		// Assert
		expect([first.projectionRevision, second.projectionRevision, third.projectionRevision]).toEqual(
			[1, 2, 3],
		);
		expect(second.patches).toEqual([
			{
				operation: 'reset',
				payload: { sourceGeneration: 4, sourceId: 'file-source-2' },
				slice: 'fileTree',
			},
			{ operation: 'reset', slice: 'fileItem' },
			{ operation: 'reset', slice: 'fileStatus' },
		]);
		expect(third.patches).toEqual(second.patches);
	});

	test('projects streamed tree and descriptor facts into worker-owned File runtime state', () => {
		// Arrange
		const projection = new BridgeCommWorkerFileMetadataProjection();

		// Act
		projection.apply({ eventKind: 'file.sourceAccepted', source });
		projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'visible', loadedBy: 'startup_window' },
			pathScope: [],
			rows: [
				{
					changeStatus: null,
					depth: 0,
					fileId: null,
					isDirectory: true,
					lineCount: null,
					name: 'Sources',
					parentPath: null,
					path: 'Sources',
					rowId: 'row-sources',
					sizeBytes: null,
				},
				{
					changeStatus: 'modified',
					depth: 1,
					fileId: 'file-1',
					isDirectory: false,
					lineCount: 3,
					name: 'File.swift',
					parentPath: 'Sources',
					path: 'Sources/File.swift',
					rowId: 'row-file-1',
					sizeBytes: 24,
				},
			],
			source,
			startIndex: 0,
			totalRowCount: 2,
		});
		projection.apply(makeAvailableDescriptorReadyEvent());
		const availableDescriptor = makeAvailableDescriptorReadyEvent();
		if (availableDescriptor.availability.availabilityKind !== 'available') {
			throw new Error('Expected available File content descriptor.');
		}

		// Assert
		expect(projection.snapshot()).toEqual({
			contentItems: [
				{
					cacheKey: `file-content:descriptor-file-1:${'a'.repeat(64)}`,
					canFetchContent: true,
					contentHash: 'a'.repeat(64),
					descriptorId: 'descriptor-file-1',
					encoding: 'utf-8',
					endsMidLine: false,
					endsWithNewline: true,
					isBinary: false,
					itemId: 'file-1',
					language: 'swift',
					metadataKind: 'fileView',
					path: 'Sources/File.swift',
					payloadByteCount: 24,
					payloadLineCount: 3,
					sizeBytes: 24,
					totalLineCount: 3,
					truncationKind: 'none',
					virtualizedExtentKind: 'exactLineCount',
				},
			],
			contentRequests: [
				{
					contentDescriptor: availableDescriptor.availability.contentDescriptor,
					itemId: 'file-1',
					language: 'swift',
					path: 'Sources/File.swift',
					sizeBytes: 24,
				},
			],
			rows: [
				{ id: 'row-sources', index: 0, parentId: null },
				{ id: 'file-1', index: 1, parentId: 'row-sources' },
			],
			treeRows: expect.any(Array),
		});
	});

	test('applies deltas, status patches, and invalidation without retaining stale descriptors', () => {
		// Arrange
		const projection = new BridgeCommWorkerFileMetadataProjection();
		projection.apply({ eventKind: 'file.sourceAccepted', source });
		projection.apply({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'visible', loadedBy: 'startup_window' },
			pathScope: [],
			rows: [makeFileTreeRow()],
			source,
			startIndex: 0,
			totalRowCount: 1,
		});
		projection.apply(makeAvailableDescriptorReadyEvent());

		// Act
		projection.apply({
			eventKind: 'file.statusPatch',
			patch: { patchKind: 'path', path: 'Sources/File.swift', status: 'added' },
			source,
		});
		projection.apply({
			eventKind: 'file.invalidated',
			fileId: 'file-1',
			path: 'Sources/File.swift',
			reason: 'contentChanged',
			replacementDescriptor: null,
			source,
		});

		// Assert
		expect(projection.snapshot().treeRows[0]?.changeStatus).toBe('added');
		expect(projection.snapshot().contentItems).toEqual([]);
		expect(projection.snapshot().contentRequests).toEqual([]);
	});

	test('projects a line-limited prefix from payload facts without substituting total lines', () => {
		const projection = new BridgeCommWorkerFileMetadataProjection();
		projection.apply({ eventKind: 'file.sourceAccepted', source });
		const availableDescriptor = makeAvailableDescriptorReadyEvent();
		if (availableDescriptor.availability.availabilityKind !== 'available') {
			throw new Error('Expected available File content descriptor.');
		}
		projection.apply({
			...availableDescriptor,
			availability: {
				availabilityKind: 'available',
				contentDescriptor: {
					...availableDescriptor.availability.contentDescriptor,
					declaredByteLength: 100_000,
				},
			},
			payloadByteCount: 100_000,
			payloadLineCount: 10_000,
			sizeBytes: 120_000,
			totalLineCount: 12_000,
			truncationKind: 'lineLimit',
		});

		expect(projection.snapshot().contentItems[0]).toMatchObject({
			endsMidLine: false,
			endsWithNewline: true,
			payloadByteCount: 100_000,
			payloadLineCount: 10_000,
			totalLineCount: 12_000,
			truncationKind: 'lineLimit',
		});
		expect(projection.snapshot().contentItems[0]).not.toHaveProperty('lineCount');
	});
});

function makeAvailableDescriptorReadyEvent(): Extract<
	BridgeProductSubscriptionEvent<'file.metadata'>,
	{ readonly eventKind: 'file.descriptorReady' }
> {
	return {
		availability: {
			availabilityKind: 'available',
			contentDescriptor: {
				contentKind: 'file.content',
				declaredByteLength: 24,
				descriptorId: 'descriptor-file-1',
				encoding: 'utf-8',
				expectedSha256: 'a'.repeat(64),
				fileId: 'file-1',
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
		fileId: 'file-1',
		language: 'swift',
		modifiedAtUnixMilliseconds: 1,
		path: 'Sources/File.swift',
		payloadByteCount: 24,
		payloadLineCount: 3,
		rowId: 'row-file-1',
		sizeBytes: 24,
		source,
		totalLineCount: 3,
		truncationKind: 'none',
		virtualizedExtentKind: 'exactLineCount',
	};
}

function makeFileTreeRow(): Extract<
	BridgeProductSubscriptionEvent<'file.metadata'>,
	{ readonly eventKind: 'file.treeWindow' }
>['rows'][number] {
	return {
		changeStatus: 'modified',
		depth: 1,
		fileId: 'file-1',
		isDirectory: false,
		lineCount: 3,
		name: 'File.swift',
		parentPath: 'Sources',
		path: 'Sources/File.swift',
		rowId: 'row-file-1',
		sizeBytes: 24,
	};
}

function makeIndexedFileTreeRow(index: number): ReturnType<typeof makeFileTreeRow> {
	return {
		...makeFileTreeRow(),
		fileId: `file-${index}`,
		name: `File${index}.swift`,
		path: `Sources/File${index}.swift`,
		rowId: `row-file-${index}`,
	};
}
