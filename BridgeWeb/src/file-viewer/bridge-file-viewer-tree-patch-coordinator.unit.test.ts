import type { FileTreeBatchOperation, FileTreeDirectoryHandle } from '@pierre/trees';
import { describe, expect, test } from 'vitest';

import type { BridgeMainFileTreePatchStreamEntry } from '../core/comm-worker/bridge-main-file-display-patch-applier.js';
import {
	createBridgeFileViewerTreePatchCoordinator,
	type BridgeFileViewerTreePatchCoordinator,
	type BridgeFileViewerPatchableTreeModel,
} from './bridge-file-viewer-tree-patch-coordinator.js';

describe('Bridge File viewer tree patch coordinator', () => {
	test('does not apply an entire large tree patch in one application turn', () => {
		const active = createRecordingTreeModel();
		const coordinator = createBridgeFileViewerTreePatchCoordinator({ model: active.model });
		const operationCount = 512;

		coordinator.applyEntry({
			cursor: 1,
			kind: 'delta',
			operations: Array.from({ length: operationCount }, (_unused, index) => ({
				path: `src/file-${String(index)}.ts`,
				type: 'add',
			})),
		});

		expect(active.paths.length).toBeLessThan(operationCount);
		expect(active.batchCalls.flat().length).toBeLessThan(operationCount);
	});

	test('bounds each patch turn by operation count and UTF-8 path bytes', () => {
		const active = createRecordingTreeModel();
		const coordinator = createBridgeFileViewerTreePatchCoordinator({ model: active.model });
		coordinator.enqueueEntry({
			cursor: 1,
			kind: 'delta',
			operations: [
				{ path: 'a.ts', type: 'add' },
				{ path: 'é.ts', type: 'add' },
				{ path: 'b.ts', type: 'add' },
			],
		});
		const limits = { maximumBytes: 6, maximumOperations: 4 };

		const firstTurn = coordinator.advanceNextTurn(limits);
		const secondTurn = coordinator.advanceNextTurn(limits);
		const thirdTurn = coordinator.advanceNextTurn(limits);

		expect(firstTurn).toEqual({
			blockedOnProjection: false,
			hasPendingWork: true,
			processedBytes: 4,
			processedOperations: 1,
		});
		expect(secondTurn).toEqual({
			blockedOnProjection: false,
			hasPendingWork: true,
			processedBytes: 5,
			processedOperations: 1,
		});
		expect(thirdTurn).toEqual({
			blockedOnProjection: false,
			hasPendingWork: false,
			processedBytes: 4,
			processedOperations: 1,
		});
		expect(active.paths).toEqual(['a.ts', 'é.ts', 'b.ts']);
		expect(active.batchCalls.map((operations) => operations.length)).toEqual([1, 1, 1]);
	});

	test('holds DOM additions until the corresponding logical row is accepted', () => {
		const active = createRecordingTreeModel(['Current.swift']);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
		});
		coordinator.enqueueEntry({
			cursor: 1,
			kind: 'delta',
			operations: [{ path: 'Next.swift', type: 'add' }],
		});

		const beforeLogicalInstall = coordinator.advanceNextTurn(undefined, (): boolean => false);

		expect(beforeLogicalInstall).toEqual({
			blockedOnProjection: true,
			hasPendingWork: true,
			processedBytes: 0,
			processedOperations: 0,
		});
		expect(active.paths).toEqual(['Current.swift']);
		expect(active.batchCalls).toEqual([]);

		const afterLogicalInstall = coordinator.advanceNextTurn(undefined, (path): boolean => {
			return path === 'Next.swift';
		});

		expect(afterLogicalInstall).toEqual({
			blockedOnProjection: false,
			hasPendingWork: false,
			processedBytes: 10,
			processedOperations: 1,
		});
		expect(active.paths).toEqual(['Current.swift', 'Next.swift']);
	});

	test('keeps the previous coherent query tree until all next rows are logical', () => {
		const active = createRecordingTreeModel(['Current.swift']);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
		});
		coordinator.enqueueEntry(queryBegin(1, 'query-next'));
		coordinator.enqueueEntry(queryBatch(2, 'query-next', ['Next-A.swift', 'Next-B.swift']));
		coordinator.enqueueEntry(queryCommit(3, 'query-next'));

		const waitingTurn = coordinator.advanceNextTurn(
			undefined,
			(path): boolean => path === 'Next-A.swift',
		);

		expect(waitingTurn.blockedOnProjection).toBe(true);
		expect(active.paths).toEqual(['Current.swift']);
		expect(active.batchCalls).toEqual([]);

		drainPendingWork(coordinator, (path): boolean => path.startsWith('Next-'));
		expect(active.paths).toEqual(['Next-A.swift', 'Next-B.swift']);
	});

	test('coalesces a staged query that is superseded before model application', () => {
		const active = createRecordingTreeModel(['Current.swift']);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
		});
		coordinator.enqueueEntry(queryBegin(1, 'query-old'));
		coordinator.enqueueEntry(
			queryBatch(
				2,
				'query-old',
				Array.from({ length: 256 }, (_, index) => `Old-${String(index)}.swift`),
			),
		);
		const firstTurn = coordinator.advanceNextTurn({
			maximumBytes: 16 * 1024,
			maximumOperations: 2,
		});

		coordinator.enqueueEntry(queryCommit(3, 'query-old'));
		coordinator.enqueueEntry(queryBegin(4, 'query-new'));
		coordinator.enqueueEntry(queryBatch(5, 'query-new', ['New.swift']));
		coordinator.enqueueEntry(queryCommit(6, 'query-new'));
		drainPendingWork(coordinator);

		expect(firstTurn.hasPendingWork).toBe(true);
		expect(active.paths).toEqual(['New.swift']);
		expect(active.batchCalls.flat()).toEqual([
			{ path: 'Current.swift', recursive: true, type: 'remove' },
			{ path: 'New.swift', type: 'add' },
		]);
	});

	test('keeps one model unchanged until every staged query batch commits atomically', () => {
		const active = createRecordingTreeModel(['Sources/Current.swift']);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
		});

		coordinator.applyEntry(queryBegin(1, 'query-1'));
		coordinator.applyEntry(queryBatch(2, 'query-1', ['Sources/One.swift']));
		coordinator.applyEntry(queryBatch(3, 'query-1', ['Sources/Two.swift']));

		expect(active.paths).toEqual(['Sources/Current.swift']);
		expect(active.batchCalls).toEqual([]);

		coordinator.applyEntry(queryCommit(4, 'query-1'));

		expect(active.paths).toEqual(['Sources/One.swift', 'Sources/Two.swift']);
		expect(active.batchCalls).toEqual([
			[
				{ path: 'Sources/Current.swift', recursive: true, type: 'remove' },
				{ path: 'Sources/One.swift', type: 'add' },
				{ path: 'Sources/Two.swift', type: 'add' },
			],
		]);
		expect(active.resetCalls).toEqual([]);
	});

	test('discards superseded staging and applies later deltas to the same committed model', () => {
		const active = createRecordingTreeModel(['Sources/Current.swift']);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
		});

		coordinator.applyEntry(queryBegin(1, 'query-old'));
		coordinator.applyEntry(queryBatch(2, 'query-old', ['Sources/Old.swift']));
		coordinator.applyEntry(queryBegin(3, 'query-new'));
		coordinator.applyEntry(queryCommit(4, 'query-old'));
		coordinator.applyEntry(queryBatch(5, 'query-old', ['Sources/LateOld.swift']));
		coordinator.applyEntry(queryBatch(6, 'query-new', ['Sources/New.swift']));
		coordinator.applyEntry(queryCommit(7, 'query-new'));
		coordinator.applyEntry({
			cursor: 8,
			kind: 'delta',
			operations: [{ path: 'Sources/Delta.swift', type: 'add' }],
		});

		expect(active.paths).toEqual(['Sources/New.swift', 'Sources/Delta.swift']);
		expect(active.resetCalls).toEqual([]);
	});

	test('keeps paint staging atomic until query commit and discards an aborted transaction', () => {
		const active = createRecordingTreeModel(['Sources/Current.swift']);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
		});

		coordinator.applyEntry(queryBegin(1, 'query-committed'));
		coordinator.applyEntry(queryBatch(2, 'query-committed', ['Sources/Committed.swift']));
		expect(active.paths).toEqual(['Sources/Current.swift']);
		coordinator.applyEntry(queryCommit(3, 'query-committed'));
		expect(active.paths).toEqual(['Sources/Committed.swift']);

		coordinator.applyEntry(queryBegin(4, 'query-aborted'));
		coordinator.applyEntry(queryBatch(5, 'query-aborted', ['Sources/Aborted.swift']));
		coordinator.applyEntry({ cursor: 6, kind: 'queryAbort', transactionId: 'query-aborted' });

		expect(active.paths).toEqual(['Sources/Committed.swift']);
		expect(active.resetCalls).toEqual([]);
	});

	test('removes an obsolete synthesized ancestor branch when a query has no descendant there', () => {
		const active = createRecordingTreeModel(['Sources/App/Current.swift']);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
		});

		coordinator.applyEntry(queryBegin(1, 'query-empty'));
		coordinator.applyEntry(queryCommit(2, 'query-empty'));

		expect(active.paths).toEqual([]);
		expect(active.batchCalls).toEqual([[{ path: 'Sources', recursive: true, type: 'remove' }]]);
		expect(active.resetCalls).toEqual([]);
	});

	test('does not add an explicit ancestor that Pierre already synthesized for a retained file', () => {
		const active = createRecordingTreeModel(['Vendor/BinaryFile.bin']);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
		});

		coordinator.applyEntry(queryBegin(1, 'query-clear'));
		coordinator.applyEntry(queryBatch(2, 'query-clear', ['Vendor/', 'Vendor/BinaryFile.bin']));
		coordinator.applyEntry(queryCommit(3, 'query-clear'));

		expect(active.batchCalls).toEqual([]);
		expect(active.paths).toEqual(['Vendor/BinaryFile.bin']);
	});

	test('holds replacement reset until commit while an explicit clear empties the stable model', () => {
		const active = createRecordingTreeModel(
			['Sources/Current.swift'],
			['Sources', 'Sources/Replacement'],
		);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
		});

		coordinator.applyEntry({ cursor: 1, kind: 'reset' });
		coordinator.applyEntry({
			cursor: 2,
			kind: 'delta',
			operations: [{ path: 'Sources/Replacement.swift', type: 'add' }],
		});
		expect(active.paths).toEqual(['Sources/Current.swift']);
		expect(active.resetCalls).toEqual([]);

		coordinator.applyEntry({ cursor: 3, kind: 'replacementCommit' });
		drainPendingWork(coordinator);
		expect(active.paths).toEqual(['Sources/Replacement.swift']);
		expect(active.resetCalls).toEqual([]);
		expect(active.expandedPaths).toEqual(['Sources']);

		coordinator.applyEntry({ cursor: 4, kind: 'clear' });
		expect(active.paths).toEqual([]);
		expect(active.resetCalls).toEqual([]);
	});

	test('streams partial replacement rows immediately when no committed tree exists yet', () => {
		const active = createRecordingTreeModel();
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			model: active.model,
		});

		coordinator.applyEntry({ cursor: 1, kind: 'reset' });
		coordinator.applyEntry({
			cursor: 2,
			kind: 'delta',
			operations: [
				{ path: 'Sources/One.swift', type: 'add' },
				{ path: 'Sources/Two.swift', type: 'add' },
			],
		});

		expect(active.paths).toEqual(['Sources/One.swift', 'Sources/Two.swift']);
		expect(active.batchCalls).toEqual([
			[
				{ path: 'Sources/One.swift', type: 'add' },
				{ path: 'Sources/Two.swift', type: 'add' },
			],
		]);
	});

	test('keeps source replacement staging independent from aborted query transactions', () => {
		const active = createRecordingTreeModel(['Sources/Current.swift']);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
		});

		coordinator.applyEntry({ cursor: 1, kind: 'reset' });
		coordinator.applyEntry({
			cursor: 2,
			kind: 'delta',
			operations: [{ path: 'Sources/Replacement.swift', type: 'add' }],
		});
		coordinator.applyEntry(queryBegin(3, 'query-aborted'));
		coordinator.applyEntry(queryBatch(4, 'query-aborted', ['Sources/QueryAbort.swift']));
		coordinator.applyEntry({ cursor: 5, kind: 'queryAbort', transactionId: 'query-aborted' });

		expect(active.paths).toEqual(['Sources/Current.swift']);

		coordinator.applyEntry({ cursor: 6, kind: 'replacementCommit' });
		drainPendingWork(coordinator);

		expect(active.paths).toEqual(['Sources/Replacement.swift']);
	});
});

