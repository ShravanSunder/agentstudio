import type {
	BridgeWorkerContentAvailabilityPatchPayload,
	BridgeWorkerPanelChromePatchPayload,
	BridgeWorkerRowPaintPatchPayload,
	BridgeWorkerSlicePatch,
} from './bridge-worker-contracts.js';
import type {
	BridgeWorkerCodeViewDiffItem,
	BridgeWorkerCodeViewFileItem,
} from './bridge-worker-pierre-render-job.js';

export type BridgeMainCodeViewItem = BridgeWorkerCodeViewFileItem | BridgeWorkerCodeViewDiffItem;

export interface BridgeMainSelectionSlice {
	readonly selectedItemId: string | null;
	readonly source: 'user' | 'keyboard' | 'programmatic' | null;
}

export interface BridgeMainViewportSlice {
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
	readonly visibleItemIds: readonly string[];
}

export type BridgeMainCodeViewItemPatch =
	| {
			readonly operation: 'delete';
			readonly itemId: string;
	  }
	| {
			readonly operation: 'reset';
	  }
	| {
			readonly operation: 'upsert';
			readonly itemId: string;
			readonly item: BridgeMainCodeViewItem;
	  };

export interface BridgeMainRenderSnapshotUpdate {
	readonly codeViewItemPatches?: readonly BridgeMainCodeViewItemPatch[];
	readonly localSelection?: SetBridgeMainLocalSelectionProps;
	readonly localViewport?: SetBridgeMainLocalViewportProps;
	readonly workerPatches?: readonly BridgeWorkerSlicePatch[];
}

export interface BridgeMainRenderSnapshot {
	readonly selectionSlice: BridgeMainSelectionSlice;
	readonly viewportSlice: BridgeMainViewportSlice;
	readonly rowPaintById: Readonly<Record<string, BridgeWorkerRowPaintPatchPayload>>;
	readonly contentAvailabilityById: Readonly<
		Record<string, BridgeWorkerContentAvailabilityPatchPayload>
	>;
	readonly codeViewItemsById: Readonly<Record<string, BridgeMainCodeViewItem>>;
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
	readonly setWorkerCodeViewItem: (props: {
		readonly itemId: string;
		readonly item: BridgeMainCodeViewItem;
	}) => void;
	readonly applyWorkerPatch: (patch: BridgeWorkerSlicePatch) => void;
	readonly applySnapshotUpdate: (update: BridgeMainRenderSnapshotUpdate) => void;
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
	codeViewItemsById: {},
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
			publish(
				buildSnapshotFromUpdate(snapshot, {
					localSelection: props,
				}),
			);
		},
		setLocalViewport: (props: SetBridgeMainLocalViewportProps): void => {
			publish(
				buildSnapshotFromUpdate(snapshot, {
					localViewport: props,
				}),
			);
		},
		setWorkerCodeViewItem: (props): void => {
			publish(
				buildSnapshotFromUpdate(snapshot, {
					codeViewItemPatches: [
						{
							operation: 'upsert',
							itemId: props.itemId,
							item: props.item,
						},
					],
				}),
			);
		},
		applyWorkerPatch: (patch: BridgeWorkerSlicePatch): void => {
			publish(
				buildSnapshotFromUpdate(snapshot, {
					workerPatches: [patch],
				}),
			);
		},
		applySnapshotUpdate: (update: BridgeMainRenderSnapshotUpdate): void => {
			publish(buildSnapshotFromUpdate(snapshot, update));
		},
	};
}

