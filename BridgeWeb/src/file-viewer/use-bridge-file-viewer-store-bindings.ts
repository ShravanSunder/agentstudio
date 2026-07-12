import { useRef } from 'react';

import {
	createBridgeFileViewerStore,
	selectBridgeFileViewerRootSnapshot,
	useBridgeFileViewerStoreSelector,
	type BridgeFileViewerRootSnapshot,
	type BridgeFileViewerStore,
	type BridgeFileViewerStoreActions,
} from './state/bridge-file-viewer-store.js';

export interface BridgeFileViewerStoreBindings {
	readonly rootSnapshot: BridgeFileViewerRootSnapshot;
	readonly viewerActions: BridgeFileViewerStoreActions;
	readonly viewerStore: BridgeFileViewerStore;
}

export function useBridgeFileViewerStoreBindings(): BridgeFileViewerStoreBindings {
	const storeRef = useRef<BridgeFileViewerStore | null>(null);
	storeRef.current ??= createBridgeFileViewerStore();
	const viewerStore = storeRef.current;
	const rootSnapshot = useBridgeFileViewerStoreSelector(
		viewerStore,
		selectBridgeFileViewerRootSnapshot,
	);
	const viewerActions = useBridgeFileViewerStoreSelector(viewerStore, (state) => state.actions);
	return { rootSnapshot, viewerActions, viewerStore };
}