interface RecordingTreeModel {
	readonly batchCalls: readonly (readonly FileTreeBatchOperation[])[];
	readonly expandedPaths: readonly string[];
	readonly model: BridgeFileViewerPatchableTreeModel;
	readonly paths: readonly string[];
	readonly resetCalls: readonly (readonly string[])[];
}

function createRecordingTreeModel(
	initialPaths: readonly string[] = [],
	directoryPaths: readonly string[] = [],
): RecordingTreeModel {
	let paths = [...initialPaths];
	const batchCalls: (readonly FileTreeBatchOperation[])[] = [];
	const expandedPaths: string[] = [];
	const resetCalls: (readonly string[])[] = [];
	const directoryPathSet = new Set(directoryPaths);
	return {
		batchCalls,
		expandedPaths,
		model: {
			batch(operations): void {
				batchCalls.push([...operations]);
				for (const operation of operations) {
					switch (operation.type) {
						case 'add':
							paths.push(operation.path);
							break;
						case 'remove':
							paths = paths.filter(
								(path) =>
									path !== operation.path &&
									(operation.recursive !== true ||
										!path.startsWith(`${operation.path.replace(/\/$/u, '')}/`)),
							);
							break;
						case 'move':
							paths = paths.map((path) => (path === operation.from ? operation.to : path));
							break;
					}
				}
			},
			getItem(path): FileTreeDirectoryHandle | null {
				if (!directoryPathSet.has(path)) return null;
				return makeRecordingDirectoryHandle(path, expandedPaths);
			},
			resetPaths(nextPaths): void {
				paths = [...nextPaths];
				resetCalls.push([...nextPaths]);
			},
		},
		get paths(): readonly string[] {
			return paths;
		},
		resetCalls,
	};
}

