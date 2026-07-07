import { createStore, type StoreApi } from 'zustand/vanilla';

import { applyBridgeCommWorkerFileViewSourceUpdateFact } from './bridge-comm-worker-file-view-source-update.js';
import {
	isBridgeCommWorkerDemandEligibleContentMetadata,
	reconcileBridgeCommWorkerDemandMembership,
	serializeBridgeCommWorkerDemandMembership,
} from './bridge-comm-worker-reconciler.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerSlicePatchEventSchema,
	type BridgeWorkerContentMetadata,
	type BridgeWorkerContentAvailabilityPatchPayload,
	type BridgeWorkerFileViewContentMetadata,
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
	readonly selectedDemandEnabled: boolean;
	readonly viewportRange: BridgeCommWorkerViewportRange | null;
	readonly visibleIds: readonly string[];
	readonly demandByKey: ReadonlyMap<string, string>;
	readonly byteCache: ReadonlyMap<string, string>;
	readonly paintReadyByItemId: ReadonlyMap<string, string>;
	readonly availabilityByItemId: ReadonlyMap<
		string,
		BridgeWorkerContentAvailabilityPatchPayload['state']
	>;
	readonly contentMetadataByItemId: ReadonlyMap<string, BridgeWorkerContentMetadata>;
}

export interface CreateBridgeCommWorkerStoreProps {
	readonly contentItems: readonly BridgeWorkerContentMetadata[];
	readonly rows: readonly BridgeCommWorkerRow[];
}

