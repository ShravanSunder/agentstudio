import { describe, expect, test } from 'vitest';

import type {
	BridgeFileViewerStoreActions,
	BridgeFileViewerStoreState,
} from './bridge-file-viewer-store.js';
import {
	createBridgeFileViewerStore,
	readBridgeFileViewerStoreSelectorSnapshot,
	selectBridgeFileViewerRootSnapshot,
} from './bridge-file-viewer-store.js';

describe('Bridge file viewer UI store', () => {
	test('owns file tree search filters as pure UI facts', () => {
		const store = createBridgeFileViewerStore();

		store.getState().actions.setSearchText('Sources');
		store.getState().actions.setSearchMode('regex');
		store.getState().actions.setFilterMode('fetchable');

		expect(store.getState().rootSnapshot).toMatchObject({
			searchText: 'Sources',
			searchMode: 'regex',
			filterMode: 'fetchable',
		});
	});

	test('notifies root selector subscriptions only for UI fact updates', () => {
		const store = createBridgeFileViewerStore();
		const initialActions = store.getState().actions;
		const rootUpdates: string[] = [];
		const unsubscribe = store.subscribeSelector(selectBridgeFileViewerRootSnapshot, (slice) => {
			rootUpdates.push(slice.searchText);
		});

		store.getState().actions.setSearchText('Sources');

		expect(rootUpdates).toEqual(['Sources']);
		expect(store.getState().actions).toBe(initialActions);
		unsubscribe();
	});

	test('caches hook selector snapshots while store state and selector are unchanged', () => {
		const store = createBridgeFileViewerStore();
		const cache = { current: null };

		const firstSnapshot = readBridgeFileViewerStoreSelectorSnapshot(
			cache,
			store,
			selectAllocatingFileViewerStoreSnapshot,
		);
		const secondSnapshot = readBridgeFileViewerStoreSelectorSnapshot(
			cache,
			store,
			selectAllocatingFileViewerStoreSnapshot,
		);

		expect(secondSnapshot).toBe(firstSnapshot);
		expect(firstSnapshot.actions).toBe(store.getState().actions);

		store.getState().actions.setSearchText('Sources');
		const afterStoreChange = readBridgeFileViewerStoreSelectorSnapshot(
			cache,
			store,
			selectAllocatingFileViewerStoreSnapshot,
		);
		const repeatedAfterStoreChange = readBridgeFileViewerStoreSelectorSnapshot(
			cache,
			store,
			selectAllocatingFileViewerStoreSnapshot,
		);

		expect(afterStoreChange).not.toBe(firstSnapshot);
		expect(afterStoreChange.actions).toBe(firstSnapshot.actions);
		expect(repeatedAfterStoreChange).toBe(afterStoreChange);
	});

	test('keeps render and protocol authority out of the UI store snapshot', () => {
		const store = createBridgeFileViewerStore();
		store.getState().actions.setSearchText('Sources');

		const snapshot = serializableViewerStateForBodyBoundary(store.getState());
		const snapshotJSON = JSON.stringify(snapshot);

		expect(snapshot.rootSnapshot.searchText).toBe('Sources');
		expect(snapshotJSON).not.toContain('export const largeBody');
		expect(snapshotJSON).not.toMatch(
			/renderState|openFileState|initialSurfaceLoadState|refreshDebugState|lastOpenLoadTelemetry|lastDemandDispatchDebugState|sourceGeneration|sequence|staleness|retryAfterVersion|demandMembership|byteCache/i,
		);
	});
});

function serializableViewerStateForBodyBoundary(
	state: BridgeFileViewerStoreState,
): Omit<BridgeFileViewerStoreState, 'actions'> {
	const { actions, ...snapshot } = state;
	void actions;
	return snapshot;
}

function selectAllocatingFileViewerStoreSnapshot(state: BridgeFileViewerStoreState): {
	readonly actions: BridgeFileViewerStoreActions;
	readonly searchText: string;
} {
	return {
		actions: state.actions,
		searchText: state.rootSnapshot.searchText,
	};
}
