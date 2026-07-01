import { describe, expect, test } from 'vitest';

import { makeFileDescriptor } from '../bridge-file-viewer-browser-test-fixtures.js';
import type { BridgeFileViewerStoreState } from './bridge-file-viewer-store.js';
import {
	createBridgeFileViewerStore,
	selectBridgeFileViewerRootSnapshot,
} from './bridge-file-viewer-store.js';

describe('Bridge file viewer Zustand store', () => {
	test('keeps root subscriptions stable for render hydration descriptor and open-file updates', () => {
		const store = createBridgeFileViewerStore();
		const descriptor = makeFileDescriptor({ path: 'Sources/App.swift' });
		let rootRenderCount = 0;
		const unsubscribe = store.subscribe(selectBridgeFileViewerRootSnapshot, () => {
			rootRenderCount += 1;
		});

		store.getState().actions.setRenderState({
			descriptors: [descriptor],
			provenance: {
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRootToken: 'root-token',
			},
			sourceIdentity: descriptor.sourceIdentity,
			treeRows: [
				{
					rowId: 'row:Sources/App.swift',
					path: 'Sources/App.swift',
					name: 'App.swift',
					parentPath: 'Sources',
					depth: 1,
					isDirectory: false,
					fileId: descriptor.fileId,
					sizeBytes: descriptor.sizeBytes,
					lineCount: descriptor.lineCount,
				},
			],
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: 1,
				windowStartIndex: 0,
				windowRowCount: 1,
				rowHeightPixels: 24,
			},
		});
		store.getState().actions.setOpenFileState({
			status: 'loading',
			path: 'Sources/App.swift',
			descriptor,
		});
		store.getState().actions.setInitialSurfaceLoadState({ status: 'ready' });
		store.getState().actions.setRefreshDebugState({
			commitState: 'committed',
			currentRequestId: 1,
			descriptorId: descriptor.contentDescriptor.ref.descriptorId,
			requestId: 1,
			result: 'ok',
		});
		store.getState().actions.setLastOpenLoadTelemetry({
			disposition: 'cold-loaded',
			durationMilliseconds: 12,
			estimatedBytes: descriptor.sizeBytes,
			executorInFlightBytesAfter: 0,
			executorInFlightBytesBefore: 1,
			executorInFlightCountAfter: 0,
			executorInFlightCountBefore: 1,
			executorInFlightMilliseconds: 2,
			executorPendingWaitMilliseconds: 1,
			executorQueuedBytesAfter: 0,
			executorQueuedBytesBefore: 0,
			executorQueuedLoadCountAfter: 0,
			executorQueuedLoadCountBefore: 0,
			lane: 'foreground',
			resourceBodyRegistryCommitMilliseconds: 1,
			resourceFetchResponseWaitMilliseconds: 3,
			resourceFirstChunkWaitMilliseconds: 4,
			resourceStreamReadMilliseconds: 5,
			schedulerQueueWaitMilliseconds: 1,
			schedulerQueuedEstimatedBytesAfter: 0,
			schedulerQueuedEstimatedBytesBefore: descriptor.sizeBytes ?? 0,
			schedulerQueuedIntentCountAfter: 0,
			schedulerQueuedIntentCountBefore: 1,
		});
		store.getState().actions.setLastDemandDispatchDebugState({
			status: 'failed',
			reason: 'descriptor_missing',
		});

		expect(rootRenderCount).toBe(0);

		store.getState().actions.setSearchText('Sources');

		expect(rootRenderCount).toBe(1);
		unsubscribe();
	});

	test('owns file tree search filters as pure control-plane facts', () => {
		const store = createBridgeFileViewerStore();
		const descriptor = makeFileDescriptor({ path: 'Sources/App.swift' });

		store.getState().actions.setSearchText('Sources');
		store.getState().actions.setSearchMode('regex');
		store.getState().actions.setFilterMode('fetchable');
		store.getState().actions.setOpenFileState({
			status: 'loading',
			path: 'Sources/App.swift',
			descriptor,
		});

		expect(store.getState().rootSnapshot).toMatchObject({
			searchText: 'Sources',
			searchMode: 'regex',
			filterMode: 'fetchable',
		});
		expect(store.getState().openFileState).toMatchObject({
			status: 'loading',
			path: 'Sources/App.swift',
		});
	});

	test('supports functional open-state transitions for frame reconciliation', () => {
		const store = createBridgeFileViewerStore();
		const descriptor = makeFileDescriptor({ path: 'Sources/App.swift' });

		store.getState().actions.setOpenFileState({
			status: 'loading',
			path: 'Sources/App.swift',
			descriptor,
		});
		store.getState().actions.setOpenFileState((currentOpenFileState) => {
			if (currentOpenFileState.status === 'idle') {
				return currentOpenFileState;
			}
			return {
				...currentOpenFileState,
				status: 'failed',
			};
		});

		expect(store.getState().openFileState).toMatchObject({
			status: 'failed',
			path: 'Sources/App.swift',
		});
	});

	test('keeps file bodies and runtime controls out of the Zustand snapshot', () => {
		const store = createBridgeFileViewerStore();
		const descriptor = makeFileDescriptor({ path: 'Sources/App.swift' });

		store.getState().actions.setRenderState({
			descriptors: [descriptor],
			provenance: {
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRootToken: 'root-token',
			},
			sourceIdentity: descriptor.sourceIdentity,
			treeRows: [
				{
					rowId: 'row:Sources/App.swift',
					path: 'Sources/App.swift',
					name: 'App.swift',
					parentPath: 'Sources',
					depth: 1,
					isDirectory: false,
					fileId: descriptor.fileId,
					sizeBytes: descriptor.sizeBytes,
					lineCount: descriptor.lineCount,
				},
			],
			treeSizeFacts: {
				extentKind: 'exactPathCount',
				pathCount: 1,
				windowStartIndex: 0,
				windowRowCount: 1,
				rowHeightPixels: 24,
			},
		});
		store.getState().actions.setOpenFileState({
			status: 'ready',
			path: 'Sources/App.swift',
			descriptor,
		});
		store.getState().actions.setSearchText('Sources');
		store.getState().actions.setLastDemandDispatchDebugState({
			status: 'failed',
			reason: 'descriptor_missing',
		});

		const snapshot = serializableViewerStateForBodyBoundary(store.getState());
		const snapshotJSON = JSON.stringify(snapshot);

		expect(snapshot.renderState.descriptors).toHaveLength(1);
		expect(snapshot.openFileState).toMatchObject({
			status: 'ready',
			path: 'Sources/App.swift',
		});
		expect(snapshot.rootSnapshot.searchText).toBe('Sources');
		expect(snapshotJSON).not.toContain('export const largeBody');
		expect(containsRuntimeControlObject(snapshot)).toBe(false);
	});
});

function serializableViewerStateForBodyBoundary(
	state: BridgeFileViewerStoreState,
): Omit<BridgeFileViewerStoreState, 'actions'> {
	const { actions, ...snapshot } = state;
	void actions;
	return snapshot;
}

function containsRuntimeControlObject(value: unknown): boolean {
	if (value instanceof Promise || value instanceof AbortController) {
		return true;
	}
	if (typeof Worker !== 'undefined' && value instanceof Worker) {
		return true;
	}
	if (Array.isArray(value)) {
		return value.some(containsRuntimeControlObject);
	}
	if (typeof value !== 'object' || value === null) {
		return false;
	}
	return Object.values(value).some(containsRuntimeControlObject);
}
