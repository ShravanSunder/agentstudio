import { useRef } from 'react';
import { useStore } from 'zustand';

import type { WorktreeFileSurfaceLoadTelemetry } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import type {
	BridgeFileViewerDemandDispatchDebugState,
	BridgeFileViewerInitialSurfaceLoadState,
	BridgeFileViewerOpenState,
	BridgeFileViewerRefreshDebugState,
	BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';
import {
	createBridgeFileViewerStore,
	selectBridgeFileViewerRootSnapshot,
	type BridgeFileViewerRootSnapshot,
	type BridgeFileViewerStore,
	type BridgeFileViewerStoreActions,
} from './state/bridge-file-viewer-store.js';

export interface BridgeFileViewerStoreBindings {
	readonly initialSurfaceLoadState: BridgeFileViewerInitialSurfaceLoadState;
	readonly lastDemandDispatchDebugState: BridgeFileViewerDemandDispatchDebugState;
	readonly lastOpenLoadTelemetry: WorktreeFileSurfaceLoadTelemetry | null;
	readonly openFileState: BridgeFileViewerOpenState;
	readonly refreshDebugState: BridgeFileViewerRefreshDebugState | null;
	readonly renderState: BridgeFileViewerRenderState;
	readonly rootSnapshot: BridgeFileViewerRootSnapshot;
	readonly viewerActions: BridgeFileViewerStoreActions;
	readonly viewerStore: BridgeFileViewerStore;
}

export function useBridgeFileViewerStoreBindings(): BridgeFileViewerStoreBindings {
	const storeRef = useRef<BridgeFileViewerStore | null>(null);
	if (storeRef.current === null) {
		storeRef.current = createBridgeFileViewerStore();
	}
	const viewerStore = storeRef.current;
	const rootSnapshot = useStore(viewerStore, selectBridgeFileViewerRootSnapshot);
	const viewerActions = useStore(viewerStore, (state) => state.actions);
	const renderState = useStore(viewerStore, (state) => state.renderState);
	const openFileState = useStore(viewerStore, (state) => state.openFileState);
	const initialSurfaceLoadState = useStore(viewerStore, (state) => state.initialSurfaceLoadState);
	const refreshDebugState = useStore(viewerStore, (state) => state.refreshDebugState);
	const lastOpenLoadTelemetry = useStore(viewerStore, (state) => state.lastOpenLoadTelemetry);
	const lastDemandDispatchDebugState = useStore(
		viewerStore,
		(state) => state.lastDemandDispatchDebugState,
	);

	return {
		initialSurfaceLoadState,
		lastDemandDispatchDebugState,
		lastOpenLoadTelemetry,
		openFileState,
		refreshDebugState,
		renderState,
		rootSnapshot,
		viewerActions,
		viewerStore,
	};
}
