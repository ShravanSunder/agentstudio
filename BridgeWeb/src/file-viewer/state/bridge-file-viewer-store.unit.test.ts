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
	test('owns file tree Search as one atomic UI state', () => {
		const store = createBridgeFileViewerStore();

		store.getState().actions.transitionSearch({ type: 'open' });
		store.getState().actions.transitionSearch({ type: 'change_query', query: 'Sources' });
		store.getState().actions.transitionSearch({ type: 'change_mode', mode: 'regex' });
		store.getState().actions.setFilterMode('source');

		expect(store.getState().rootSnapshot).toMatchObject({
			filterMode: 'source',
			search: {
				isOpen: true,
				enteredCriteria: { query: 'Sources', mode: 'regex' },
				acceptedCriteria: { query: 'Sources', mode: 'regex' },
				error: null,
			},
		});
	});

	test('preserves the accepted File projection when entered regex is invalid', () => {
		const store = createBridgeFileViewerStore();

		store.getState().actions.transitionSearch({ type: 'change_query', query: 'Sources' });
		store.getState().actions.transitionSearch({ type: 'change_mode', mode: 'regex' });
		store.getState().actions.transitionSearch({ type: 'change_query', query: '[' });

		expect(store.getState().rootSnapshot.search).toEqual({
			isOpen: false,
			enteredCriteria: { query: '[', mode: 'regex' },
			acceptedCriteria: { query: 'Sources', mode: 'regex' },
			error: 'invalid_regex',
		});
	});

	test('rejects oversized Search without publishing a store update', () => {
		const store = createBridgeFileViewerStore();
		const before = store.getState();
		let notificationCount = 0;
		store.subscribe(() => {
			notificationCount += 1;
		});

		const result = store
			.getState()
			.actions.transitionSearch({ type: 'change_query', query: 'x'.repeat(4_097) });

		expect(result.rejectionReason).toBe('search_query_too_long');
		expect(store.getState()).toBe(before);
		expect(notificationCount).toBe(0);
	});

	test('notifies root selector subscriptions only for UI fact updates', () => {
		const store = createBridgeFileViewerStore();
		const initialActions = store.getState().actions;
		const rootUpdates: string[] = [];
		const unsubscribe = store.subscribeSelector(selectBridgeFileViewerRootSnapshot, (slice) => {
			rootUpdates.push(slice.search.enteredCriteria.query);
		});

		store.getState().actions.transitionSearch({ type: 'change_query', query: 'Sources' });

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

		store.getState().actions.transitionSearch({ type: 'change_query', query: 'Sources' });
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
		store.getState().actions.transitionSearch({ type: 'change_query', query: 'Sources' });

		const snapshot = serializableViewerStateForBodyBoundary(store.getState());
		const snapshotJSON = JSON.stringify(snapshot);

		expect(snapshot.rootSnapshot.search.enteredCriteria.query).toBe('Sources');
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
		searchText: state.rootSnapshot.search.enteredCriteria.query,
	};
}
