import type { FileTreeBatchOperation, FileTreeDirectoryHandle } from '@pierre/trees';
import { describe, expect, test } from 'vitest';

import type { BridgeMainFileTreePatchStreamEntry } from '../core/comm-worker/bridge-main-file-display-patch-applier.js';
import {
	createBridgeFileViewerTreePatchCoordinator,
	type BridgeFileViewerPatchableTreeModel,
} from './bridge-file-viewer-tree-patch-coordinator.js';

describe('Bridge File viewer tree patch coordinator', () => {
	test('keeps one model unchanged until every staged query batch commits atomically', () => {
		const active = createRecordingTreeModel(['Sources/Current.swift']);
		const readyTransactions: string[] = [];
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
			onQueryTransactionReady: (transactionId): boolean => {
				readyTransactions.push(transactionId);
				return true;
			},
		});

		coordinator.applyEntry(queryBegin(1, 'query-1'));
		coordinator.applyEntry(queryBatch(2, 'query-1', ['Sources/One.swift']));
		coordinator.applyEntry(queryBatch(3, 'query-1', ['Sources/Two.swift']));

		expect(active.paths).toEqual(['Sources/Current.swift']);
		expect(active.batchCalls).toEqual([]);
		expect(readyTransactions).toEqual([]);

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
		expect(readyTransactions).toEqual(['query-1']);
	});

	test('discards superseded staging and applies later deltas to the same committed model', () => {
		const active = createRecordingTreeModel(['Sources/Current.swift']);
		const readyTransactions: string[] = [];
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
			onQueryTransactionReady: (transactionId): boolean => {
				readyTransactions.push(transactionId);
				return true;
			},
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
		expect(readyTransactions).toEqual(['query-new']);
	});

	test('keeps the current model unchanged when main rejects acknowledgement or aborts staging', () => {
		const active = createRecordingTreeModel(['Sources/Current.swift']);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
			onQueryTransactionReady: (): boolean => false,
		});

		coordinator.applyEntry(queryBegin(1, 'query-rejected'));
		coordinator.applyEntry(queryBatch(2, 'query-rejected', ['Sources/Rejected.swift']));
		coordinator.applyEntry(queryCommit(3, 'query-rejected'));
		coordinator.applyEntry(queryBegin(4, 'query-aborted'));
		coordinator.applyEntry(queryBatch(5, 'query-aborted', ['Sources/Aborted.swift']));
		coordinator.applyEntry({ cursor: 6, kind: 'queryAbort', transactionId: 'query-aborted' });

		expect(active.paths).toEqual(['Sources/Current.swift']);
		expect(active.resetCalls).toEqual([]);
	});

	test('removes an obsolete synthesized ancestor branch when a query has no descendant there', () => {
		const active = createRecordingTreeModel(['Sources/App/Current.swift']);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
			onQueryTransactionReady: (): boolean => true,
		});

		coordinator.applyEntry(queryBegin(1, 'query-empty'));
		coordinator.applyEntry(queryCommit(2, 'query-empty'));

		expect(active.paths).toEqual([]);
		expect(active.batchCalls).toEqual([[{ path: 'Sources', recursive: true, type: 'remove' }]]);
		expect(active.resetCalls).toEqual([]);
	});

	test('holds replacement reset until commit while an explicit clear empties the stable model', () => {
		const active = createRecordingTreeModel(
			['Sources/Current.swift'],
			['Sources', 'Sources/Replacement'],
		);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
			onQueryTransactionReady: (): boolean => true,
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
		expect(active.paths).toEqual(['Sources/Replacement.swift']);
		expect(active.resetCalls).toEqual([]);
		expect(active.expandedPaths).toEqual(['Sources']);

		coordinator.applyEntry({ cursor: 4, kind: 'clear' });
		expect(active.paths).toEqual([]);
		expect(active.resetCalls).toEqual([[]]);
	});

	test('streams partial replacement rows immediately when no committed tree exists yet', () => {
		const active = createRecordingTreeModel();
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			model: active.model,
			onQueryTransactionReady: (): boolean => true,
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

	test('keeps source replacement staging independent from aborted or rejected queries', () => {
		const active = createRecordingTreeModel(['Sources/Current.swift']);
		const coordinator = createBridgeFileViewerTreePatchCoordinator({
			initialPaths: active.paths,
			model: active.model,
			onQueryTransactionReady: (): boolean => false,
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
		coordinator.applyEntry(queryBegin(6, 'query-rejected'));
		coordinator.applyEntry(queryBatch(7, 'query-rejected', ['Sources/QueryReject.swift']));
		coordinator.applyEntry(queryCommit(8, 'query-rejected'));

		expect(active.paths).toEqual(['Sources/Current.swift']);

		coordinator.applyEntry({ cursor: 9, kind: 'replacementCommit' });

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
