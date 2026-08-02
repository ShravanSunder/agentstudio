import { useRef, useSyncExternalStore } from 'react';

import {
	createBridgeViewerSearchState,
	transitionBridgeViewerSearchState,
	type BridgeViewerSearchAction,
	type BridgeViewerSearchState,
	type BridgeViewerSearchTransition,
} from '../../app/bridge-viewer-search-state.js';
import type { BridgeFileViewerFilterMode } from '../bridge-file-viewer-contracts.js';

export interface BridgeFileViewerRootSnapshot {
	readonly search: BridgeViewerSearchState;
	readonly filterMode: BridgeFileViewerFilterMode;
}

export interface BridgeFileViewerStoreActions {
	readonly transitionSearch: (action: BridgeViewerSearchAction) => BridgeViewerSearchTransition;
	readonly setFilterMode: (filterMode: BridgeFileViewerFilterMode) => void;
}

export interface BridgeFileViewerStoreState {
	readonly rootSnapshot: BridgeFileViewerRootSnapshot;
	readonly actions: BridgeFileViewerStoreActions;
}

export type BridgeFileViewerStoreListener = () => void;

export interface BridgeFileViewerStore {
	readonly getState: () => BridgeFileViewerStoreState;
	readonly subscribe: (listener: BridgeFileViewerStoreListener) => () => void;
	readonly subscribeSelector: <TSelected>(
		selector: (state: BridgeFileViewerStoreState) => TSelected,
		listener: (slice: TSelected, previousSlice: TSelected) => void,
	) => () => void;
}

type BridgeFileViewerStorePatch = Partial<BridgeFileViewerStoreState>;

type BridgeFileViewerStorePatchInput =
	| BridgeFileViewerStorePatch
	| ((state: BridgeFileViewerStoreState) => BridgeFileViewerStorePatch);

interface BridgeFileViewerStoreSelectorSubscription {
	readonly notifyIfChanged: (state: BridgeFileViewerStoreState) => void;
}

interface BridgeFileViewerStoreSelectorSnapshotCache<TSelected> {
	readonly selector: (state: BridgeFileViewerStoreState) => TSelected;
	readonly slice: TSelected;
	readonly state: BridgeFileViewerStoreState;
	readonly store: BridgeFileViewerStore;
}

interface BridgeFileViewerStoreSelectorSnapshotCacheRef<TSelected> {
	current: BridgeFileViewerStoreSelectorSnapshotCache<TSelected> | null;
}

export function createBridgeFileViewerStore(): BridgeFileViewerStore {
	let state: BridgeFileViewerStoreState;
	const listeners = new Set<BridgeFileViewerStoreListener>();
	const selectorSubscriptions = new Set<BridgeFileViewerStoreSelectorSubscription>();
	const getState = (): BridgeFileViewerStoreState => state;
	const notify = (): void => {
		for (const listener of listeners) {
			listener();
		}
		for (const subscription of selectorSubscriptions) {
			subscription.notifyIfChanged(state);
		}
	};
	const setState = (patchInput: BridgeFileViewerStorePatchInput): void => {
		const patch = typeof patchInput === 'function' ? patchInput(state) : patchInput;
		if (Object.keys(patch).length === 0) {
			return;
		}
		state = { ...state, ...patch };
		notify();
	};
	const replaceRootSnapshot = (patch: Partial<BridgeFileViewerRootSnapshot>): void => {
		setState(
			(currentState): BridgeFileViewerStorePatch => ({
				rootSnapshot: {
					...currentState.rootSnapshot,
					...patch,
				},
			}),
		);
	};
	const actions: BridgeFileViewerStoreActions = {
		transitionSearch: (action: BridgeViewerSearchAction): BridgeViewerSearchTransition => {
			const transition = transitionBridgeViewerSearchState(state.rootSnapshot.search, action);
			if (transition.state !== state.rootSnapshot.search) {
				replaceRootSnapshot({ search: transition.state });
			}
			return transition;
		},
		setFilterMode: (filterMode: BridgeFileViewerFilterMode): void => {
			replaceRootSnapshot({ filterMode });
		},
	};
	state = {
		rootSnapshot: {
			search: createBridgeViewerSearchState(),
			filterMode: 'all',
		},
		actions,
	};
	const subscribe = (listener: BridgeFileViewerStoreListener): (() => void) => {
		listeners.add(listener);
		return (): void => {
			listeners.delete(listener);
		};
	};
	const subscribeSelector = <TSelected>(
		selector: (state: BridgeFileViewerStoreState) => TSelected,
		listener: (slice: TSelected, previousSlice: TSelected) => void,
	): (() => void) => {
		let currentSlice = selector(state);
		const subscription: BridgeFileViewerStoreSelectorSubscription = {
			notifyIfChanged: (nextState: BridgeFileViewerStoreState): void => {
				const nextSlice = selector(nextState);
				if (Object.is(nextSlice, currentSlice)) {
					return;
				}
				const previousSlice = currentSlice;
				currentSlice = nextSlice;
				listener(nextSlice, previousSlice);
			},
		};
		selectorSubscriptions.add(subscription);
		return (): void => {
			selectorSubscriptions.delete(subscription);
		};
	};
	return {
		getState,
		subscribe,
		subscribeSelector,
	};
}

export function useBridgeFileViewerStoreSelector<TSelected>(
	store: BridgeFileViewerStore,
	selector: (state: BridgeFileViewerStoreState) => TSelected,
): TSelected {
	const snapshotCacheRef = useRef<BridgeFileViewerStoreSelectorSnapshotCache<TSelected> | null>(
		null,
	);
	return useSyncExternalStore(
		(listener): (() => void) => store.subscribe(listener),
		(): TSelected => readBridgeFileViewerStoreSelectorSnapshot(snapshotCacheRef, store, selector),
		(): TSelected => readBridgeFileViewerStoreSelectorSnapshot(snapshotCacheRef, store, selector),
	);
}

export function readBridgeFileViewerStoreSelectorSnapshot<TSelected>(
	cacheRef: BridgeFileViewerStoreSelectorSnapshotCacheRef<TSelected>,
	store: BridgeFileViewerStore,
	selector: (state: BridgeFileViewerStoreState) => TSelected,
): TSelected {
	const nextState = store.getState();
	const cached = cacheRef.current;
	if (cached?.store === store && cached.selector === selector && cached.state === nextState) {
		return cached.slice;
	}
	const nextSlice = selector(nextState);
	cacheRef.current = {
		selector,
		slice: nextSlice,
		state: nextState,
		store,
	};
	return nextSlice;
}

export function selectBridgeFileViewerRootSnapshot(
	state: BridgeFileViewerStoreState,
): BridgeFileViewerRootSnapshot {
	return state.rootSnapshot;
}
