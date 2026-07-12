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

	test('buffers terminal metadata and a later query in FIFO order until each exact acknowledgement', () => {
		const applier = new BridgeMainFileDisplayPatchApplier();
		applier.applyEvent(baseTreeEvent(1, [fileTreeUpsert('row-a', 'Sources/A.swift', 0)]));
		applier.applyEvent(singleBatchQueryEvent(2, 'query-first', 'row-b', 'Sources/B.swift'));
		applier.applyEvent(deltaTreeEvent(3, [fileTreeUpsert('row-c', 'Sources/C.swift', 1)]));
		applier.applyEvent(singleBatchQueryEvent(4, 'query-second', 'row-d', 'Sources/D.swift'));

		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/A.swift')).toBeDefined();
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/B.swift')).toBeUndefined();
		expect(applier.completeQueryTransaction('query-first')?.fileTreeSlice.index.size).toBe(2);
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/B.swift')).toBeDefined();
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/C.swift')).toBeDefined();
		expect(applier.completeQueryTransaction('query-second')?.fileTreeSlice.index.size).toBe(1);
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/D.swift')).toBeDefined();
	});

	test('preserves old visible state on ack mismatch, timeout, and buffer overflow', () => {
		for (const scenario of ['mismatch', 'timeout', 'overflow'] as const) {
			const resyncRequests: unknown[] = [];
			let fireTimeout = noOperation;
			const applier = new BridgeMainFileDisplayPatchApplier({
				maximumBufferedEvents: scenario === 'overflow' ? 0 : 256,
				requestResync: (request): void => {
					resyncRequests.push(request);
				},
				scheduleTimeout: (callback): (() => void) => {
					fireTimeout = callback;
					return (): void => {};
				},
			});
			applier.applyEvent(baseTreeEvent(1, [fileTreeUpsert('row-a', 'Sources/A.swift', 0)]));
			applier.applyEvent(singleBatchQueryEvent(2, 'query-failure', 'row-b', 'Sources/B.swift'));

			if (scenario === 'mismatch') applier.completeQueryTransaction('wrong-query');
			if (scenario === 'timeout') fireTimeout();
			if (scenario === 'overflow') {
				applier.applyEvent(deltaTreeEvent(3, [fileTreeUpsert('row-c', 'Sources/C.swift', 1)]));
			}

			expect(applier.state.fileTreeSlice.index.rowForPath('Sources/A.swift')).toBeDefined();
			expect(applier.state.fileTreeSlice.index.rowForPath('Sources/B.swift')).toBeUndefined();
			expect(applier.completeQueryTransaction('query-failure')).toBeNull();
			expect(resyncRequests).toEqual([
				{
					reason:
						scenario === 'mismatch'
							? 'acknowledgementMismatch'
							: scenario === 'timeout'
								? 'acknowledgementTimeout'
								: 'bufferOverflow',
					transactionId: 'query-failure',
				},
			]);
		}
	});

	test('publishes no React snapshot before the terminal Pierre acknowledgement', () => {
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

		expect(publishCount).toBe(0);
		expect(store.getSnapshot().fileTreeSlice.index.rowForPath('Sources/A.swift')).toBeDefined();
		expect(store.getSnapshot().fileTreeSlice.index.rowForPath('Sources/B.swift')).toBeUndefined();

		store.completeFileQueryTransaction('query-store');

		expect(publishCount).toBe(1);
		expect(store.getSnapshot().fileTreeSlice.index.rowForPath('Sources/A.swift')).toBeUndefined();
		expect(store.getSnapshot().fileTreeSlice.index.rowForPath('Sources/B.swift')).toBeDefined();
		unsubscribe();
	});

	test('stages every query batch without publishing visible state until Pierre acknowledges commit', () => {
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
		expect(
			applier.applyEvent(
				queryEvent({
					batchCount: 2,
					batchIndex: 1,
					patches: [fileQueryPatch(1, 2)],
					projectionRevision: 3,
					sequence: 3,
					transactionId: 'query-one',
				}),
			),
		).toBeNull();

		expect(applier.state).toBe(visibleBeforeQuery);
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/A.swift')).toBeDefined();
		expect(applier.state.fileTreeSlice.index.rowForPath('Sources/B.swift')).toBeUndefined();
		expect(
			applier.fileTreePatchStream.readAfter(cursorBeforeQuery).map((entry) => entry.kind),
		).toEqual(['queryBegin', 'queryBatch', 'queryCommit']);

		const committed = applier.completeQueryTransaction('query-one');

		expect(committed?.fileTreeSlice.index.size).toBe(1);
		expect(committed?.fileTreeSlice.index.rowForPath('Sources/A.swift')).toBeUndefined();
		expect(committed?.fileTreeSlice.index.rowForPath('Sources/B.swift')).toBeDefined();
		expect(committed?.fileQuerySlice).toMatchObject({ projectedRowCount: 1, totalRowCount: 2 });
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
		expect(applier.state.fileTreeSlice.index.size).toBe(1);

		const committed = applier.completeQueryTransaction('query-many');
		expect(committed?.fileTreeSlice.index.size).toBe(3);
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

function noOperation(): void {}

function fileQueryPatch(
	projectedRowCount: number,
	totalRowCount: number,
): BridgeWorkerFileDisplayPatch {
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