function buildSnapshotFromUpdate(
	snapshot: BridgeMainRenderSnapshot,
	update: BridgeMainRenderSnapshotUpdate,
): BridgeMainRenderSnapshot {
	let nextSnapshot = snapshot;
	if (update.localSelection !== undefined) {
		nextSnapshot = {
			...nextSnapshot,
			selectionSlice: update.localSelection,
		};
	}
	if (update.localViewport !== undefined) {
		nextSnapshot = {
			...nextSnapshot,
			viewportSlice: {
				firstVisibleIndex: update.localViewport.firstVisibleIndex,
				lastVisibleIndex: update.localViewport.lastVisibleIndex,
				visibleItemIds: [...update.localViewport.visibleItemIds],
			},
		};
	}
	for (const patch of update.codeViewItemPatches ?? []) {
		nextSnapshot = buildCodeViewItemPatchSnapshot(nextSnapshot, patch);
	}
	for (const patch of update.workerPatches ?? []) {
		nextSnapshot = buildWorkerPatchSnapshot(nextSnapshot, patch);
	}
	return nextSnapshot;
}

function buildCodeViewItemPatchSnapshot(
	snapshot: BridgeMainRenderSnapshot,
	patch: BridgeMainCodeViewItemPatch,
): BridgeMainRenderSnapshot {
	if (patch.operation === 'reset') {
		return {
			...snapshot,
			codeViewItemsById: {},
		};
	}
	const nextCodeViewItemsById = { ...snapshot.codeViewItemsById };
	if (patch.operation === 'delete') {
		delete nextCodeViewItemsById[patch.itemId];
	} else {
		nextCodeViewItemsById[patch.itemId] = patch.item;
	}
	return {
		...snapshot,
		codeViewItemsById: nextCodeViewItemsById,
	};
}

function buildWorkerPatchSnapshot(
	snapshot: BridgeMainRenderSnapshot,
	patch: BridgeWorkerSlicePatch,
): BridgeMainRenderSnapshot {
	switch (patch.slice) {
		case 'selection':
			return {
				...snapshot,
				selectionSlice: buildSelectionSliceFromPatch(patch),
			};
		case 'viewport':
			return {
				...snapshot,
				viewportSlice: buildViewportSliceFromPatch(patch),
			};
		case 'rowPaint':
			return buildRowPaintPatchSnapshot(snapshot, patch);
		case 'contentAvailability':
			return buildContentAvailabilityPatchSnapshot(snapshot, patch);
		case 'panelChrome':
			return {
				...snapshot,
				panelChromeSlice: patch.operation === 'upsert' ? patch.payload : {},
			};
	}
	return assertNeverBridgeWorkerSlicePatch(patch);
}

function assertNeverBridgeWorkerSlicePatch(patch: never): never {
	throw new Error(`Unhandled bridge worker slice patch: ${String(patch)}`);
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

function buildRowPaintPatchSnapshot(
	snapshot: BridgeMainRenderSnapshot,
	patch: Extract<BridgeWorkerSlicePatch, { slice: 'rowPaint' }>,
): BridgeMainRenderSnapshot {
	if (patch.operation === 'reset') {
		return {
			...snapshot,
			rowPaintById: {},
			codeViewItemsById: {},
		};
	}
	const nextEntries = { ...snapshot.rowPaintById };
	if (patch.operation === 'delete') {
		const nextCodeViewItemsById = { ...snapshot.codeViewItemsById };
		delete nextEntries[patch.itemId];
		delete nextCodeViewItemsById[patch.itemId];
		return {
			...snapshot,
			rowPaintById: nextEntries,
			codeViewItemsById: nextCodeViewItemsById,
		};
	} else {
		nextEntries[patch.itemId] = patch.payload;
	}
	return {
		...snapshot,
		rowPaintById: nextEntries,
	};
}

function buildContentAvailabilityPatchSnapshot(
	snapshot: BridgeMainRenderSnapshot,
	patch: Extract<BridgeWorkerSlicePatch, { slice: 'contentAvailability' }>,
): BridgeMainRenderSnapshot {
	if (patch.operation === 'reset') {
		return {
			...snapshot,
			contentAvailabilityById: {},
		};
	}
	const nextEntries = { ...snapshot.contentAvailabilityById };
	if (patch.operation === 'delete') {
		delete nextEntries[patch.itemId];
	} else {
		nextEntries[patch.itemId] = patch.payload;
	}
	return {
		...snapshot,
		contentAvailabilityById: nextEntries,
	};
}
