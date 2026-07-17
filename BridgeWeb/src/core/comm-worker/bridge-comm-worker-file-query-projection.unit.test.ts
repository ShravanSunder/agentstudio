import { describe, expect, test } from 'vitest';

import {
	BridgeCommWorkerFileQueryProjection,
	type BridgeCommWorkerFileQueryProjectionResult,
} from './bridge-comm-worker-file-query-projection.js';
import type { BridgeWorkerFileDisplayPatch } from './bridge-worker-contracts.js';
import type { BridgeWorkerFileQuery } from './bridge-worker-file-query-contracts.js';

describe('Bridge comm worker File query projection', () => {
	test('owns text, regex, availability filtering, and invalid regex errors', () => {
		expect(projectedPaths(resultForQuery(query({ searchText: 'readme' })))).toEqual(['README.md']);
		expect(projectedPaths(resultForQuery(query({ searchText: 'assets' })))).toEqual([
			'assets/logo.bin',
		]);
		expect(
			projectedPaths(resultForQuery(query({ searchMode: 'regex', searchText: '\\.bin$' }))),
		).toEqual(['assets/logo.bin']);
		expect(projectedPaths(resultForQuery(query({ filterMode: 'fetchable' })))).toEqual([
			'assets',
			'README.md',
		]);
		expect(projectedPaths(resultForQuery(query({ filterMode: 'unavailable' })))).toEqual([
			'assets',
			'assets/logo.bin',
		]);

		const invalid = resultForQuery(query({ searchMode: 'regex', searchText: '[' }));
		expect(projectedPaths(invalid)).toEqual([]);
		expect(queryStatus(invalid)).toMatchObject({
			projectedRowCount: 0,
			searchMode: 'regex',
			searchText: '[',
			totalRowCount: 3,
		});
		expect(queryStatus(invalid).searchError).toContain('regular expression');
	});

	test('retains query through metadata events and reevaluates only affected rows', () => {
		const scheduler = new DeterministicFileQueryScheduler();
		const projection = makeProjection(scheduler);
		projection.applyDisplayPatches(baseDisplayPatches());
		applyQueryAndDrain(
			projection,
			scheduler,
			query({ filterMode: 'fetchable', searchText: 'late' }),
		);

		const rowDelta = projection.applyDisplayPatches([
			fileTreeBatch([fileTreeRowOperation('row-late', 'file-late', 'late.ts', 3)]),
		]);
		expect(rowDelta.evaluatedRowCount).toBe(1);
		expect(projectedPaths(rowDelta)).toEqual([]);

		const descriptorDelta = projection.applyDisplayPatches([
			fileItemPatch('file-late', 'late.ts', 'available'),
		]);
		expect(descriptorDelta.evaluatedRowCount).toBe(1);
		expect(projectedPaths(descriptorDelta)).toEqual(['late.ts']);
		expect(queryStatus(descriptorDelta)).toMatchObject({
			filterMode: 'fetchable',
			searchText: 'late',
			projectedRowCount: 1,
			totalRowCount: 4,
		});
	});

	test('keeps replacement commit behind every projected row batch from the same publication', () => {
		const projection = makeProjection(new DeterministicFileQueryScheduler());

		const result = projection.applyDisplayPatches([
			{
				operation: 'reset',
				payload: { sourceGeneration: 2, sourceId: 'source-2' },
				slice: 'fileTree',
			},
			fileTreeBatch([
				fileTreeRowOperation('row-one', 'file-one', 'One.swift', 0),
				fileTreeRowOperation('row-two', 'file-two', 'Two.swift', 1),
			]),
			{
				operation: 'replacementCommit',
				payload: { sourceGeneration: 2, sourceId: 'source-2' },
				slice: 'fileTree',
			},
		]);

		expect(
			result.patches.flatMap((patch): readonly string[] =>
				patch.slice === 'fileTree' ? [patch.operation] : [],
			),
		).toEqual(['reset', 'batch', 'replacementCommit']);
	});

	test('treats duplicate query and empty metadata patches as zero-work no-ops', () => {
		const scheduler = new DeterministicFileQueryScheduler();
		const projection = makeProjection(scheduler);
		projection.applyDisplayPatches(baseDisplayPatches());
		applyQueryAndDrain(projection, scheduler, query({ searchText: 'readme' }));

		const publishedResults: BridgeCommWorkerFileQueryProjectionResult[] = [];
		const duplicateScheduled = projection.updateQuery({
			publish: (result): void => {
				publishedResults.push(result);
			},
			query: query({ searchText: 'readme' }),
		});
		const empty = projection.applyDisplayPatches([]);

		expect(duplicateScheduled).toBe(false);
		expect(scheduler.pendingCount).toBe(0);
		expect(publishedResults).toEqual([]);
		expect(empty).toEqual({ evaluatedRowCount: 0, patches: [], queryTransactionId: null });
	});

	test('keeps a 10k-row metadata delta O(delta) and chunks projected operations', () => {
		const scheduler = new DeterministicFileQueryScheduler();
		const projection = makeProjection(scheduler);
		const rowOperations = Array.from({ length: 10_000 }, (_, index) =>
			fileTreeRowOperation(
				`row-${String(index)}`,
				`file-${String(index)}`,
				`Sources/File-${String(index).padStart(5, '0')}.swift`,
				index,
			),
		);
		projection.applyDisplayPatches(chunkTreeOperations(rowOperations));

		const filtered = applyQueryAndDrain(projection, scheduler, query({ searchText: 'File-09999' }));
		expect(filtered.evaluatedRowCount).toBe(10_000);
		expect(projectedPaths(filtered)).toEqual(['Sources/File-09999.swift']);
		expect(maximumTreeOperationCount(filtered)).toBeLessThanOrEqual(256);

		const delta = projection.applyDisplayPatches([
			fileTreeBatch([
				fileTreeRowOperation('row-9999', 'file-9999', 'Sources/Renamed.swift', 9_999),
			]),
		]);
		expect(delta.evaluatedRowCount).toBe(1);
		expect(maximumTreeOperationCount(delta)).toBeLessThanOrEqual(256);
	});

	test('chunks a 100k query and suppresses superseded query generations', () => {
		const scheduler = new DeterministicFileQueryScheduler();
		const evaluatedChunks: number[] = [];
		const projection = makeProjection(scheduler, evaluatedChunks);
		const rowOperations = Array.from({ length: 100_000 }, (_, index) =>
			fileTreeRowOperation(
				`row-${String(index)}`,
				`file-${String(index)}`,
				`Sources/File-${String(index).padStart(6, '0')}.swift`,
				index,
			),
		);
		projection.applyDisplayPatches(chunkTreeOperations(rowOperations));
		const publishedResults: BridgeCommWorkerFileQueryProjectionResult[] = [];
		projection.updateQuery({
			publish: (result): void => {
				publishedResults.push(result);
			},
			query: query({ searchText: 'File-099999' }),
		});

		scheduler.runNext();
		expect(evaluatedChunks).toEqual([128]);
		expect(publishedResults).toEqual([]);

		projection.updateQuery({
			publish: (result): void => {
				publishedResults.push(result);
			},
			query: query({ searchText: 'File-000001' }),
		});
		scheduler.runAll();

		expect(Math.max(...evaluatedChunks)).toBeLessThanOrEqual(128);
		expect(publishedResults).toHaveLength(1);
		expect(queryStatus(publishedResults[0] ?? noResult())).toMatchObject({
			searchText: 'File-000001',
			projectedRowCount: 1,
			totalRowCount: 100_000,
		});
	});

	test('rebuilds the complete published display state for fail-closed resync', () => {
		const scheduler = new DeterministicFileQueryScheduler();
		const projection = makeProjection(scheduler);
		projection.applyDisplayPatches([
			...baseDisplayPatches(),
			{
				operation: 'upsert',
				payload: {
					ahead: 1,
					behind: 0,
					branchName: 'main',
					staged: 2,
					state: 'ready',
					unstaged: 3,
					untracked: 4,
				},
				slice: 'fileStatus',
			},
		]);
		applyQueryAndDrain(projection, scheduler, query({ searchText: 'readme' }));

		const snapshot = projection.snapshotDisplayPatches();

		expect(snapshot.slice(0, 3)).toEqual([
			{
				operation: 'reset',
				payload: { sourceGeneration: 1, sourceId: 'source-1' },
				slice: 'fileTree',
			},
			{ operation: 'reset', slice: 'fileItem' },
			{ operation: 'reset', slice: 'fileStatus' },
		]);
		expect(
			projectedPaths({ evaluatedRowCount: 0, patches: snapshot, queryTransactionId: null }),
		).toEqual(['README.md']);
		expect(snapshot).toContainEqual(fileItemPatch('file-readme', 'README.md', 'available'));
		expect(snapshot).toContainEqual(expect.objectContaining({ slice: 'fileStatus' }));
		expect(
			queryStatus({ evaluatedRowCount: 0, patches: snapshot, queryTransactionId: null }),
		).toMatchObject({
			projectedRowCount: 1,
			searchText: 'readme',
			totalRowCount: 3,
		});
	});

	test('does not synthesize replacement completion in a partial resync snapshot', () => {
		const projection = makeProjection(new DeterministicFileQueryScheduler());
		projection.applyDisplayPatches([
			{
				operation: 'reset',
				payload: { sourceGeneration: 2, sourceId: 'source-2' },
				slice: 'fileTree',
			},
			fileTreeBatch([fileTreeRowOperation('row-partial', 'file-partial', 'Partial.swift', 0)]),
		]);

		const snapshot = projection.snapshotDisplayPatches();

		expect(
			snapshot.some(
				(patch): boolean => patch.slice === 'fileTree' && patch.operation === 'replacementCommit',
			),
		).toBe(false);
	});
});

