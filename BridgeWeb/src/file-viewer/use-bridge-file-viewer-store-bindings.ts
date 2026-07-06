import { useRef } from 'react';

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
	useBridgeFileViewerStoreSelector,
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
	const rootSnapshot = useBridgeFileViewerStoreSelector(
		viewerStore,
		selectBridgeFileViewerRootSnapshot,
	);
	const viewerActions = useBridgeFileViewerStoreSelector(viewerStore, (state) => state.actions);
	const renderState = useBridgeFileViewerStoreSelector(viewerStore, (state) => state.renderState);
	const openFileState = useBridgeFileViewerStoreSelector(
		viewerStore,
		(state) => state.openFileState,
	);
	const initialSurfaceLoadState = useBridgeFileViewerStoreSelector(
		viewerStore,
		(state) => state.initialSurfaceLoadState,
	);
	const refreshDebugState = useBridgeFileViewerStoreSelector(
		viewerStore,
		(state) => state.refreshDebugState,
	);
	const lastOpenLoadTelemetry = useBridgeFileViewerStoreSelector(
		viewerStore,
		(state) => state.lastOpenLoadTelemetry,
	);
	const lastDemandDispatchDebugState = useBridgeFileViewerStoreSelector(
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
