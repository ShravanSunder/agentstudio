import type {
	BridgeWorkerContentAvailabilityPatchPayload,
	BridgeWorkerPanelChromePatchPayload,
	BridgeWorkerRowPaintPatchPayload,
	BridgeWorkerSlicePatch,
} from './bridge-worker-contracts.js';

export interface BridgeMainSelectionSlice {
	readonly selectedItemId: string | null;
	readonly source: 'user' | 'keyboard' | 'programmatic' | null;
}

export interface BridgeMainViewportSlice {
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
	readonly visibleItemIds: readonly string[];
}

export interface BridgeMainRenderSnapshot {
	readonly selectionSlice: BridgeMainSelectionSlice;
	readonly viewportSlice: BridgeMainViewportSlice;
	readonly rowPaintById: Readonly<Record<string, BridgeWorkerRowPaintPatchPayload>>;
	readonly contentAvailabilityById: Readonly<
		Record<string, BridgeWorkerContentAvailabilityPatchPayload>
	>;
	readonly panelChromeSlice: BridgeWorkerPanelChromePatchPayload;
}

export interface SetBridgeMainLocalSelectionProps {
	readonly selectedItemId: string;
	readonly source: 'user' | 'keyboard' | 'programmatic';
}

export interface SetBridgeMainLocalViewportProps {
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
	readonly visibleItemIds: readonly string[];
}

export interface BridgeMainRenderSnapshotStore {
	readonly getSnapshot: () => BridgeMainRenderSnapshot;
	readonly getServerSnapshot: () => BridgeMainRenderSnapshot;
	readonly subscribe: (listener: () => void) => () => void;
	readonly setLocalSelection: (props: SetBridgeMainLocalSelectionProps) => void;
	readonly setLocalViewport: (props: SetBridgeMainLocalViewportProps) => void;
	readonly applyWorkerPatch: (patch: BridgeWorkerSlicePatch) => void;
}

const EMPTY_BRIDGE_MAIN_RENDER_SNAPSHOT: BridgeMainRenderSnapshot = {
	selectionSlice: {
		selectedItemId: null,
		source: null,
	},
	viewportSlice: {
		firstVisibleIndex: 0,
		lastVisibleIndex: 0,
		visibleItemIds: [],
	},
	rowPaintById: {},
	contentAvailabilityById: {},
	panelChromeSlice: {},
};

export function createBridgeMainRenderSnapshotStore(): BridgeMainRenderSnapshotStore {
	let snapshot = EMPTY_BRIDGE_MAIN_RENDER_SNAPSHOT;
	const listeners = new Set<() => void>();

	const publish = (nextSnapshot: BridgeMainRenderSnapshot): void => {
		snapshot = nextSnapshot;
		for (const listener of listeners) {
			listener();
		}
	};

	return {
		getSnapshot: (): BridgeMainRenderSnapshot => snapshot,
		getServerSnapshot: (): BridgeMainRenderSnapshot => snapshot,
		subscribe: (listener: () => void): (() => void) => {
			listeners.add(listener);
			return (): void => {
				listeners.delete(listener);
			};
		},
		setLocalSelection: (props: SetBridgeMainLocalSelectionProps): void => {
			publish({
				...snapshot,
				selectionSlice: props,
			});
		},
		setLocalViewport: (props: SetBridgeMainLocalViewportProps): void => {
			publish({
				...snapshot,
				viewportSlice: {
					firstVisibleIndex: props.firstVisibleIndex,
					lastVisibleIndex: props.lastVisibleIndex,
					visibleItemIds: [...props.visibleItemIds],
				},
			});
		},
		applyWorkerPatch: (patch: BridgeWorkerSlicePatch): void => {
			switch (patch.slice) {
				case 'selection': {
					publish({
						...snapshot,
						selectionSlice: buildSelectionSliceFromPatch(patch),
					});
					return;
				}
				case 'viewport': {
					publish({
						...snapshot,
						viewportSlice: buildViewportSliceFromPatch(patch),
					});
					return;
				}
				case 'rowPaint': {
					publishRowPaintPatch(snapshot, publish, patch);
					return;
				}
				case 'contentAvailability': {
					publishContentAvailabilityPatch(snapshot, publish, patch);
					return;
				}
				case 'panelChrome': {
					publish({
						...snapshot,
						panelChromeSlice: patch.operation === 'upsert' ? patch.payload : {},
					});
					return;
				}
			}
		},
	};
}

function buildSelectionSliceFromPatch(
	patch: Extract<BridgeWorkerSlicePatch, { slice: 'selection' }>,
): BridgeMainSelectionSlice {
	if (patch.operation === 'delete' || patch.operation === 'reset') {
		return {
			selectedItemId: null,
			source: null,
		};
	}
	return {
		selectedItemId: patch.payload.selectedItemId,
		source: patch.payload.source ?? null,
	};
}

function buildViewportSliceFromPatch(
	patch: Extract<BridgeWorkerSlicePatch, { slice: 'viewport' }>,
): BridgeMainViewportSlice {
	if (patch.operation === 'delete' || patch.operation === 'reset') {
		return {
			firstVisibleIndex: 0,
			lastVisibleIndex: 0,
			visibleItemIds: [],
		};
	}
	return {
		firstVisibleIndex: patch.payload.firstVisibleIndex,
		lastVisibleIndex: patch.payload.lastVisibleIndex,
		visibleItemIds: [...patch.payload.visibleItemIds],
	};
}

function publishRowPaintPatch(
	snapshot: BridgeMainRenderSnapshot,
	publish: (snapshot: BridgeMainRenderSnapshot) => void,
	patch: Extract<BridgeWorkerSlicePatch, { slice: 'rowPaint' }>,
): void {
	if (patch.operation === 'reset') {
		publish({
			...snapshot,
			rowPaintById: {},
		});
		return;
	}
	const nextEntries = { ...snapshot.rowPaintById };
	if (patch.operation === 'delete') {
		delete nextEntries[patch.itemId];
	} else {
		nextEntries[patch.itemId] = patch.payload;
	}
	publish({
		...snapshot,
		rowPaintById: nextEntries,
	});
}

function publishContentAvailabilityPatch(
	snapshot: BridgeMainRenderSnapshot,
	publish: (snapshot: BridgeMainRenderSnapshot) => void,
	patch: Extract<BridgeWorkerSlicePatch, { slice: 'contentAvailability' }>,
): void {
	if (patch.operation === 'reset') {
		publish({
			...snapshot,
			contentAvailabilityById: {},
		});
		return;
	}
	const nextEntries = { ...snapshot.contentAvailabilityById };
	if (patch.operation === 'delete') {
		delete nextEntries[patch.itemId];
	} else {
		nextEntries[patch.itemId] = patch.payload;
	}
	publish({
		...snapshot,
		contentAvailabilityById: nextEntries,
	});
}
