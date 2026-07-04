import { subscribeWithSelector } from 'zustand/middleware';
import { createStore, type Mutate, type StoreApi } from 'zustand/vanilla';

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
export type BridgeContentHydrationStatusKind = 'idle' | 'queued' | 'loading' | 'ready' | 'failed';

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
	readonly status: BridgeContentHydrationStatusKind;
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

export interface BridgeContentHydrationStatus {
	readonly itemId: string;
	readonly status: BridgeContentHydrationStatusKind;
	readonly contentHandleId: string | null;
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
	readonly setContentHydrationStatus: (status: BridgeContentHydrationStatus) => void;
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
	readonly contentHydrationByItemId: Readonly<Record<string, BridgeContentHydrationStatus>>;
	readonly mountedItemIds: readonly string[];
	readonly actions: BridgeReviewViewerStoreActions;
}

export type BridgeReviewViewerStore = Mutate<
	StoreApi<BridgeReviewViewerStoreState>,
	[['zustand/subscribeWithSelector', never]]
>;

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
	return createStore<BridgeReviewViewerStoreState>()(
		subscribeWithSelector((set, get): BridgeReviewViewerStoreState => {
			const replacePanelChromeSlice = (patch: Partial<BridgeReviewPanelChromeSlice>): void => {
				set((state: BridgeReviewViewerStoreState): Partial<BridgeReviewViewerStoreState> => {
					const nextPanelChromeSlice = { ...state.panelChromeSlice, ...patch };
					if (panelChromeSlicesEqual(state.panelChromeSlice, nextPanelChromeSlice)) {
						return {};
					}
					return {
						panelChromeSlice: nextPanelChromeSlice,
						rootSnapshot: rootSnapshotFromSlices({
							panelChromeSlice: nextPanelChromeSlice,
							selectionSlice: state.selectionSlice,
						}),
					};
				});
			};

			return {
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
				contentHydrationByItemId: {},
				mountedItemIds: [],
				actions: {
					setSelectedItemId: (itemId: string | null): void => {
						set((state: BridgeReviewViewerStoreState): Partial<BridgeReviewViewerStoreState> => {
							if (state.selectionSlice.selectedItemId === itemId) {
								return {};
							}
							const nextSelectionSlice = { selectedItemId: itemId };
							return {
								selectionSlice: nextSelectionSlice,
								rowPaintByItemId: rowPaintSlicesForSelectionChange({
									nextSelectedItemId: itemId,
									previous: state.rowPaintByItemId,
									previousSelectedItemId: state.selectionSlice.selectedItemId,
								}),
								rootSnapshot: rootSnapshotFromSlices({
									panelChromeSlice: state.panelChromeSlice,
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
							get().projectionIdentity,
							identity,
						);
						set({
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
						const activeIdentity = get().activeProjectionRequestIdentity;
						if (!requestIdentitiesMatch(activeIdentity, props.identity)) {
							return false;
						}
						set({
							activeProjectionRequestIdentity: null,
							projection: props.result,
							projectionIdentity: props.identity,
							panelChromeSlice: {
								...get().panelChromeSlice,
								hasProjection: true,
								projectionStatus: 'ready',
							},
							rootSnapshot: rootSnapshotFromSlices({
								panelChromeSlice: {
									...get().panelChromeSlice,
									hasProjection: true,
									projectionStatus: 'ready',
								},
								selectionSlice: get().selectionSlice,
							}),
							workerStatus: {
								...get().workerStatus,
								pendingRequestCount: Math.max(0, get().workerStatus.pendingRequestCount - 1),
								lastCompletedRequestId: props.identity.requestId,
							},
						});
						return true;
					},
					failProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity): boolean => {
						const activeIdentity = get().activeProjectionRequestIdentity;
						if (!requestIdentitiesMatch(activeIdentity, identity)) {
							return false;
						}
						set({
							activeProjectionRequestIdentity: null,
							workerStatus: {
								...get().workerStatus,
								pendingRequestCount: Math.max(0, get().workerStatus.pendingRequestCount - 1),
								lastCompletedRequestId: identity.requestId,
							},
						});
						replacePanelChromeSlice({ projectionStatus: 'failed' });
						return true;
					},
					cancelProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity): boolean => {
						const activeIdentity = get().activeProjectionRequestIdentity;
						if (!requestIdentitiesMatch(activeIdentity, identity)) {
							return false;
						}
						set({
							activeProjectionRequestIdentity: null,
							workerStatus: {
								...get().workerStatus,
								pendingRequestCount: Math.max(0, get().workerStatus.pendingRequestCount - 1),
							},
						});
						replacePanelChromeSlice({ projectionStatus: 'idle' });
						return true;
					},
					setWorkerStatus: (status: BridgeReviewWorkerStatus): void => {
						set({ workerStatus: status });
					},
					setContentHydrationStatus: (status: BridgeContentHydrationStatus): void => {
						set(
							(state: BridgeReviewViewerStoreState): Partial<BridgeReviewViewerStoreState> => ({
								contentHydrationByItemId: {
									...state.contentHydrationByItemId,
									[status.itemId]: status,
								},
								contentAvailabilityByItemId: {
									...state.contentAvailabilityByItemId,
									[status.itemId]: contentAvailabilitySliceFromStatus(status),
								},
							}),
						);
					},
					setMountedItemIds: (itemIds: readonly string[]): void => {
						set({ mountedItemIds: itemIds, viewportSlice: { visibleItemIds: itemIds } });
					},
				},
			};
		}),
	);
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

function contentAvailabilitySliceFromStatus(
	status: BridgeContentHydrationStatus,
): BridgeReviewContentAvailabilitySlice {
	return {
		itemId: status.itemId,
		status: status.status,
		contentHandleId: status.contentHandleId,
	};
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
