import { createStore, type StoreApi } from 'zustand/vanilla';

import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerSlicePatchEventSchema,
	type BridgeWorkerContentAvailabilityPatchPayload,
	type BridgeWorkerReviewContentMetadata,
	type BridgeWorkerSlicePatch,
	type BridgeWorkerSlicePatchEvent,
} from './bridge-worker-contracts.js';

export interface BridgeCommWorkerRow {
	readonly id: string;
	readonly parentId: string | null;
	readonly index: number;
}

export interface BridgeCommWorkerViewportRange {
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
}

export interface BridgeCommWorkerStoreState {
	readonly rowById: ReadonlyMap<string, BridgeCommWorkerRow>;
	readonly orderedIds: readonly string[];
	readonly indexById: ReadonlyMap<string, number>;
	readonly childrenByParentId: ReadonlyMap<string, readonly string[]>;
	readonly selectedId: string | null;
	readonly viewportRange: BridgeCommWorkerViewportRange | null;
	readonly visibleIds: readonly string[];
	readonly demandByKey: ReadonlyMap<string, string>;
	readonly byteCache: ReadonlyMap<string, string>;
	readonly paintReadyByItemId: ReadonlyMap<string, string>;
	readonly availabilityByItemId: ReadonlyMap<
		string,
		BridgeWorkerContentAvailabilityPatchPayload['state']
	>;
	readonly contentMetadataByItemId: ReadonlyMap<string, BridgeWorkerReviewContentMetadata>;
}

export interface CreateBridgeCommWorkerStoreProps {
	readonly contentItems: readonly BridgeWorkerReviewContentMetadata[];
	readonly rows: readonly BridgeCommWorkerRow[];
}

export interface BridgeCommWorkerTouchedResult {
	readonly touchedKeys: readonly string[];
}

export interface ApplyBridgeCommWorkerSelectedFactProps {
	readonly itemId: string;
	readonly epoch: number;
}

export interface ApplyBridgeCommWorkerViewportFactProps {
	readonly visibleItemIds: readonly string[];
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
}

export interface ApplyBridgeCommWorkerContentReadyProps {
	readonly itemId: string;
	readonly contentCacheKey: string;
}

export interface TakePendingBridgeCommWorkerSlicePatchEventProps {
	readonly epoch: number;
	readonly sequence: number;
}

export interface BridgeCommWorkerStore {
	readonly getState: () => BridgeCommWorkerStoreState;
	readonly subscribe: StoreApi<BridgeCommWorkerStoreState>['subscribe'];
	readonly actions: {
		readonly applySelectedFact: (
			props: ApplyBridgeCommWorkerSelectedFactProps,
		) => BridgeCommWorkerTouchedResult;
		readonly applyViewportFact: (
			props: ApplyBridgeCommWorkerViewportFactProps,
		) => BridgeCommWorkerTouchedResult;
		readonly applyContentReady: (
			props: ApplyBridgeCommWorkerContentReadyProps,
		) => BridgeCommWorkerTouchedResult;
		readonly takePendingSlicePatchEvent: (
			props: TakePendingBridgeCommWorkerSlicePatchEventProps,
		) => BridgeWorkerSlicePatchEvent | null;
		readonly buildRootSnapshotPayload: () => never;
	};
}

