import type { StoreApi } from 'zustand/vanilla';

import {
	isBridgeCommWorkerDemandEligibleContentMetadata,
	reconcileBridgeCommWorkerDemandMembership,
	serializeBridgeCommWorkerDemandMembership,
} from './bridge-comm-worker-reconciler.js';
import type {
	BridgeCommWorkerRow,
	BridgeCommWorkerStoreState,
	BridgeCommWorkerTouchedResult,
} from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerContentAvailabilityPatchPayload,
	BridgeWorkerContentMetadata,
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerSlicePatch,
} from './bridge-worker-contracts.js';

export interface ApplyBridgeCommWorkerFileViewSourceUpdateFactProps {
	readonly contentItems: readonly BridgeWorkerFileViewContentMetadata[];
	readonly epoch: number;
	readonly pendingSlicePatches: BridgeWorkerSlicePatch[];
	readonly rows: readonly BridgeCommWorkerRow[];
	readonly store: StoreApi<BridgeCommWorkerStoreState>;
}

export function applyBridgeCommWorkerFileViewSourceUpdateFact(
	props: ApplyBridgeCommWorkerFileViewSourceUpdateFactProps,
): BridgeCommWorkerTouchedResult {
	const previousState = props.store.getState();
	const sourceIndexes = buildBridgeCommWorkerFileViewSourceIndexes(props);
	const nextByteCache = new Map(previousState.byteCache);
	const nextPaintReadyByItemId = new Map(previousState.paintReadyByItemId);
	const nextAvailabilityByItemId = new Map(previousState.availabilityByItemId);
	const touchedKeys = new Set<string>([
		'sourceRows',
		'sourceContentMetadata',
		...Array.from(sourceIndexes.contentMetadataByItemId.keys()).map(
			(itemId): string => `contentMetadata:${itemId}`,
		),
	]);
	const selectedFileViewContentMetadataChanged = didSelectedFileViewContentMetadataChange({
		nextContentMetadataByItemId: sourceIndexes.contentMetadataByItemId,
		previousState,
	});
	const nextSlicePatches: BridgeWorkerSlicePatch[] = [];
	const selectedDemandEpoch = selectedDemandEpochForSourceUpdate({
		contentMetadataByItemId: sourceIndexes.contentMetadataByItemId,
		epoch: props.epoch,
		state: previousState,
	});
	const selectedDemandEnabled = selectedDemandEpoch !== null;
	const demandByKey = buildDemandByKey({
		contentMetadataByItemId: sourceIndexes.contentMetadataByItemId,
		selectedId: previousState.selectedId,
		selectedDemandEpoch,
		visibleIds: previousState.visibleIds,
	});

	for (const itemId of sourceRepairCandidateIds(previousState)) {
		const metadata = sourceIndexes.contentMetadataByItemId.get(itemId) ?? null;
		const isDemandEligible = isBridgeCommWorkerDemandEligibleContentMetadata(metadata);
		const isSelectedItem = previousState.selectedId === itemId;
		const isDemandTarget = isSelectedItem || previousState.visibleIds.includes(itemId);
		const previousContentCacheKey = previousState.paintReadyByItemId.get(itemId);
		const keepsReadyPaint =
			previousContentCacheKey !== undefined &&
			isDemandEligible &&
			metadata?.cacheKey === previousContentCacheKey;
		const keepsStaleSelectedPaint =
			previousContentCacheKey !== undefined && metadata === null && isSelectedItem;
		if (previousContentCacheKey !== undefined && !keepsReadyPaint && !keepsStaleSelectedPaint) {
			nextPaintReadyByItemId.delete(itemId);
			nextByteCache.delete(previousContentCacheKey);
			touchedKeys.add(`paintReady:${itemId}`);
			touchedKeys.add(`byteCache:${previousContentCacheKey}`);
			nextSlicePatches.push({
				slice: 'rowPaint',
				operation: 'delete',
				itemId,
			});
		}

		const nextAvailability = nextAvailabilityForFileViewSourceUpdate({
			hasReadyPaint: keepsReadyPaint,
			hasStaleSelectedPaint: keepsStaleSelectedPaint,
			isDemandEligible,
			isDemandTarget,
			previousContentCacheKey,
		});
		if (
			nextAvailability !== null &&
			previousState.availabilityByItemId.get(itemId) !== nextAvailability
		) {
			nextAvailabilityByItemId.set(itemId, nextAvailability);
			touchedKeys.add(`availability:${itemId}`);
			nextSlicePatches.push({
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId,
				payload: { state: nextAvailability },
			});
		}
		if (demandByKey.get(itemId) !== previousState.demandByKey.get(itemId)) {
			touchedKeys.add(`demand:${itemId}`);
		}
	}

	props.store.setState({
		...previousState,
		...sourceIndexes,
		selectedDemandEnabled,
		byteCache: nextByteCache,
		paintReadyByItemId: nextPaintReadyByItemId,
		availabilityByItemId: nextAvailabilityByItemId,
		demandByKey,
	});
	props.pendingSlicePatches.push(...nextSlicePatches);

	return {
		selectedFileViewContentMetadataChanged,
		touchedKeys: [...touchedKeys],
	};
}