export interface BridgeCommWorkerTouchedResult {
	readonly selectedFileViewContentMetadataChanged?: boolean;
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

type BridgeCommWorkerTerminalContentAvailabilityState = Extract<
	BridgeWorkerContentAvailabilityPatchPayload['state'],
	'failed' | 'unavailable'
>;

export interface ApplyBridgeCommWorkerContentTerminalAvailabilityProps {
	readonly itemId: string;
	readonly state: BridgeCommWorkerTerminalContentAvailabilityState;
}

export interface ApplyBridgeCommWorkerReviewInvalidationFactProps {
	readonly epoch: number;
	readonly scope: 'package' | 'items' | 'paths' | 'treeWindow';
	readonly itemIds: readonly string[];
	readonly pathHints: readonly string[];
	readonly reason: 'sourceChanged' | 'watchEvent' | 'lineageReplaced' | 'unknown';
}

export interface ApplyBridgeCommWorkerReviewSourceUpdateFactProps {
	readonly contentItems: readonly BridgeWorkerReviewContentMetadata[];
	readonly rows: readonly BridgeCommWorkerRow[];
}

export interface ApplyBridgeCommWorkerFileViewSourceUpdateFactProps {
	readonly contentItems: readonly BridgeWorkerFileViewContentMetadata[];
	readonly epoch: number;
	readonly rows: readonly BridgeCommWorkerRow[];
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
		readonly applyContentTerminalAvailability: (
			props: ApplyBridgeCommWorkerContentTerminalAvailabilityProps,
		) => BridgeCommWorkerTouchedResult;
		readonly applyReviewInvalidationFact: (
			props: ApplyBridgeCommWorkerReviewInvalidationFactProps,
		) => BridgeCommWorkerTouchedResult;
		readonly applyReviewSourceUpdateFact: (
			props: ApplyBridgeCommWorkerReviewSourceUpdateFactProps,
		) => BridgeCommWorkerTouchedResult;
		readonly applyFileViewSourceUpdateFact: (
			props: ApplyBridgeCommWorkerFileViewSourceUpdateFactProps,
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
				const isDemandEligible = isBridgeCommWorkerDemandEligibleContentMetadata(contentMetadata);
				const selectedDemandEnabled = isDemandEligible;
				const nextAvailabilityState = selectedDemandEnabled ? 'loading' : 'unavailable';
				store.setState((state) => {
					const selectedState = {
						...state,
						selectedDemandEnabled,
						selectedId: fact.itemId,
						demandByKey: buildDemandByKey({
							contentMetadataByItemId: state.contentMetadataByItemId,
							selectedId: fact.itemId,
							selectedDemandEpoch: selectedDemandEnabled ? fact.epoch : null,
							visibleIds: state.visibleIds,
						}),
					};
					return nextAvailabilityState === null
						? selectedState
						: writeBridgeWorkerMap(
								selectedState,
								'availabilityByItemId',
								fact.itemId,
								nextAvailabilityState,
							);
				});
				pendingSlicePatches.push({
					slice: 'selection',
					operation: 'upsert',
					payload: { selectedItemId: fact.itemId },
				});
				if (nextAvailabilityState !== null) {
					pendingSlicePatches.push({
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: fact.itemId,
						payload: { state: nextAvailabilityState },
					});
				}
				return {
					touchedKeys: [
						'selectedId',
						...(nextAvailabilityState === null
							? []
							: [
									`rowPaint:${fact.itemId}`,
									`availability:${fact.itemId}`,
									`contentMetadata:${fact.itemId}`,
								]),
						...(selectedDemandEnabled ? [`demand:${fact.itemId}`] : []),
					],
				};
			},
			applyViewportFact: (
				fact: ApplyBridgeCommWorkerViewportFactProps,
			): BridgeCommWorkerTouchedResult => {
				const previousState = store.getState();
				const visibleIds = [...fact.visibleItemIds];
				const visibleDeltaIds = findChangedIds(previousState.visibleIds, visibleIds);
				const unavailableVisibleIds = visibleIds.filter((itemId) => {
					const metadata = previousState.contentMetadataByItemId.get(itemId) ?? null;
					return (
						metadata !== null &&
						!isBridgeCommWorkerDemandEligibleContentMetadata(metadata) &&
						previousState.availabilityByItemId.get(itemId) !== 'unavailable'
					);
				});
				let nextAvailabilityByItemId = previousState.availabilityByItemId;
				if (unavailableVisibleIds.length > 0) {
					const unavailableAvailabilityByItemId = new Map(previousState.availabilityByItemId);
					for (const itemId of unavailableVisibleIds) {
						unavailableAvailabilityByItemId.set(itemId, 'unavailable');
					}
					nextAvailabilityByItemId = unavailableAvailabilityByItemId;
				}
				store.setState((state) => ({
					...state,
					viewportRange: {
						firstVisibleIndex: fact.firstVisibleIndex,
						lastVisibleIndex: fact.lastVisibleIndex,
					},
					visibleIds,
					availabilityByItemId: nextAvailabilityByItemId,
					demandByKey: buildDemandByKey({
						contentMetadataByItemId: state.contentMetadataByItemId,
						selectedId: state.selectedId,
						selectedDemandEpoch: readSelectedDemandEpoch(state),
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
				for (const itemId of unavailableVisibleIds) {
					pendingSlicePatches.push({
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId,
						payload: { state: 'unavailable' },
					});
				}
				return {
					touchedKeys: [
						'viewportRange',
						...visibleDeltaIds.map((itemId) => `visibleIds:${itemId}`),
						...visibleDeltaIds.map((itemId) => `demand:${itemId}`),
						...unavailableVisibleIds.map((itemId) => `availability:${itemId}`),
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
			applyContentTerminalAvailability: (
				fact: ApplyBridgeCommWorkerContentTerminalAvailabilityProps,
			): BridgeCommWorkerTouchedResult => {
				const previousState = store.getState();
				const previousContentCacheKey = previousState.paintReadyByItemId.get(fact.itemId);
				const nextByteCache = new Map(previousState.byteCache);
				const nextPaintReadyByItemId = new Map(previousState.paintReadyByItemId);
				const touchedKeys: string[] = [];
				if (previousContentCacheKey !== undefined) {
					nextPaintReadyByItemId.delete(fact.itemId);
					nextByteCache.delete(previousContentCacheKey);
					touchedKeys.push(`paintReady:${fact.itemId}`, `byteCache:${previousContentCacheKey}`);
					pendingSlicePatches.push({
						slice: 'rowPaint',
						operation: 'delete',
						itemId: fact.itemId,
					});
				}
				const nextAvailabilityByItemId = new Map(previousState.availabilityByItemId);
				nextAvailabilityByItemId.set(fact.itemId, fact.state);
				store.setState({
					...previousState,
					byteCache: nextByteCache,
					paintReadyByItemId: nextPaintReadyByItemId,
					availabilityByItemId: nextAvailabilityByItemId,
				});
				pendingSlicePatches.push({
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: fact.itemId,
					payload: { state: fact.state },
				});
				return {
					touchedKeys: [...touchedKeys, `availability:${fact.itemId}`],
				};
			},
			applyReviewInvalidationFact: (
				fact: ApplyBridgeCommWorkerReviewInvalidationFactProps,
			): BridgeCommWorkerTouchedResult => {
				const previousState = store.getState();
				const invalidatedItemIds = resolveReviewInvalidationItemIds({
					fact,
					state: previousState,
				});
				const invalidatedItemIdSet = new Set(invalidatedItemIds);
				const nextByteCache = new Map(previousState.byteCache);
				const nextPaintReadyByItemId = new Map(previousState.paintReadyByItemId);
				const nextAvailabilityByItemId = new Map(previousState.availabilityByItemId);
				const touchedKeys: string[] = [];
				const nextPatches: BridgeWorkerSlicePatch[] = [];

				for (const itemId of invalidatedItemIds) {
					const previousContentCacheKey = previousState.paintReadyByItemId.get(itemId);
					if (previousContentCacheKey !== undefined) {
						nextPaintReadyByItemId.delete(itemId);
						nextByteCache.delete(previousContentCacheKey);
						touchedKeys.push(`paintReady:${itemId}`, `byteCache:${previousContentCacheKey}`);
						nextPatches.push({
							slice: 'rowPaint',
							operation: 'delete',
							itemId,
						});
					}
					if (
						previousContentCacheKey !== undefined ||
						previousState.availabilityByItemId.has(itemId) ||
						previousState.selectedId === itemId ||
						previousState.visibleIds.includes(itemId)
					) {
						nextAvailabilityByItemId.set(itemId, 'stale');
						touchedKeys.push(`availability:${itemId}`);
						nextPatches.push({
							slice: 'contentAvailability',
							operation: 'upsert',
							itemId,
							payload: { state: 'stale' },
						});
					}
					if (previousState.selectedId === itemId || previousState.visibleIds.includes(itemId)) {
						touchedKeys.push(`demand:${itemId}`);
					}
				}

				const selectedDemandEpoch =
					previousState.selectedId !== null && invalidatedItemIdSet.has(previousState.selectedId)
						? fact.epoch
						: readSelectedDemandEpoch(previousState);
				store.setState({
					...previousState,
					byteCache: nextByteCache,
					paintReadyByItemId: nextPaintReadyByItemId,
					availabilityByItemId: nextAvailabilityByItemId,
					demandByKey: buildDemandByKey({
						contentMetadataByItemId: previousState.contentMetadataByItemId,
						selectedId: previousState.selectedId,
						selectedDemandEpoch,
						visibleIds: previousState.visibleIds,
					}),
				});
				pendingSlicePatches.push(...nextPatches);
				return { touchedKeys };
			},
			applyReviewSourceUpdateFact: (
				fact: ApplyBridgeCommWorkerReviewSourceUpdateFactProps,
			): BridgeCommWorkerTouchedResult => {
				return applyBridgeCommWorkerSourceUpdateFact({
					contentItems: fact.contentItems,
					rows: fact.rows,
					store,
				});
			},
			applyFileViewSourceUpdateFact: (
				fact: ApplyBridgeCommWorkerFileViewSourceUpdateFactProps,
			): BridgeCommWorkerTouchedResult => {
				return applyBridgeCommWorkerFileViewSourceUpdateFact({
					contentItems: fact.contentItems,
					epoch: fact.epoch,
					pendingSlicePatches,
					rows: fact.rows,
					store,
				});
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

function applyBridgeCommWorkerSourceUpdateFact(props: {
	readonly contentItems: readonly BridgeWorkerContentMetadata[];
	readonly rows: readonly BridgeCommWorkerRow[];
	readonly store: StoreApi<BridgeCommWorkerStoreState>;
}): BridgeCommWorkerTouchedResult {
	const previousState = props.store.getState();
	const sourceIndexes = buildBridgeCommWorkerSourceIndexes(props);
	props.store.setState({
		...previousState,
		...sourceIndexes,
		demandByKey: buildDemandByKey({
			contentMetadataByItemId: sourceIndexes.contentMetadataByItemId,
			selectedId: previousState.selectedId,
			selectedDemandEpoch: readSelectedDemandEpoch(previousState),
			visibleIds: previousState.visibleIds,
		}),
	});
	return {
		touchedKeys: [
			'sourceRows',
			'sourceContentMetadata',
			...Array.from(sourceIndexes.contentMetadataByItemId.keys()).map(
				(itemId): string => `contentMetadata:${itemId}`,
			),
		],
	};
}

function buildInitialBridgeCommWorkerStoreState(
	props: CreateBridgeCommWorkerStoreProps,
): BridgeCommWorkerStoreState {
	const sourceIndexes = buildBridgeCommWorkerSourceIndexes(props);
	return {
		...sourceIndexes,
		selectedId: null,
		selectedDemandEnabled: false,
		viewportRange: null,
		visibleIds: [],
		demandByKey: new Map<string, string>(),
		byteCache: new Map<string, string>(),
		paintReadyByItemId: new Map<string, string>(),
		availabilityByItemId: new Map<string, BridgeWorkerContentAvailabilityPatchPayload['state']>(),
	};
}

function buildBridgeCommWorkerSourceIndexes(props: {
	readonly contentItems: readonly BridgeWorkerContentMetadata[];
	readonly rows: readonly BridgeCommWorkerRow[];
}): Pick<
	BridgeCommWorkerStoreState,
	'rowById' | 'orderedIds' | 'indexById' | 'childrenByParentId' | 'contentMetadataByItemId'
> {
	const rowById = new Map<string, BridgeCommWorkerRow>();
	const indexById = new Map<string, number>();
	const childrenByParentId = new Map<string, readonly string[]>();
	const contentMetadataByItemId = new Map<string, BridgeWorkerContentMetadata>();
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
		contentMetadataByItemId,
	};
}

function resolveReviewInvalidationItemIds(props: {
	readonly fact: ApplyBridgeCommWorkerReviewInvalidationFactProps;
	readonly state: BridgeCommWorkerStoreState;
}): readonly string[] {
	const itemIds = new Set<string>();
	if (props.fact.scope === 'package' || props.fact.scope === 'treeWindow') {
		for (const itemId of props.state.paintReadyByItemId.keys()) {
			itemIds.add(itemId);
		}
		if (props.state.selectedId !== null) {
			itemIds.add(props.state.selectedId);
		}
		for (const itemId of props.state.visibleIds) {
			itemIds.add(itemId);
		}
	} else {
		for (const itemId of props.fact.itemIds) {
			itemIds.add(itemId);
		}
	}
	for (const pathHint of props.fact.pathHints) {
		for (const metadata of props.state.contentMetadataByItemId.values()) {
			if (metadata.path === pathHint) {
				itemIds.add(metadata.itemId);
			}
		}
	}
	return [...itemIds];
}

function buildDemandByKey(props: {
	readonly contentMetadataByItemId: ReadonlyMap<string, BridgeWorkerContentMetadata>;
	readonly selectedId: string | null;
	readonly selectedDemandEpoch: number | null;
	readonly visibleIds: readonly string[];
}): ReadonlyMap<string, string> {
	return serializeBridgeCommWorkerDemandMembership(
		reconcileBridgeCommWorkerDemandMembership(props),
	);
}

function readSelectedDemandEpoch(state: BridgeCommWorkerStoreState): number | null {
	if (state.selectedId === null) {
		return null;
	}
	const existingValue = state.demandByKey.get(state.selectedId);
	const selectedEpochMatch = /^selected:(\d+)$/u.exec(existingValue ?? '');
	if (selectedEpochMatch !== null) {
		return Number(selectedEpochMatch[1]);
	}
	return null;
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
