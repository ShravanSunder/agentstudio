import type { BridgeWorkerSlicePatch } from './bridge-worker-contracts.js';

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
	readonly rowPaintById: Readonly<Record<string, Record<string, unknown>>>;
	readonly contentAvailabilityById: Readonly<Record<string, Record<string, unknown>>>;
	readonly panelChromeSlice: Readonly<Record<string, unknown>>;
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
					publishKeyedPatch(snapshot, publish, 'rowPaintById', patch);
					return;
				}
				case 'contentAvailability': {
					publishKeyedPatch(snapshot, publish, 'contentAvailabilityById', patch);
					return;
				}
				case 'panelChrome': {
					publish({
						...snapshot,
						panelChromeSlice: patch.payload ?? {},
					});
					return;
				}
			}
		},
	};
}

function buildSelectionSliceFromPatch(patch: BridgeWorkerSlicePatch): BridgeMainSelectionSlice {
	if (patch.operation === 'delete' || patch.operation === 'reset') {
		return {
			selectedItemId: null,
			source: null,
		};
	}
	const selectedItemId = readRequiredStringPatchPayload(patch, 'selectedItemId');
	return {
		selectedItemId,
		source: readOptionalSelectionSourcePatchPayload(patch),
	};
}

function buildViewportSliceFromPatch(patch: BridgeWorkerSlicePatch): BridgeMainViewportSlice {
	if (patch.operation === 'delete' || patch.operation === 'reset') {
		return {
			firstVisibleIndex: 0,
			lastVisibleIndex: 0,
			visibleItemIds: [],
		};
	}
	const visibleItemIds = readRequiredStringArrayPatchPayload(patch, 'visibleItemIds');
	return {
		firstVisibleIndex: readRequiredNumberPatchPayload(patch, 'firstVisibleIndex'),
		lastVisibleIndex: readRequiredNumberPatchPayload(patch, 'lastVisibleIndex'),
		visibleItemIds,
	};
}

function publishKeyedPatch(
	snapshot: BridgeMainRenderSnapshot,
	publish: (snapshot: BridgeMainRenderSnapshot) => void,
	key: 'rowPaintById' | 'contentAvailabilityById',
	patch: BridgeWorkerSlicePatch,
): void {
	if (patch.itemId === undefined) {
		throw new Error(`Bridge worker ${patch.slice} patch requires itemId.`);
	}
	const nextEntries = { ...snapshot[key] };
	if (patch.operation === 'delete') {
		delete nextEntries[patch.itemId];
	} else {
		nextEntries[patch.itemId] = patch.payload ?? {};
	}
	publish({
		...snapshot,
		[key]: nextEntries,
	});
}

function readRequiredStringPatchPayload(patch: BridgeWorkerSlicePatch, key: string): string {
	const value = patch.payload?.[key];
	if (typeof value !== 'string') {
		throw new Error(`Bridge worker ${patch.slice} patch requires string payload.${key}.`);
	}
	return value;
}

function readOptionalSelectionSourcePatchPayload(
	patch: BridgeWorkerSlicePatch,
): BridgeMainSelectionSlice['source'] {
	const value = patch.payload?.['source'];
	if (value === undefined) {
		return null;
	}
	if (value === 'user' || value === 'keyboard' || value === 'programmatic') {
		return value;
	}
	throw new Error(`Bridge worker selection patch has invalid payload.source.`);
}

function readRequiredNumberPatchPayload(patch: BridgeWorkerSlicePatch, key: string): number {
	const value = patch.payload?.[key];
	if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) {
		throw new Error(
			`Bridge worker ${patch.slice} patch requires nonnegative integer payload.${key}.`,
		);
	}
	return value;
}

function readRequiredStringArrayPatchPayload(
	patch: BridgeWorkerSlicePatch,
	key: string,
): readonly string[] {
	const value = patch.payload?.[key];
	if (!Array.isArray(value) || !value.every((item) => typeof item === 'string')) {
		throw new Error(`Bridge worker ${patch.slice} patch requires string[] payload.${key}.`);
	}
	return [...value];
}
