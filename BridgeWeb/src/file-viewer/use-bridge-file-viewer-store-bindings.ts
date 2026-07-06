import { useMemo, useRef, useState } from 'react';

import type { WorktreeFileSurfaceLoadTelemetry } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import type {
	BridgeFileViewerDemandDispatchDebugState,
	BridgeFileViewerInitialSurfaceLoadState,
	BridgeFileViewerOpenState,
	BridgeFileViewerRefreshDebugState,
	BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';
import { emptyRenderState } from './bridge-file-viewer-state.js';
import {
	createBridgeFileViewerStore,
	selectBridgeFileViewerRootSnapshot,
	useBridgeFileViewerStoreSelector,
	type BridgeFileViewerRootSnapshot,
	type BridgeFileViewerStore,
	type BridgeFileViewerStoreActions,
} from './state/bridge-file-viewer-store.js';

export type BridgeFileViewerStoreBindingActions = BridgeFileViewerStoreActions &
	BridgeFileViewerLegacyDisplayStateActions;

export interface BridgeFileViewerLegacyDisplayStateActions {
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
}

export interface BridgeFileViewerStoreBindings {
	readonly initialSurfaceLoadState: BridgeFileViewerInitialSurfaceLoadState;
	readonly lastDemandDispatchDebugState: BridgeFileViewerDemandDispatchDebugState;
	readonly lastOpenLoadTelemetry: WorktreeFileSurfaceLoadTelemetry | null;
	readonly openFileState: BridgeFileViewerOpenState;
	readonly refreshDebugState: BridgeFileViewerRefreshDebugState | null;
	readonly renderState: BridgeFileViewerRenderState;
	readonly rootSnapshot: BridgeFileViewerRootSnapshot;
	readonly viewerActions: BridgeFileViewerStoreBindingActions;
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
	const viewerStoreActions = useBridgeFileViewerStoreSelector(
		viewerStore,
		(state) => state.actions,
	);
	const [renderState, setRenderState] = useState<BridgeFileViewerRenderState>(emptyRenderState);
	const [openFileState, setOpenFileState] = useState<BridgeFileViewerOpenState>({
		status: 'idle',
	});
	const [initialSurfaceLoadState, setInitialSurfaceLoadState] =
		useState<BridgeFileViewerInitialSurfaceLoadState>({ status: 'idle' });
	const [refreshDebugState, setRefreshDebugState] =
		useState<BridgeFileViewerRefreshDebugState | null>(null);
	const [lastOpenLoadTelemetry, setLastOpenLoadTelemetry] =
		useState<WorktreeFileSurfaceLoadTelemetry | null>(null);
	const [lastDemandDispatchDebugState, setLastDemandDispatchDebugState] =
		useState<BridgeFileViewerDemandDispatchDebugState>({ status: 'idle' });
	const displayStateActions = useMemo(
		(): BridgeFileViewerLegacyDisplayStateActions => ({
			setRenderState,
			setOpenFileState,
			setInitialSurfaceLoadState,
			setRefreshDebugState,
			setLastOpenLoadTelemetry,
			setLastDemandDispatchDebugState,
		}),
		[],
	);
	const viewerActions = useMemo(
		(): BridgeFileViewerStoreBindingActions => ({
			...displayStateActions,
			...viewerStoreActions,
		}),
		[displayStateActions, viewerStoreActions],
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
