import { subscribeWithSelector } from 'zustand/middleware';
import { createStore, type Mutate, type StoreApi } from 'zustand/vanilla';

import type {
	BridgeReviewProjectionMode,
	BridgeReviewProjectionRefinement,
	BridgeReviewProjectionRequestIdentity,
	BridgeReviewProjectionResult,
} from '../models/review-projection-models.js';

export type BridgeReviewProjectionStatus = 'idle' | 'running' | 'ready' | 'failed';
export type BridgeReviewWorkerLane = 'sync' | 'worker';
export type BridgeContentHydrationStatusKind = 'idle' | 'queued' | 'loading' | 'ready' | 'failed';

export interface BridgeReviewViewerRootSnapshot {
	readonly selectedItemId: string | null;
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly refinements: readonly BridgeReviewProjectionRefinement[];
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
	readonly setProjectionRefinements: (
		refinements: readonly BridgeReviewProjectionRefinement[],
	) => void;
	readonly startProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity) => void;
	readonly applyProjectionWorkerResult: (props: ApplyProjectionWorkerResultProps) => boolean;
	readonly setWorkerStatus: (status: BridgeReviewWorkerStatus) => void;
	readonly setContentHydrationStatus: (status: BridgeContentHydrationStatus) => void;
}

export interface BridgeReviewViewerStoreState {
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly projection: BridgeReviewProjectionResult | null;
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

const defaultProjectionMode: BridgeReviewProjectionMode = { kind: 'allFiles' };

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
					refinements: [],
					projectionStatus: 'idle',
				},
				projection: null,
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
					setProjectionRefinements: (
						refinements: readonly BridgeReviewProjectionRefinement[],
					): void => {
						replaceRootSnapshot({ refinements });
					},
					startProjectionRequest: (identity: BridgeReviewProjectionRequestIdentity): void => {
						set({
							activeProjectionRequestIdentity: identity,
							projection: null,
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
							workerStatus: {
								...get().workerStatus,
								pendingRequestCount: Math.max(0, get().workerStatus.pendingRequestCount - 1),
								lastCompletedRequestId: props.identity.requestId,
							},
						});
						replaceRootSnapshot({ projectionStatus: 'ready' });
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