export function createBridgeCommWorkerStore(
	props: CreateBridgeCommWorkerStoreProps,
): BridgeCommWorkerStore {
	const store = createStore<BridgeCommWorkerStoreState>(() =>
		buildInitialBridgeCommWorkerStoreState(props),
	);
	const pendingSlicePatches: BridgeWorkerSlicePatch[] = [];

	return {
		getState: store.getState,
		subscribe: store.subscribe,
		actions: {
			applySelectedFact: (
				fact: ApplyBridgeCommWorkerSelectedFactProps,
			): BridgeCommWorkerTouchedResult => {
				const contentMetadata = store.getState().contentMetadataByItemId.get(fact.itemId) ?? null;
				const isDemandEligible = isDemandEligibleContentMetadata(contentMetadata);
				const nextAvailabilityState = isDemandEligible ? 'loading' : 'unavailable';
				store.setState((state) => ({
					...writeBridgeWorkerMap(
						state,
						'availabilityByItemId',
						fact.itemId,
						nextAvailabilityState,
					),
					selectedId: fact.itemId,
					demandByKey: buildDemandByKey({
						contentMetadataByItemId: state.contentMetadataByItemId,
						selectedId: fact.itemId,
						selectedDemandValue: `selected:${fact.epoch}`,
						visibleIds: state.visibleIds,
					}),
				}));
				pendingSlicePatches.push(
					{
						slice: 'selection',
						operation: 'upsert',
						payload: { selectedItemId: fact.itemId },
					},
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: fact.itemId,
						payload: { state: nextAvailabilityState },
					},
				);
				return {
					touchedKeys: [
						'selectedId',
						`rowPaint:${fact.itemId}`,
						`availability:${fact.itemId}`,
						`contentMetadata:${fact.itemId}`,
						`demand:${fact.itemId}`,
					],
				};
			},
			applyViewportFact: (
				fact: ApplyBridgeCommWorkerViewportFactProps,
			): BridgeCommWorkerTouchedResult => {
				const previousState = store.getState();
				const visibleIds = [...fact.visibleItemIds];
				const visibleDeltaIds = findChangedIds(previousState.visibleIds, visibleIds);
				store.setState((state) => ({
					...state,
					viewportRange: {
						firstVisibleIndex: fact.firstVisibleIndex,
						lastVisibleIndex: fact.lastVisibleIndex,
					},
					visibleIds,
					demandByKey: buildDemandByKey({
						contentMetadataByItemId: state.contentMetadataByItemId,
						selectedId: state.selectedId,
						selectedDemandValue: readSelectedDemandValue(state),
						visibleIds,
					}),
				}));
				pendingSlicePatches.push({
					slice: 'viewport',
					operation: 'upsert',
					payload: {
						firstVisibleIndex: fact.firstVisibleIndex,
						lastVisibleIndex: fact.lastVisibleIndex,
						visibleItemIds: visibleIds,
					},
				});
				return {
					touchedKeys: [
						'viewportRange',
						...visibleDeltaIds.map((itemId) => `visibleIds:${itemId}`),
						...visibleDeltaIds.map((itemId) => `demand:${itemId}`),
					],
				};
			},
			applyContentReady: (
				fact: ApplyBridgeCommWorkerContentReadyProps,
			): BridgeCommWorkerTouchedResult => {
				store.setState((state) => ({
					...writeBridgeWorkerMap(
						writeBridgeWorkerMap(
							writeBridgeWorkerMap(state, 'byteCache', fact.contentCacheKey, fact.itemId),
							'paintReadyByItemId',
							fact.itemId,
							fact.contentCacheKey,
						),
						'availabilityByItemId',
						fact.itemId,
						'ready',
					),
				}));
				pendingSlicePatches.push(
					{
						slice: 'rowPaint',
						operation: 'upsert',
						itemId: fact.itemId,
						payload: { contentCacheKey: fact.contentCacheKey },
					},
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: fact.itemId,
						payload: { state: 'ready' },
					},
				);
				return {
					touchedKeys: [
						`byteCache:${fact.contentCacheKey}`,
						`paintReady:${fact.itemId}`,
						`availability:${fact.itemId}`,
					],
				};
			},
			takePendingSlicePatchEvent: (
				eventProps: TakePendingBridgeCommWorkerSlicePatchEventProps,
			): BridgeWorkerSlicePatchEvent | null => {
				if (pendingSlicePatches.length === 0) {
					return null;
				}
				const patches = pendingSlicePatches.splice(0, pendingSlicePatches.length);
				return bridgeWorkerSlicePatchEventSchema.parse({
					wireVersion: BRIDGE_WORKER_WIRE_VERSION,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'slicePatch',
					epoch: eventProps.epoch,
					sequence: eventProps.sequence,
					patches,
				});
			},
			buildRootSnapshotPayload: (): never => {
				throw new Error('Bridge comm worker root snapshots are forbidden across the boundary.');
			},
		},
	};
}

