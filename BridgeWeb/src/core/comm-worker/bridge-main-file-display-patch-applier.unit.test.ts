import { describe, expect, test } from 'vitest';

import { createBridgeMainRenderSnapshotStore } from './bridge-main-render-snapshot-store.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerFileDisplayPatch,
	type BridgeWorkerFileDisplayPatchEvent,
} from './bridge-worker-contracts.js';
type FileTreeBatchOperations = Extract<
	BridgeWorkerFileDisplayPatch,
	{ operation: 'batch'; slice: 'fileTree' }
>['payload']['operations'];
import { BridgeMainFileDisplayPatchApplier } from './bridge-main-file-display-patch-applier.js';

describe('Bridge main File display patch applier', () => {
	test('requires an explicit worker abort before a pre-terminal non-query patch', () => {
		const resyncRequests: unknown[] = [];
		const applier = new BridgeMainFileDisplayPatchApplier({
			requestResync: (request): void => {
				resyncRequests.push(request);
			},
		});
		applier.applyEvent(baseTreeEvent(1, [fileTreeUpsert('row-a', 'Sources/A.swift', 0)]));
		const cursor = applier.fileTreePatchStream.getCursor();
		applier.applyEvent(
			queryEvent({
				batchCount: 2,
				batchIndex: 0,
				patches: [fileTreeBatch([fileTreeUpsert('row-b', 'Sources/B.swift', 0)])],
				projectionRevision: 2,
				sequence: 2,
				transactionId: 'query-aborted',
			}),
		);
		applier.applyEvent(queryAbortEvent(3, 'query-aborted'));
		applier.applyEvent(deltaTreeEvent(4, [fileTreeUpsert('row-c', 'Sources/C.swift', 1)]));

		expect(resyncRequests).toEqual([]);
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/A.swift')).toBeDefined();
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/B.swift')).toBeUndefined();
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/C.swift')).toBeDefined();
		expect(applier.fileTreePatchStream.readAfter(cursor).map((entry) => entry.kind)).toEqual([
			'queryBegin',
			'queryBatch',
			'queryAbort',
			'delta',
		]);
	});

	test('fails closed when a raw non-query patch interleaves before worker abort', () => {
		const resyncRequests: unknown[] = [];
		const applier = new BridgeMainFileDisplayPatchApplier({
			requestResync: (request): void => {
				resyncRequests.push(request);
			},
		});
		applier.applyEvent(baseTreeEvent(1, [fileTreeUpsert('row-a', 'Sources/A.swift', 0)]));
		applier.applyEvent(
			queryEvent({
				batchCount: 2,
				batchIndex: 0,
				patches: [fileTreeBatch([fileTreeUpsert('row-b', 'Sources/B.swift', 0)])],
				projectionRevision: 2,
				sequence: 2,
				transactionId: 'query-invalid',
			}),
		);
		applier.applyEvent(deltaTreeEvent(3, [fileTreeUpsert('row-c', 'Sources/C.swift', 1)]));

		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/A.swift')).toBeDefined();
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/B.swift')).toBeUndefined();
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/C.swift')).toBeUndefined();
		expect(resyncRequests).toEqual([
			{ reason: 'protocolViolation', transactionId: 'query-invalid' },
		]);
	});

	test('replays events buffered during paint commit in FIFO order after the worker commit', () => {
		const applier = new BridgeMainFileDisplayPatchApplier();
		applier.applyEvent(baseTreeEvent(1, [fileTreeUpsert('row-a', 'Sources/A.swift', 0)]));
		const cursorBeforeQueries = applier.fileTreePatchStream.getCursor();
		let replayedBufferedEvents = false;
		applier.fileTreePatchStream.subscribe((): void => {
			const latestEntry = applier.fileTreePatchStream.readAfter(cursorBeforeQueries).at(-1);
			if (
				replayedBufferedEvents ||
				latestEntry?.kind !== 'queryCommit' ||
				latestEntry.transactionId !== 'query-first'
			) {
				return;
			}
			replayedBufferedEvents = true;
			applier.applyEvent(deltaTreeEvent(3, [fileTreeUpsert('row-c', 'Sources/C.swift', 1)]));
			applier.applyEvent(singleBatchQueryEvent(4, 'query-second', 'row-d', 'Sources/D.swift'));
		});
		applier.applyEvent(singleBatchQueryEvent(2, 'query-first', 'row-b', 'Sources/B.swift'));

		expect(replayedBufferedEvents).toBe(true);
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/A.swift')).toBeUndefined();
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/B.swift')).toBeUndefined();
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/C.swift')).toBeUndefined();
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/D.swift')).toBeDefined();
		expect(applier.state.fileDisplayFreshness?.sequence).toBe(4);
		expect(
			applier.fileTreePatchStream.readAfter(cursorBeforeQueries).map((entry) => entry.kind),
		).toEqual([
			'queryBegin',
			'queryBatch',
			'queryCommit',
			'delta',
			'queryBegin',
			'queryBatch',
			'queryCommit',
		]);
	});

	test('preserves old visible state and requests resync if buffered worker events overflow', () => {
		const resyncRequests: unknown[] = [];
		const applier = new BridgeMainFileDisplayPatchApplier({
			maximumBufferedEvents: 0,
			requestResync: (request): void => {
				resyncRequests.push(request);
			},
		});
		applier.applyEvent(baseTreeEvent(1, [fileTreeUpsert('row-a', 'Sources/A.swift', 0)]));
		let injectedAfterCommit = false;
		applier.fileTreePatchStream.subscribe((): void => {
			if (injectedAfterCommit) return;
			if (applier.fileTreePatchStream.readAfter(0).at(-1)?.kind !== 'queryCommit') return;
			injectedAfterCommit = true;
			applier.applyEvent(deltaTreeEvent(3, [fileTreeUpsert('row-c', 'Sources/C.swift', 1)]));
		});

		applier.applyEvent(singleBatchQueryEvent(2, 'query-failure', 'row-b', 'Sources/B.swift'));

		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/A.swift')).toBeDefined();
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/B.swift')).toBeUndefined();
		expect(resyncRequests).toEqual([{ reason: 'bufferOverflow', transactionId: 'query-failure' }]);
	});

	test('publishes the atomic File query snapshot on worker commit before Pierre paints it', () => {
		const store = createBridgeMainRenderSnapshotStore();
		store.applyFileDisplayPatchEvent(
			baseTreeEvent(1, [fileTreeUpsert('row-a', 'Sources/A.swift', 0)]),
		);
		let publishCount = 0;
		const unsubscribe = store.subscribe((): void => {
			publishCount += 1;
		});

		store.applyFileDisplayPatchEvent(
			queryEvent({
				batchCount: 1,
				batchIndex: 0,
				patches: [
					fileTreeBatch([fileTreeUpsert('row-b', 'Sources/B.swift', 0)]),
					fileQueryPatch(1, 2),
				],
				projectionRevision: 2,
				sequence: 2,
				transactionId: 'query-store',
			}),
		);

		expect(publishCount).toBe(1);
		expect(store.getSnapshot().fileTreeSlice.index.rowForPath('Sources/A.swift')).toBeUndefined();
		expect(store.getSnapshot().fileTreeSlice.index.rowForPath('Sources/B.swift')).toBeDefined();
		expect(store.getSnapshot().fileQuerySlice).toMatchObject({
			projectedRowCount: 1,
			totalRowCount: 2,
		});
		unsubscribe();
	});

	test('publishes a hidden-page query replacement on worker commit without Pierre frames', () => {
		const resyncRequests: unknown[] = [];
		const store = createBridgeMainRenderSnapshotStore({
			requestResync: (request): void => {
				resyncRequests.push(request);
			},
		});
		store.applyFileDisplayPatchEvent(
			baseTreeEvent(1, [fileTreeUpsert('old', 'Sources/Old.swift', 0)]),
		);
		const publications: Array<{
			readonly freshnessSequence: number | null;
			readonly queryText: string | undefined;
			readonly rowPaths: readonly string[];
		}> = [];
		const unsubscribe = store.subscribe((): void => {
			const snapshot = store.getSnapshot();
			publications.push({
				freshnessSequence: snapshot.fileDisplayFreshness?.sequence ?? null,
				queryText: snapshot.fileQuerySlice?.searchText,
				rowPaths: ['Sources/Old.swift', 'Sources/New.swift', 'Sources/Next.swift'].filter(
					(path): boolean => snapshot.fileTreeSlice.index.rowForPath(path) !== undefined,
				),
			});
		});

		store.applyFileDisplayPatchEvent(
			queryEvent({
				batchCount: 2,
				batchIndex: 0,
				patches: [fileTreeBatch([fileTreeUpsert('new', 'Sources/New.swift', 0)])],
				projectionRevision: 2,
				sequence: 2,
				transactionId: 'hidden-query-replacement',
			}),
		);
		store.applyFileDisplayPatchEvent(
			queryEvent({
				batchCount: 2,
				batchIndex: 1,
				patches: [
					fileTreeBatch([fileTreeUpsert('next', 'Sources/Next.swift', 1)]),
					{
						...fileQueryPatch(2, 3),
						payload: {
							...fileQueryPatch(2, 3).payload,
							searchText: 'new',
						},
					},
				],
				projectionRevision: 3,
				sequence: 3,
				transactionId: 'hidden-query-replacement',
			}),
		);

		// Model a hidden document: the Pierre patch stream has no consumer, so no rAF drain runs.
		const snapshot = store.getSnapshot();
		expect({
			freshnessSequence: snapshot.fileDisplayFreshness?.sequence ?? null,
			publications,
			queryText: snapshot.fileQuerySlice?.searchText,
			resyncRequests,
			rowPaths: ['Sources/Old.swift', 'Sources/New.swift', 'Sources/Next.swift'].filter(
				(path): boolean => snapshot.fileTreeSlice.index.rowForPath(path) !== undefined,
			),
		}).toEqual({
			freshnessSequence: 3,
			publications: [
				{
					freshnessSequence: 3,
					queryText: 'new',
					rowPaths: ['Sources/New.swift', 'Sources/Next.swift'],
				},
			],
			queryText: 'new',
			resyncRequests: [],
			rowPaths: ['Sources/New.swift', 'Sources/Next.swift'],
		});
		unsubscribe();
	});

	test('stages every worker query batch and commits query state atomically before Pierre drains', () => {
		const applier = new BridgeMainFileDisplayPatchApplier();
		applier.applyEvent(baseTreeEvent(1, [fileTreeUpsert('row-a', 'Sources/A.swift', 0)]));
		const visibleBeforeQuery = applier.state;
		const cursorBeforeQuery = applier.fileTreePatchStream.getCursor();

		expect(
			applier.applyEvent(
				queryEvent({
					batchCount: 2,
					batchIndex: 0,
					patches: [fileTreeBatch([fileTreeUpsert('row-b', 'Sources/B.swift', 0)])],
					projectionRevision: 2,
					sequence: 2,
					transactionId: 'query-one',
				}),
			),
		).toBeNull();
		expect(applier.state).toBe(visibleBeforeQuery);
		const committed = applier.applyEvent(
			queryEvent({
				batchCount: 2,
				batchIndex: 1,
				patches: [fileQueryPatch(1, 2)],
				projectionRevision: 3,
				sequence: 3,
				transactionId: 'query-one',
			}),
		);

		expect(committed?.fileTreeSlice.index.rowForPath('Sources/A.swift')).toBeUndefined();
		expect(committed?.fileTreeSlice.index.rowForPath('Sources/B.swift')).toBeDefined();
		expect(committed?.fileQuerySlice).toMatchObject({ projectedRowCount: 1, totalRowCount: 2 });
		expect(
			applier.fileTreePatchStream.readAfter(cursorBeforeQuery).map((entry) => entry.kind),
		).toEqual(['queryBegin', 'queryBatch', 'queryCommit']);
	});

	test('replays every stream operation after a skipped snapshot and supports one-to-many replacement', () => {
		const applier = new BridgeMainFileDisplayPatchApplier();
		applier.applyEvent(baseTreeEvent(1, [fileTreeUpsert('row-a', 'Sources/A.swift', 0)]));
		const cursorBeforeQuery = applier.fileTreePatchStream.getCursor();

		applier.applyEvent(
			queryEvent({
				batchCount: 3,
				batchIndex: 0,
				patches: [fileTreeBatch([fileTreeUpsert('row-a', 'Sources/A.swift', 0)])],
				projectionRevision: 2,
				sequence: 2,
				transactionId: 'query-many',
			}),
		);
		applier.applyEvent(
			queryEvent({
				batchCount: 3,
				batchIndex: 1,
				patches: [fileTreeBatch([fileTreeUpsert('row-b', 'Sources/B.swift', 1)])],
				projectionRevision: 3,
				sequence: 3,
				transactionId: 'query-many',
			}),
		);
		applier.applyEvent(
			queryEvent({
				batchCount: 3,
				batchIndex: 2,
				patches: [
					fileTreeBatch([fileTreeUpsert('row-c', 'Sources/C.swift', 2)]),
					fileQueryPatch(3, 3),
				],
				projectionRevision: 4,
				sequence: 4,
				transactionId: 'query-many',
			}),
		);

		const entries = applier.fileTreePatchStream.readAfter(cursorBeforeQuery);
		expect(entries.map((entry) => entry.kind)).toEqual([
			'queryBegin',
			'queryBatch',
			'queryBatch',
			'queryBatch',
			'queryCommit',
		]);
		expect(
			entries
				.filter((entry) => entry.kind === 'queryBatch')
				.flatMap((entry) => entry.operations)
				.map((operation) => operation.path),
		).toEqual(['Sources/A.swift', 'Sources/B.swift', 'Sources/C.swift']);
		expect(applier.state.fileTreeSlice.index.size).toBe(3);
	});
});