function buildBridgeCommWorkerFileViewSourceIndexes(props: {
	readonly contentItems: readonly BridgeWorkerFileViewContentMetadata[];
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

function selectedDemandEpochForSourceUpdate(props: {
	readonly contentMetadataByItemId: ReadonlyMap<string, BridgeWorkerContentMetadata>;
	readonly epoch: number;
	readonly state: BridgeCommWorkerStoreState;
}): number | null {
	if (
		props.state.selectedId === null ||
		!isBridgeCommWorkerDemandEligibleContentMetadata(
			props.contentMetadataByItemId.get(props.state.selectedId) ?? null,
		)
	) {
		return null;
	}
	return props.epoch;
}

function sourceRepairCandidateIds(state: BridgeCommWorkerStoreState): readonly string[] {
	const itemIds = new Set<string>([
		...state.visibleIds,
		...state.paintReadyByItemId.keys(),
		...state.availabilityByItemId.keys(),
	]);
	if (state.selectedId !== null) {
		itemIds.add(state.selectedId);
	}
	return [...itemIds];
}

function nextAvailabilityForFileViewSourceUpdate(props: {
	readonly hasReadyPaint: boolean;
	readonly hasStaleSelectedPaint: boolean;
	readonly isDemandEligible: boolean;
	readonly isDemandTarget: boolean;
	readonly previousContentCacheKey: string | undefined;
}): BridgeWorkerContentAvailabilityPatchPayload['state'] | null {
	if (props.hasReadyPaint) {
		return 'ready';
	}
	if (props.hasStaleSelectedPaint) {
		return 'stale';
	}
	if (
		!props.isDemandEligible &&
		(props.isDemandTarget || props.previousContentCacheKey !== undefined)
	) {
		return 'unavailable';
	}
	if (props.isDemandEligible && props.isDemandTarget) {
		return 'loading';
	}
	return null;
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

function didSelectedFileViewContentMetadataChange(props: {
	readonly nextContentMetadataByItemId: ReadonlyMap<string, BridgeWorkerContentMetadata>;
	readonly previousState: BridgeCommWorkerStoreState;
}): boolean {
	const selectedId = props.previousState.selectedId;
	if (selectedId === null) {
		return false;
	}
	return !areFileViewContentMetadataEquivalent(
		props.previousState.contentMetadataByItemId.get(selectedId) ?? null,
		props.nextContentMetadataByItemId.get(selectedId) ?? null,
	);
}

function areFileViewContentMetadataEquivalent(
	left: BridgeWorkerContentMetadata | null,
	right: BridgeWorkerContentMetadata | null,
): boolean {
	if (left === null || right === null) {
		return left === right;
	}
	if (
		!isBridgeWorkerFileViewContentMetadata(left) ||
		!isBridgeWorkerFileViewContentMetadata(right)
	) {
		return false;
	}
	return (
		left.itemId === right.itemId &&
		left.path === right.path &&
		left.language === right.language &&
		left.cacheKey === right.cacheKey &&
		left.sizeBytes === right.sizeBytes &&
		left.contentHandle === right.contentHandle &&
		left.descriptorId === right.descriptorId &&
		(left.contentHash ?? null) === (right.contentHash ?? null) &&
		left.virtualizedExtentKind === right.virtualizedExtentKind &&
		(left.lineCount ?? null) === (right.lineCount ?? null) &&
		left.isBinary === right.isBinary &&
		left.canFetchContent === right.canFetchContent
	);
}

function isBridgeWorkerFileViewContentMetadata(
	metadata: BridgeWorkerContentMetadata,
): metadata is BridgeWorkerFileViewContentMetadata {
	return 'contentHandle' in metadata;
}