class DeterministicFileQueryScheduler {
	readonly #pending: Array<() => void> = [];

	get pendingCount(): number {
		return this.#pending.length;
	}

	readonly schedule = (runChunk: () => void): void => {
		this.#pending.push(runChunk);
	};

	runNext(): void {
		const runChunk = this.#pending.shift();
		if (runChunk === undefined) throw new Error('Expected a pending File query chunk.');
		runChunk();
	}

	runAll(): void {
		while (this.#pending.length > 0) this.runNext();
	}
}

function makeProjection(
	scheduler: DeterministicFileQueryScheduler,
	evaluatedChunks: number[] = [],
): BridgeCommWorkerFileQueryProjection {
	return new BridgeCommWorkerFileQueryProjection({
		maximumRowsPerQueryChunk: 128,
		recordEvaluatedQueryChunk: (evaluatedRowCount): void => {
			evaluatedChunks.push(evaluatedRowCount);
		},
		scheduleQueryChunk: scheduler.schedule,
	});
}

function applyQueryAndDrain(
	projection: BridgeCommWorkerFileQueryProjection,
	scheduler: DeterministicFileQueryScheduler,
	fileQuery: BridgeWorkerFileQuery,
): BridgeCommWorkerFileQueryProjectionResult {
	const results: BridgeCommWorkerFileQueryProjectionResult[] = [];
	const scheduled = projection.updateQuery({
		publish: (result): void => {
			results.push(result);
		},
		query: fileQuery,
	});
	if (!scheduled) throw new Error('Expected File query projection to be scheduled.');
	scheduler.runAll();
	const result = results[0];
	if (result === undefined) throw new Error('Expected File query projection result.');
	return result;
}

function resultForQuery(
	fileQuery: BridgeWorkerFileQuery,
): BridgeCommWorkerFileQueryProjectionResult {
	const scheduler = new DeterministicFileQueryScheduler();
	const projection = makeProjection(scheduler);
	projection.applyDisplayPatches(baseDisplayPatches());
	return applyQueryAndDrain(projection, scheduler, fileQuery);
}

function noResult(): BridgeCommWorkerFileQueryProjectionResult {
	return { evaluatedRowCount: 0, patches: [], queryTransactionId: null };
}

function query(overrides: Partial<BridgeWorkerFileQuery> = {}): BridgeWorkerFileQuery {
	return {
		filterMode: 'all',
		searchMode: 'text',
		searchText: '',
		...overrides,
	};
}

function baseDisplayPatches(): readonly BridgeWorkerFileDisplayPatch[] {
	return [
		{
			operation: 'reset',
			payload: { sourceGeneration: 1, sourceId: 'source-1' },
			slice: 'fileTree',
		},
		fileTreeBatch([
			fileTreeRowOperation('row-assets', null, 'assets', 0, true),
			fileTreeRowOperation('row-logo', 'file-logo', 'assets/logo.bin', 1),
			fileTreeRowOperation('row-readme', 'file-readme', 'README.md', 2),
		]),
		fileItemPatch('file-logo', 'assets/logo.bin', 'binary'),
		fileItemPatch('file-readme', 'README.md', 'available'),
	];
}

function fileTreeRowOperation(
	rowId: string,
	fileId: string | null,
	path: string,
	projectionIndex: number,
	isDirectory = false,
): FileTreeOperation {
	const pathSegments = path.split('/');
	return {
		operation: 'upsert',
		row: {
			changeStatus: null,
			depth: pathSegments.length - 1,
			fileId,
			isDirectory,
			lineCount: null,
			name: pathSegments.at(-1) ?? path,
			parentPath: pathSegments.length === 1 ? null : pathSegments.slice(0, -1).join('/'),
			path,
			projectionIndex,
			rowId,
			sizeBytes: isDirectory ? null : 10,
		},
	};
}

function fileTreeBatch(operations: readonly FileTreeOperation[]): FileTreePatch {
	return { operation: 'batch', payload: { operations }, slice: 'fileTree' };
}

function chunkTreeOperations(
	operations: readonly FileTreeOperation[],
): readonly BridgeWorkerFileDisplayPatch[] {
	const patches: BridgeWorkerFileDisplayPatch[] = [];
	for (let index = 0; index < operations.length; index += 256) {
		patches.push(fileTreeBatch(operations.slice(index, index + 256)));
	}
	return patches;
}

function fileItemPatch(
	itemId: string,
	displayPath: string,
	availability: 'available' | 'binary',
): BridgeWorkerFileDisplayPatch {
	return {
		itemId,
		operation: 'upsert',
		payload: {
			availability: { kind: availability },
			displayPath,
			endsMidLine: false,
			endsWithNewline: availability === 'available',
			extent:
				availability === 'available'
					? { kind: 'exactLineCount', lineCount: 1 }
					: { kind: 'unavailable' },
			fileExtension: displayPath.split('.').at(-1) ?? null,
			language: availability === 'available' ? 'text' : null,
			payloadByteCount: availability === 'available' ? 10 : 0,
			payloadLineCount: availability === 'available' ? 1 : 0,
			rowId: `row-for-${itemId}`,
			sizeBytes: 10,
			totalLineCount: availability === 'available' ? 1 : null,
			truncationKind: 'none',
		},
		slice: 'fileItem',
	};
}

type FileTreePatch = Extract<
	BridgeWorkerFileDisplayPatch,
	{ readonly operation: 'batch'; readonly slice: 'fileTree' }
>;
type FileTreeOperation = FileTreePatch['payload']['operations'][number];

function projectedPaths(result: BridgeCommWorkerFileQueryProjectionResult): readonly string[] {
	return result.patches.flatMap((patch): readonly string[] =>
		patch.slice !== 'fileTree' || patch.operation !== 'batch'
			? []
			: patch.payload.operations.flatMap((operation): readonly string[] =>
					operation.operation === 'upsert' ? [operation.row.path] : [],
				),
	);
}

function queryStatus(result: BridgeCommWorkerFileQueryProjectionResult): QueryStatus {
	const patch = result.patches.find(
		(candidate): candidate is QueryPatch =>
			candidate.slice === 'fileQuery' && candidate.operation === 'upsert',
	);
	if (patch === undefined) throw new Error('Expected a File query status patch.');
	return patch.payload;
}

type QueryPatch = Extract<
	BridgeWorkerFileDisplayPatch,
	{ readonly operation: 'upsert'; readonly slice: 'fileQuery' }
>;
type QueryStatus = QueryPatch['payload'];

function maximumTreeOperationCount(result: BridgeCommWorkerFileQueryProjectionResult): number {
	return Math.max(
		0,
		...result.patches.flatMap((patch): readonly number[] =>
			patch.slice === 'fileTree' && patch.operation === 'batch'
				? [patch.payload.operations.length]
				: [],
		),
	);
}