function makeRecordingDirectoryHandle(
	path: string,
	expandedPaths: string[],
): FileTreeDirectoryHandle {
	return {
		collapse: (): void => {},
		deselect: (): void => {},
		expand: (): void => {
			expandedPaths.push(path);
		},
		focus: (): void => {},
		getPath: (): string => path,
		isDirectory: (): true => true,
		isExpanded: (): boolean => true,
		isFocused: (): boolean => false,
		isSelected: (): boolean => false,
		select: (): void => {},
		toggle: (): void => {},
		toggleSelect: (): void => {},
	};
}

function drainPendingWork(
	coordinator: BridgeFileViewerTreePatchCoordinator,
	isPathReady: (path: string) => boolean = (): boolean => true,
): void {
	let turn = coordinator.advanceNextTurn(undefined, isPathReady);
	while (turn.hasPendingWork) {
		turn = coordinator.advanceNextTurn(undefined, isPathReady);
	}
}

function queryBegin(cursor: number, transactionId: string): BridgeMainFileTreePatchStreamEntry {
	return { cursor, kind: 'queryBegin', transactionId };
}

function queryBatch(
	cursor: number,
	transactionId: string,
	paths: readonly string[],
): BridgeMainFileTreePatchStreamEntry {
	return {
		cursor,
		kind: 'queryBatch',
		operations: paths.map((path) => ({ path, type: 'add' })),
		transactionId,
	};
}

function queryCommit(cursor: number, transactionId: string): BridgeMainFileTreePatchStreamEntry {
	return { cursor, kind: 'queryCommit', transactionId };
}
