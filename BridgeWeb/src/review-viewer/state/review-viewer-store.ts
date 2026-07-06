import { useRef, useSyncExternalStore } from 'react';

import type {
	BridgeReviewFilterState,
	BridgeReviewRenderMode,
	BridgeReviewSearchMode,
	BridgeReviewProjectionMode,
	BridgeReviewProjectionFacet,
	BridgeReviewProjectionRequestIdentity,
	BridgeReviewProjectionResult,
} from '../models/review-projection-models.js';

export type BridgeReviewProjectionStatus = 'idle' | 'running' | 'ready' | 'failed';
export type BridgeReviewWorkerLane = 'sync' | 'worker';
export type BridgeReviewContentAvailabilityStatusKind =
	| 'idle'
	| 'queued'
	| 'loading'
	| 'ready'
	| 'failed';

export interface BridgeReviewViewerRootSnapshot {
	readonly selectedItemId: string | null;
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly facets: readonly BridgeReviewProjectionFacet[];
	readonly treeSearchText: string;
	readonly treeSearchMode: BridgeReviewSearchMode;
	readonly gitStatusFilter: BridgeReviewFilterState['gitStatusFilter'];
	readonly fileClassFilter: BridgeReviewFilterState['fileClassFilter'];
	readonly renderMode: BridgeReviewRenderMode;
	readonly projectionStatus: BridgeReviewProjectionStatus;
}

export interface BridgeReviewSelectionSlice {
	readonly selectedItemId: string | null;
}

export interface BridgeReviewViewportSlice {
	readonly visibleItemIds: readonly string[];
}

export interface BridgeReviewRowPaintSlice {
	readonly itemId: string;
	readonly isSelected: boolean;
}

export interface BridgeReviewContentAvailabilitySlice {
	readonly itemId: string;
	readonly status: BridgeReviewContentAvailabilityStatusKind;
	readonly contentHandleId: string | null;
}

export interface BridgeReviewPanelChromeSlice {
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly facets: readonly BridgeReviewProjectionFacet[];
	readonly treeSearchText: string;
	readonly treeSearchMode: BridgeReviewSearchMode;
	readonly gitStatusFilter: BridgeReviewFilterState['gitStatusFilter'];
	readonly fileClassFilter: BridgeReviewFilterState['fileClassFilter'];
	readonly renderMode: BridgeReviewRenderMode;
	readonly projectionStatus: BridgeReviewProjectionStatus;
	readonly hasProjection: boolean;
}

export interface BridgeReviewWorkerStatus {
	readonly lane: BridgeReviewWorkerLane;
	readonly pendingRequestCount: number;
	readonly lastCompletedRequestId: string | null;
}

export interface ApplyProjectionWorkerResultProps {
	readonly identity: BridgeReviewProjectionRequestIdentity;
	readonly result: BridgeReviewProjectionResult;
}

export interface BridgeReviewViewerStoreActions {
	readonly setSelectedItemId: (itemId: string | null) => void;
	readonly setProjectionMode: (mode: BridgeReviewProjectionMode) => void;
	readonly setProjectionFacets: (facets: readonly BridgeReviewProjectionFacet[]) => void;
	readonly setTreeSearchText: (searchText: string) => void;
	readonly setTreeSearchMode: (searchMode: BridgeReviewSearchMode) => void;
	readonly setGitStatusFilter: (status: BridgeReviewFilterState['gitStatusFilter']) => void;
	readonly setFileClassFilter: (fileClass: BridgeReviewFilterState['fileClassFilter']) => void;
	readonly setRenderMode: (renderMode: BridgeReviewRenderMode) => void;
	readonly startProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity) => void;
	readonly applyProjectionWorkerResult: (props: ApplyProjectionWorkerResultProps) => boolean;
	readonly failProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity) => boolean;
	readonly cancelProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity) => boolean;
	readonly setWorkerStatus: (status: BridgeReviewWorkerStatus) => void;
	readonly setMountedItemIds: (itemIds: readonly string[]) => void;
}

