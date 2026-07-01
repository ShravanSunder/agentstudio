import { subscribeWithSelector } from 'zustand/middleware';
import { createStore, type Mutate, type StoreApi } from 'zustand/vanilla';

import type { WorktreeFileSurfaceLoadTelemetry } from '../../worktree-file-surface/worktree-file-surface-runtime.js';
import {
	emptyRenderState,
	type BridgeFileViewerDemandDispatchDebugState,
	type BridgeFileViewerInitialSurfaceLoadState,
	type BridgeFileViewerOpenState,
	type BridgeFileViewerRefreshDebugState,
	type BridgeFileViewerRenderState,
} from '../bridge-file-viewer-state.js';
import type {
	BridgeFileViewerFilterMode,
	BridgeFileViewerSearchMode,
} from '../bridge-file-viewer-tree-panel.js';

export interface BridgeFileViewerRootSnapshot {
	readonly renderState: BridgeFileViewerRenderState;
	readonly openFileState: BridgeFileViewerOpenState;
	readonly initialSurfaceLoadState: BridgeFileViewerInitialSurfaceLoadState;
	readonly refreshDebugState: BridgeFileViewerRefreshDebugState | null;
	readonly lastOpenLoadTelemetry: WorktreeFileSurfaceLoadTelemetry | null;
	readonly lastDemandDispatchDebugState: BridgeFileViewerDemandDispatchDebugState;
	readonly searchText: string;
	readonly searchMode: BridgeFileViewerSearchMode;
	readonly filterMode: BridgeFileViewerFilterMode;
}

export interface BridgeFileViewerStoreActions {
	readonly setRenderState: (renderState: BridgeFileViewerRenderState) => void;
	readonly setOpenFileState: (
		openFileState:
			| BridgeFileViewerOpenState
			| ((currentOpenFileState: BridgeFileViewerOpenState) => BridgeFileViewerOpenState),
	) => void;
	readonly setInitialSurfaceLoadState: (
		initialSurfaceLoadState: BridgeFileViewerInitialSurfaceLoadState,
	) => void;
	readonly setRefreshDebugState: (
		refreshDebugState: BridgeFileViewerRefreshDebugState | null,
	) => void;
	readonly setLastOpenLoadTelemetry: (
		lastOpenLoadTelemetry: WorktreeFileSurfaceLoadTelemetry | null,
	) => void;
	readonly setLastDemandDispatchDebugState: (
		lastDemandDispatchDebugState: BridgeFileViewerDemandDispatchDebugState,
	) => void;
	readonly setSearchText: (searchText: string) => void;
	readonly setSearchMode: (searchMode: BridgeFileViewerSearchMode) => void;
	readonly setFilterMode: (filterMode: BridgeFileViewerFilterMode) => void;
}

export interface BridgeFileViewerStoreState {
	readonly rootSnapshot: BridgeFileViewerRootSnapshot;
	readonly actions: BridgeFileViewerStoreActions;
}

export type BridgeFileViewerStore = Mutate<
	StoreApi<BridgeFileViewerStoreState>,
	[['zustand/subscribeWithSelector', never]]
>;

export function createBridgeFileViewerStore(): BridgeFileViewerStore {
	return createStore<BridgeFileViewerStoreState>()(
		subscribeWithSelector((set): BridgeFileViewerStoreState => {
			const replaceRootSnapshot = (patch: Partial<BridgeFileViewerRootSnapshot>): void => {
				set(
					(state: BridgeFileViewerStoreState): Partial<BridgeFileViewerStoreState> => ({
						rootSnapshot: {
							...state.rootSnapshot,
							...patch,
						},
					}),
				);
			};

			return {
				rootSnapshot: {
					renderState: emptyRenderState,
					openFileState: { status: 'idle' },
					initialSurfaceLoadState: { status: 'idle' },
					refreshDebugState: null,
					lastOpenLoadTelemetry: null,
					lastDemandDispatchDebugState: { status: 'idle' },
					searchText: '',
					searchMode: 'text',
					filterMode: 'all',
				},
				actions: {
					setRenderState: (renderState: BridgeFileViewerRenderState): void => {
						replaceRootSnapshot({ renderState });
					},
					setOpenFileState: (
						openFileState:
							| BridgeFileViewerOpenState
							| ((currentOpenFileState: BridgeFileViewerOpenState) => BridgeFileViewerOpenState),
					): void => {
						set(
							(state: BridgeFileViewerStoreState): Partial<BridgeFileViewerStoreState> => ({
								rootSnapshot: {
									...state.rootSnapshot,
									openFileState:
										typeof openFileState === 'function'
											? openFileState(state.rootSnapshot.openFileState)
											: openFileState,
								},
							}),
						);
					},
					setInitialSurfaceLoadState: (
						initialSurfaceLoadState: BridgeFileViewerInitialSurfaceLoadState,
					): void => {
						replaceRootSnapshot({ initialSurfaceLoadState });
					},
					setRefreshDebugState: (
						refreshDebugState: BridgeFileViewerRefreshDebugState | null,
					): void => {
						replaceRootSnapshot({ refreshDebugState });
					},
					setLastOpenLoadTelemetry: (
						lastOpenLoadTelemetry: WorktreeFileSurfaceLoadTelemetry | null,
					): void => {
						replaceRootSnapshot({ lastOpenLoadTelemetry });
					},
					setLastDemandDispatchDebugState: (
						lastDemandDispatchDebugState: BridgeFileViewerDemandDispatchDebugState,
					): void => {
						replaceRootSnapshot({ lastDemandDispatchDebugState });
					},
					setSearchText: (searchText: string): void => {
						replaceRootSnapshot({ searchText });
					},
					setSearchMode: (searchMode: BridgeFileViewerSearchMode): void => {
						replaceRootSnapshot({ searchMode });
					},
					setFilterMode: (filterMode: BridgeFileViewerFilterMode): void => {
						replaceRootSnapshot({ filterMode });
					},
				},
			};
		}),
	);
}

export function selectBridgeFileViewerRootSnapshot(
	state: BridgeFileViewerStoreState,
): BridgeFileViewerRootSnapshot {
	return state.rootSnapshot;
}