function buildInitialBridgeCommWorkerStoreState(
	props: CreateBridgeCommWorkerStoreProps,
): BridgeCommWorkerStoreState {
	const rowById = new Map<string, BridgeCommWorkerRow>();
	const indexById = new Map<string, number>();
	const childrenByParentId = new Map<string, readonly string[]>();
	const contentMetadataByItemId = new Map<string, BridgeWorkerReviewContentMetadata>();
	for (const row of props.rows) {
		rowById.set(row.id, row);
		indexById.set(row.id, row.index);
		if (row.parentId !== null) {
			childrenByParentId.set(row.parentId, [
				...(childrenByParentId.get(row.parentId) ?? []),
				row.id,
			]);
		}
	}
	for (const contentItem of props.contentItems) {
		contentMetadataByItemId.set(contentItem.itemId, contentItem);
	}
	return {
		rowById,
		orderedIds: props.rows.map((row) => row.id),
		indexById,
		childrenByParentId,
		selectedId: null,
		viewportRange: null,
		visibleIds: [],
		demandByKey: new Map<string, string>(),
		byteCache: new Map<string, string>(),
		paintReadyByItemId: new Map<string, string>(),
		availabilityByItemId: new Map<string, BridgeWorkerContentAvailabilityPatchPayload['state']>(),
		contentMetadataByItemId,
	};
}

function buildDemandByKey(props: {
	readonly contentMetadataByItemId: ReadonlyMap<string, BridgeWorkerReviewContentMetadata>;
	readonly selectedId: string | null;
	readonly selectedDemandValue: string | null;
	readonly visibleIds: readonly string[];
}): ReadonlyMap<string, string> {
	const demandByKey = new Map<string, string>();
	for (const itemId of props.visibleIds) {
		if (isDemandEligibleContentMetadata(props.contentMetadataByItemId.get(itemId) ?? null)) {
			demandByKey.set(itemId, 'visible');
		}
	}
	if (
		props.selectedId !== null &&
		isDemandEligibleContentMetadata(props.contentMetadataByItemId.get(props.selectedId) ?? null)
	) {
		demandByKey.set(props.selectedId, props.selectedDemandValue ?? 'selected');
	}
	return demandByKey;
}

function isDemandEligibleContentMetadata(
	metadata: BridgeWorkerReviewContentMetadata | null,
): boolean {
	return metadata !== null && metadata.availableContentRoles.length > 0;
}

function readSelectedDemandValue(state: BridgeCommWorkerStoreState): string | null {
	if (state.selectedId === null) {
		return null;
	}
	const existingValue = state.demandByKey.get(state.selectedId);
	if (existingValue?.startsWith('selected:') === true) {
		return existingValue;
	}
	return 'selected';
}

type BridgeCommWorkerStringMapKey =
	| 'demandByKey'
	| 'byteCache'
	| 'paintReadyByItemId'
	| 'availabilityByItemId';

function writeBridgeWorkerMap(
	state: BridgeCommWorkerStoreState,
	key: BridgeCommWorkerStringMapKey,
	entryKey: string,
	value: string,
): BridgeCommWorkerStoreState {
	const target = state[key];
	if (!(target instanceof Map)) {
		throw new Error(`Bridge comm worker state ${key} is not a map.`);
	}
	target.set(entryKey, value);
	return state;
}

function findChangedIds(
	previousIds: readonly string[],
	nextIds: readonly string[],
): readonly string[] {
	const previousIdSet = new Set(previousIds);
	const nextIdSet = new Set(nextIds);
	return [
		...previousIds.filter((itemId) => !nextIdSet.has(itemId)),
		...nextIds.filter((itemId) => !previousIdSet.has(itemId)),
	];
}
