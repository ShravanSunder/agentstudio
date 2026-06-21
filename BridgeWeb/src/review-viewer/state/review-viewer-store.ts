import { subscribeWithSelector } from 'zustand/middleware';
import { createStore, type Mutate, type StoreApi } from 'zustand/vanilla';

import type {
	BridgeReviewFilterState,
	BridgeReviewRenderMode,
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
	readonly gitStatusFilter: BridgeReviewFilterState['gitStatusFilter'];
	readonly fileClassFilter: BridgeReviewFilterState['fileClassFilter'];
	readonly renderMode: BridgeReviewRenderMode;
	readonly projectionStatus: BridgeReviewProjectionStatus;
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
	readonly setGitStatusFilter: (status: BridgeReviewFilterState['gitStatusFilter']) => void;
	readonly setFileClassFilter: (fileClass: BridgeReviewFilterState['fileClassFilter']) => void;
	readonly setRenderMode: (renderMode: BridgeReviewRenderMode) => void;
	readonly startProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity) => void;
	readonly applyProjectionWorkerResult: (props: ApplyProjectionWorkerResultProps) => boolean;
	readonly failProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity) => boolean;
	readonly cancelProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity) => boolean;
	readonly setWorkerStatus: (status: BridgeReviewWorkerStatus) => void;
	readonly setContentHydrationStatus: (status: BridgeContentHydrationStatus) => void;
}

export interface BridgeReviewViewerStoreState {
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
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

export function createBridgeReviewViewerStore(): BridgeReviewViewerStore {
	return createStore<BridgeReviewViewerStoreState>()(
		subscribeWithSelector((set, get): BridgeReviewViewerStoreState => {
			const replaceRootSnapshot = (patch: Partial<BridgeReviewViewerRootSnapshot>): void => {
				set(
					(state: BridgeReviewViewerStoreState): Partial<BridgeReviewViewerStoreState> => ({
						rootSnapshot: {
							...state.rootSnapshot,
							...patch,
						},
					}),
				);
			};

			return {
				rootSnapshot: {
					selectedItemId: null,
					projectionMode: defaultProjectionMode,
					facets: [],
					treeSearchText: '',
					gitStatusFilter: 'all',
					fileClassFilter: 'all',
					renderMode: defaultRenderMode,
					projectionStatus: 'idle',
				},
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
						replaceRootSnapshot({ selectedItemId: itemId });
					},
					setProjectionMode: (mode: BridgeReviewProjectionMode): void => {
						replaceRootSnapshot({ projectionMode: mode });
					},
					setProjectionFacets: (facets: readonly BridgeReviewProjectionFacet[]): void => {
						replaceRootSnapshot({ facets });
					},
					setTreeSearchText: (searchText: string): void => {
						replaceRootSnapshot({ treeSearchText: searchText });
					},
					setGitStatusFilter: (status: BridgeReviewFilterState['gitStatusFilter']): void => {
						replaceRootSnapshot({ gitStatusFilter: status });
					},
					setFileClassFilter: (fileClass: BridgeReviewFilterState['fileClassFilter']): void => {
						replaceRootSnapshot({ fileClassFilter: fileClass });
					},
					setRenderMode: (renderMode: BridgeReviewRenderMode): void => {
						replaceRootSnapshot({ renderMode });
					},
					startProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity): void => {
						set((state: BridgeReviewViewerStoreState): Partial<BridgeReviewViewerStoreState> => {
							const keepCurrentProjection = projectionIdentityMatchesPackageRevision(
								state.projectionIdentity,
								identity,
							);
							return {
								activeProjectionRequestIdentity: identity,
								...(keepCurrentProjection
									? {}
									: {
											projection: null,
											projectionIdentity: null,
										}),
							};
						});
						replaceRootSnapshot({ projectionStatus: 'running' });
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
							workerStatus: {
								...get().workerStatus,
								pendingRequestCount: Math.max(0, get().workerStatus.pendingRequestCount - 1),
								lastCompletedRequestId: props.identity.requestId,
							},
						});
						replaceRootSnapshot({ projectionStatus: 'ready' });
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
						replaceRootSnapshot({ projectionStatus: 'failed' });
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
						replaceRootSnapshot({ projectionStatus: 'idle' });
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
							}),
						);
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

function projectionIdentityMatchesPackageRevision(
	left: BridgeReviewProjectionRequestIdentity | null,
	right: BridgeReviewProjectionRequestIdentity,
): boolean {
	return (
		left !== null &&
		left.packageId === right.packageId &&
		left.reviewGeneration === right.reviewGeneration &&
		left.revision === right.revision
	);
}