function baseTreeEvent(
	sequence: number,
	operations: FileTreeBatchOperations,
): BridgeWorkerFileDisplayPatchEvent {
	return event({
		patches: [
			{
				operation: 'reset',
				payload: { sourceGeneration: 1, sourceId: 'source-1' },
				slice: 'fileTree',
			},
			fileTreeBatch(operations),
		],
		projectionRevision: sequence,
		sequence,
	});
}

function deltaTreeEvent(
	sequence: number,
	operations: FileTreeBatchOperations,
): BridgeWorkerFileDisplayPatchEvent {
	return event({ patches: [fileTreeBatch(operations)], projectionRevision: sequence, sequence });
}

function singleBatchQueryEvent(
	sequence: number,
	transactionId: string,
	rowId: string,
	path: string,
): BridgeWorkerFileDisplayPatchEvent {
	return queryEvent({
		batchCount: 1,
		batchIndex: 0,
		patches: [fileTreeBatch([fileTreeUpsert(rowId, path, 0)]), fileQueryPatch(1, 1)],
		projectionRevision: sequence,
		sequence,
		transactionId,
	});
}

function queryAbortEvent(
	sequence: number,
	transactionId: string,
): BridgeWorkerFileDisplayPatchEvent {
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'fileDisplayPatch',
		patches: [],
		projectionRevision: sequence,
		queryTransaction: { phase: 'abort', transactionId },
		sequence,
		surface: 'fileView',
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
	};
}