export interface BridgeReviewViewerStoreState {
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly selectionSlice: BridgeReviewSelectionSlice;
	readonly viewportSlice: BridgeReviewViewportSlice;
	readonly rowPaintByItemId: Readonly<Record<string, BridgeReviewRowPaintSlice>>;
	readonly contentAvailabilityByItemId: Readonly<
		Record<string, BridgeReviewContentAvailabilitySlice>
	>;
	readonly panelChromeSlice: BridgeReviewPanelChromeSlice;
	readonly projection: BridgeReviewProjectionResult | null;
	readonly projectionIdentity: BridgeReviewProjectionRequestIdentity | null;
	readonly activeProjectionRequestIdentity: BridgeReviewProjectionRequestIdentity | null;
	readonly workerStatus: BridgeReviewWorkerStatus;
	readonly mountedItemIds: readonly string[];
	readonly actions: BridgeReviewViewerStoreActions;
}

export type BridgeReviewViewerStoreListener = () => void;

export interface BridgeReviewViewerStore {
	readonly getState: () => BridgeReviewViewerStoreState;
	readonly subscribe: (listener: BridgeReviewViewerStoreListener) => () => void;
	readonly subscribeSelector: <TSelected>(
		selector: (state: BridgeReviewViewerStoreState) => TSelected,
		listener: (slice: TSelected, previousSlice: TSelected) => void,
	) => () => void;
}

type BridgeReviewViewerStorePatch = Partial<BridgeReviewViewerStoreState>;

type BridgeReviewViewerStorePatchInput =
	| BridgeReviewViewerStorePatch
	| ((state: BridgeReviewViewerStoreState) => BridgeReviewViewerStorePatch);

interface BridgeReviewViewerStoreSelectorSubscription {
	readonly notifyIfChanged: (state: BridgeReviewViewerStoreState) => void;
}

interface BridgeReviewViewerStoreSelectorSnapshotCache<TSelected> {
	readonly selector: (state: BridgeReviewViewerStoreState) => TSelected;
	readonly slice: TSelected;
	readonly state: BridgeReviewViewerStoreState;
	readonly store: BridgeReviewViewerStore;
}

interface BridgeReviewViewerStoreSelectorSnapshotCacheRef<TSelected> {
	current: BridgeReviewViewerStoreSelectorSnapshotCache<TSelected> | null;
}

const defaultProjectionMode: BridgeReviewProjectionMode = { kind: 'normalReview' };
const defaultRenderMode: BridgeReviewRenderMode = { kind: 'codeView' };
const defaultTreeSearchMode: BridgeReviewSearchMode = { kind: 'text' };
const defaultSelectionSlice: BridgeReviewSelectionSlice = { selectedItemId: null };
const defaultPanelChromeSlice: BridgeReviewPanelChromeSlice = {
	projectionMode: defaultProjectionMode,
	facets: [],
	treeSearchText: '',
	treeSearchMode: defaultTreeSearchMode,
	gitStatusFilter: 'all',
	fileClassFilter: 'all',
	renderMode: defaultRenderMode,
	projectionStatus: 'idle',
	hasProjection: false,
};
const defaultViewportSlice: BridgeReviewViewportSlice = { visibleItemIds: [] };
const defaultRowPaintSliceByItemId = new Map<string, BridgeReviewRowPaintSlice>();
const defaultContentAvailabilitySliceByItemId = new Map<
	string,
	BridgeReviewContentAvailabilitySlice
>();

export function createBridgeReviewViewerStore(): BridgeReviewViewerStore {
	let state: BridgeReviewViewerStoreState;
	const listeners = new Set<BridgeReviewViewerStoreListener>();
	const selectorSubscriptions = new Set<BridgeReviewViewerStoreSelectorSubscription>();
	const getState = (): BridgeReviewViewerStoreState => state;
	const notify = (): void => {
		for (const listener of listeners) {
			listener();
		}
		for (const subscription of selectorSubscriptions) {
			subscription.notifyIfChanged(state);
		}
	};
	const setState = (patchInput: BridgeReviewViewerStorePatchInput): void => {
		const patch = typeof patchInput === 'function' ? patchInput(state) : patchInput;
		if (Object.keys(patch).length === 0) {
			return;
		}
		state = { ...state, ...patch };
		notify();
	};
	const replacePanelChromeSlice = (patch: Partial<BridgeReviewPanelChromeSlice>): void => {
		setState((currentState): BridgeReviewViewerStorePatch => {
			const nextPanelChromeSlice = { ...currentState.panelChromeSlice, ...patch };
			if (panelChromeSlicesEqual(currentState.panelChromeSlice, nextPanelChromeSlice)) {
				return {};
			}
			return {
				panelChromeSlice: nextPanelChromeSlice,
				rootSnapshot: rootSnapshotFromSlices({
					panelChromeSlice: nextPanelChromeSlice,
					selectionSlice: currentState.selectionSlice,
				}),
			};
		});
	};
	const actions: BridgeReviewViewerStoreActions = {
		setSelectedItemId: (itemId: string | null): void => {
			setState((currentState): BridgeReviewViewerStorePatch => {
				if (currentState.selectionSlice.selectedItemId === itemId) {
					return {};
				}
				const nextSelectionSlice = { selectedItemId: itemId };
				return {
					selectionSlice: nextSelectionSlice,
					rowPaintByItemId: rowPaintSlicesForSelectionChange({
						nextSelectedItemId: itemId,
						previous: currentState.rowPaintByItemId,
						previousSelectedItemId: currentState.selectionSlice.selectedItemId,
					}),
					rootSnapshot: rootSnapshotFromSlices({
						panelChromeSlice: currentState.panelChromeSlice,
						selectionSlice: nextSelectionSlice,
					}),
				};
			});
		},
		setProjectionMode: (mode: BridgeReviewProjectionMode): void => {
			replacePanelChromeSlice({ projectionMode: mode });
		},
		setProjectionFacets: (facets: readonly BridgeReviewProjectionFacet[]): void => {
			replacePanelChromeSlice({ facets });
		},
		setTreeSearchText: (searchText: string): void => {
			replacePanelChromeSlice({ treeSearchText: searchText });
		},
		setTreeSearchMode: (searchMode: BridgeReviewSearchMode): void => {
			replacePanelChromeSlice({ treeSearchMode: searchMode });
		},
		setGitStatusFilter: (status: BridgeReviewFilterState['gitStatusFilter']): void => {
			replacePanelChromeSlice({ gitStatusFilter: status });
		},
		setFileClassFilter: (fileClass: BridgeReviewFilterState['fileClassFilter']): void => {
			replacePanelChromeSlice({ fileClassFilter: fileClass });
		},
		setRenderMode: (renderMode: BridgeReviewRenderMode): void => {
			replacePanelChromeSlice({ renderMode });
		},
		startProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity): void => {
			const keepCurrentProjection = projectionIdentityMatchesReviewStream(
				getState().projectionIdentity,
				identity,
			);
			setState({
				activeProjectionRequestIdentity: identity,
				...(keepCurrentProjection
					? {}
					: {
							projection: null,
							projectionIdentity: null,
						}),
			});
			replacePanelChromeSlice({
				projectionStatus: 'running',
				...(keepCurrentProjection ? {} : { hasProjection: false }),
			});
		},
		applyProjectionWorkerResult: (props: ApplyProjectionWorkerResultProps): boolean => {
			const activeIdentity = getState().activeProjectionRequestIdentity;
			if (!requestIdentitiesMatch(activeIdentity, props.identity)) {
				return false;
			}
			const nextPanelChromeSlice: BridgeReviewPanelChromeSlice = {
				...getState().panelChromeSlice,
				hasProjection: true,
				projectionStatus: 'ready',
			};
			setState({
				activeProjectionRequestIdentity: null,
				projection: props.result,
				projectionIdentity: props.identity,
				panelChromeSlice: nextPanelChromeSlice,
				rootSnapshot: rootSnapshotFromSlices({
					panelChromeSlice: nextPanelChromeSlice,
					selectionSlice: getState().selectionSlice,
				}),
				workerStatus: {
					...getState().workerStatus,
					pendingRequestCount: Math.max(0, getState().workerStatus.pendingRequestCount - 1),
					lastCompletedRequestId: props.identity.requestId,
				},
			});
			return true;
		},
		failProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity): boolean => {
			const activeIdentity = getState().activeProjectionRequestIdentity;
			if (!requestIdentitiesMatch(activeIdentity, identity)) {
				return false;
			}
			setState({
				activeProjectionRequestIdentity: null,
				workerStatus: {
					...getState().workerStatus,
					pendingRequestCount: Math.max(0, getState().workerStatus.pendingRequestCount - 1),
					lastCompletedRequestId: identity.requestId,
				},
			});
			replacePanelChromeSlice({ projectionStatus: 'failed' });
			return true;
		},
		cancelProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity): boolean => {
			const activeIdentity = getState().activeProjectionRequestIdentity;
			if (!requestIdentitiesMatch(activeIdentity, identity)) {
				return false;
			}
			setState({
				activeProjectionRequestIdentity: null,
				workerStatus: {
					...getState().workerStatus,
					pendingRequestCount: Math.max(0, getState().workerStatus.pendingRequestCount - 1),
				},
			});
			replacePanelChromeSlice({ projectionStatus: 'idle' });
			return true;
		},
		setWorkerStatus: (status: BridgeReviewWorkerStatus): void => {
			setState({ workerStatus: status });
		},
		setMountedItemIds: (itemIds: readonly string[]): void => {
			setState({ mountedItemIds: itemIds, viewportSlice: { visibleItemIds: itemIds } });
		},
	};
	state = {
		rootSnapshot: rootSnapshotFromSlices({
			panelChromeSlice: defaultPanelChromeSlice,
			selectionSlice: defaultSelectionSlice,
		}),
		selectionSlice: defaultSelectionSlice,
		viewportSlice: defaultViewportSlice,
		rowPaintByItemId: {},
		contentAvailabilityByItemId: {},
		panelChromeSlice: defaultPanelChromeSlice,
		projection: null,
		projectionIdentity: null,
		activeProjectionRequestIdentity: null,
		workerStatus: {
			lane: 'sync',
			pendingRequestCount: 0,
			lastCompletedRequestId: null,
		},
		mountedItemIds: [],
		actions,
	};
	const subscribe = (listener: BridgeReviewViewerStoreListener): (() => void) => {
		listeners.add(listener);
		return (): void => {
			listeners.delete(listener);
		};
	};
	const subscribeSelector = <TSelected>(
		selector: (state: BridgeReviewViewerStoreState) => TSelected,
		listener: (slice: TSelected, previousSlice: TSelected) => void,
	): (() => void) => {
		let currentSlice = selector(state);
		const subscription: BridgeReviewViewerStoreSelectorSubscription = {
			notifyIfChanged: (nextState: BridgeReviewViewerStoreState): void => {
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

export function useBridgeReviewViewerStoreSelector<TSelected>(
	store: BridgeReviewViewerStore,
	selector: (state: BridgeReviewViewerStoreState) => TSelected,
): TSelected {
	const snapshotCacheRef = useRef<BridgeReviewViewerStoreSelectorSnapshotCache<TSelected> | null>(
		null,
	);
	return useSyncExternalStore(
		(listener): (() => void) => store.subscribe(listener),
		(): TSelected => readBridgeReviewViewerStoreSelectorSnapshot(snapshotCacheRef, store, selector),
		(): TSelected => readBridgeReviewViewerStoreSelectorSnapshot(snapshotCacheRef, store, selector),
	);
}

export function readBridgeReviewViewerStoreSelectorSnapshot<TSelected>(
	cacheRef: BridgeReviewViewerStoreSelectorSnapshotCacheRef<TSelected>,
	store: BridgeReviewViewerStore,
	selector: (state: BridgeReviewViewerStoreState) => TSelected,
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

export function selectBridgeReviewViewerRootSnapshot(
	state: BridgeReviewViewerStoreState,
): BridgeReviewViewerRootSnapshot {
	return state.rootSnapshot;
}

export function selectBridgeReviewSelectionSlice(
	state: BridgeReviewViewerStoreState,
): BridgeReviewSelectionSlice {
	return state.selectionSlice;
}

export function selectBridgeReviewViewportSlice(
	state: BridgeReviewViewerStoreState,
): BridgeReviewViewportSlice {
	return state.viewportSlice;
}

export function selectBridgeReviewRowPaintSlice(
	itemId: string,
): (state: BridgeReviewViewerStoreState) => BridgeReviewRowPaintSlice {
	return (state: BridgeReviewViewerStoreState): BridgeReviewRowPaintSlice =>
		state.rowPaintByItemId[itemId] ?? defaultRowPaintSlice(itemId);
}

export function selectBridgeReviewContentAvailabilitySlice(
	itemId: string,
): (state: BridgeReviewViewerStoreState) => BridgeReviewContentAvailabilitySlice {
	return (state: BridgeReviewViewerStoreState): BridgeReviewContentAvailabilitySlice =>
		state.contentAvailabilityByItemId[itemId] ?? defaultContentAvailabilitySlice(itemId);
}

export function selectBridgeReviewPanelChromeSlice(
	state: BridgeReviewViewerStoreState,
): BridgeReviewPanelChromeSlice {
	return state.panelChromeSlice;
}

export function bridgeReviewViewerRootSnapshotFromSlices(props: {
	readonly panelChromeSlice: BridgeReviewPanelChromeSlice;
	readonly selectionSlice: BridgeReviewSelectionSlice;
}): BridgeReviewViewerRootSnapshot {
	return rootSnapshotFromSlices(props);
}

export function bridgeReviewViewerRenderSliceStateKeys(): readonly string[] {
	return [
		'selectionSlice',
		'viewportSlice',
		'rowPaintSlice',
		'contentAvailabilitySlice',
		'panelChromeSlice',
	];
}

function requestIdentitiesMatch(
	left: BridgeReviewProjectionRequestIdentity | null,
	right: BridgeReviewProjectionRequestIdentity,
): boolean {
	return (
		left !== null &&
		left.requestId === right.requestId &&
		left.packageId === right.packageId &&
		left.reviewGeneration === right.reviewGeneration &&
		left.revision === right.revision &&
		left.projectionRequestFingerprint === right.projectionRequestFingerprint &&
		left.abortKey === right.abortKey
	);
}

function projectionIdentityMatchesReviewStream(
	left: BridgeReviewProjectionRequestIdentity | null,
	right: BridgeReviewProjectionRequestIdentity,
): boolean {
	return (
		left !== null &&
		left.packageId === right.packageId &&
		left.reviewGeneration === right.reviewGeneration
	);
}

function rootSnapshotFromSlices(props: {
	readonly panelChromeSlice: BridgeReviewPanelChromeSlice;
	readonly selectionSlice: BridgeReviewSelectionSlice;
}): BridgeReviewViewerRootSnapshot {
	return {
		selectedItemId: props.selectionSlice.selectedItemId,
		projectionMode: props.panelChromeSlice.projectionMode,
		facets: props.panelChromeSlice.facets,
		treeSearchText: props.panelChromeSlice.treeSearchText,
		treeSearchMode: props.panelChromeSlice.treeSearchMode,
		gitStatusFilter: props.panelChromeSlice.gitStatusFilter,
		fileClassFilter: props.panelChromeSlice.fileClassFilter,
		renderMode: props.panelChromeSlice.renderMode,
		projectionStatus: props.panelChromeSlice.projectionStatus,
	};
}

function panelChromeSlicesEqual(
	left: BridgeReviewPanelChromeSlice,
	right: BridgeReviewPanelChromeSlice,
): boolean {
	return (
		left.projectionMode.kind === right.projectionMode.kind &&
		left.facets === right.facets &&
		left.treeSearchText === right.treeSearchText &&
		left.treeSearchMode.kind === right.treeSearchMode.kind &&
		left.gitStatusFilter === right.gitStatusFilter &&
		left.fileClassFilter === right.fileClassFilter &&
		left.renderMode.kind === right.renderMode.kind &&
		left.projectionStatus === right.projectionStatus &&
		left.hasProjection === right.hasProjection
	);
}

function rowPaintSlicesForSelectionChange(props: {
	readonly previous: Readonly<Record<string, BridgeReviewRowPaintSlice>>;
	readonly previousSelectedItemId: string | null;
	readonly nextSelectedItemId: string | null;
}): Readonly<Record<string, BridgeReviewRowPaintSlice>> {
	const next = { ...props.previous };
	if (props.previousSelectedItemId !== null) {
		next[props.previousSelectedItemId] = {
			itemId: props.previousSelectedItemId,
			isSelected: false,
		};
	}
	if (props.nextSelectedItemId !== null) {
		next[props.nextSelectedItemId] = {
			itemId: props.nextSelectedItemId,
			isSelected: true,
		};
	}
	return next;
}

function defaultRowPaintSlice(itemId: string): BridgeReviewRowPaintSlice {
	const existing = defaultRowPaintSliceByItemId.get(itemId);
	if (existing !== undefined) {
		return existing;
	}
	const slice = { itemId, isSelected: false };
	defaultRowPaintSliceByItemId.set(itemId, slice);
	return slice;
}

function defaultContentAvailabilitySlice(itemId: string): BridgeReviewContentAvailabilitySlice {
	const existing = defaultContentAvailabilitySliceByItemId.get(itemId);
	if (existing !== undefined) {
		return existing;
	}
	const slice = {
		itemId,
		status: 'idle',
		contentHandleId: null,
	} satisfies BridgeReviewContentAvailabilitySlice;
	defaultContentAvailabilitySliceByItemId.set(itemId, slice);
	return slice;
}