function queryEvent(props: {
	readonly batchCount: number;
	readonly batchIndex: number;
	readonly patches: readonly BridgeWorkerFileDisplayPatch[];
	readonly projectionRevision: number;
	readonly sequence: number;
	readonly transactionId: string;
}): BridgeWorkerFileDisplayPatchEvent {
	return event({
		patches: props.patches,
		projectionRevision: props.projectionRevision,
		queryTransaction: {
			batchCount: props.batchCount,
			batchIndex: props.batchIndex,
			phase: 'batch',
			transactionId: props.transactionId,
		},
		sequence: props.sequence,
	});
}

function event(props: {
	readonly patches: readonly BridgeWorkerFileDisplayPatch[];
	readonly projectionRevision: number;
	readonly queryTransaction?: {
		readonly batchCount: number;
		readonly batchIndex: number;
		readonly phase: 'batch';
		readonly transactionId: string;
	};
	readonly sequence: number;
}): BridgeWorkerFileDisplayPatchEvent {
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'fileDisplayPatch',
		patches: props.patches,
		projectionRevision: props.projectionRevision,
		...(props.queryTransaction === undefined ? {} : { queryTransaction: props.queryTransaction }),
		sequence: props.sequence,
		surface: 'fileView',
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
	};
}

function fileTreeBatch(operations: FileTreeBatchOperations): BridgeWorkerFileDisplayPatch {
	return { operation: 'batch', payload: { operations }, slice: 'fileTree' };
}

function fileTreeUpsert(
	rowId: string,
	path: string,
	projectionIndex: number,
): FileTreeBatchOperations[number] {
	return {
		operation: 'upsert' as const,
		row: {
			changeStatus: 'modified' as const,
			depth: 1,
			documentLocation: null,
			fileId: `file-${rowId}`,
			fileClass: 'source' as const,
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

function fileQueryPatch(
	projectedRowCount: number,
	totalRowCount: number,
): Extract<BridgeWorkerFileDisplayPatch, { readonly slice: 'fileQuery' }> {
	return {
		operation: 'upsert',
		payload: {
			filterMode: 'all',
			projectedRowCount,
			searchError: null,
			searchMode: 'text',
			searchText: '',
			totalRowCount,
		},
		slice: 'fileQuery',
	};
}
