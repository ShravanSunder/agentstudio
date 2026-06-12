import type {
	BridgeReviewGroup,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from './bridge-review-package.js';

export interface BridgeReviewDeltaOperations {
	readonly addItems: readonly BridgeReviewItemDescriptor[];
	readonly updateItems: readonly BridgeReviewItemDescriptor[];
	readonly removeItems: readonly string[];
	readonly moveItems: readonly string[];
	readonly updateGroups: readonly BridgeReviewGroup[] | null;
	readonly updateSummary: BridgeReviewPackage['summary'] | null;
	readonly invalidateContent: readonly string[];
}

export interface BridgeReviewDelta {
	readonly packageId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
	readonly operations: BridgeReviewDeltaOperations;
}

export function applyBridgeReviewDelta(
	reviewPackage: BridgeReviewPackage,
	delta: BridgeReviewDelta,
): BridgeReviewPackage {
	if (reviewPackage.packageId !== delta.packageId) {
		return reviewPackage;
	}
	if (reviewPackage.reviewGeneration !== delta.reviewGeneration) {
		return reviewPackage;
	}

	const removedItemIds = new Set(delta.operations.removeItems);
	const addedOrUpdatedItems = [...delta.operations.addItems, ...delta.operations.updateItems];
	const itemsById: Record<string, BridgeReviewItemDescriptor> = {};

	for (const [itemId, item] of Object.entries(reviewPackage.itemsById)) {
		if (!removedItemIds.has(itemId)) {
			itemsById[itemId] = item;
		}
	}
	for (const item of addedOrUpdatedItems) {
		itemsById[item.itemId] = item;
	}

	const orderedItemIds = reviewPackage.orderedItemIds.filter(
		(itemId: string): boolean => !removedItemIds.has(itemId),
	);
	for (const item of delta.operations.addItems) {
		if (!orderedItemIds.includes(item.itemId)) {
			orderedItemIds.push(item.itemId);
		}
	}
	const movedItemIds =
		delta.operations.moveItems.length > 0
			? delta.operations.moveItems.filter((itemId: string): boolean => itemId in itemsById)
			: orderedItemIds;
	const movedItemIdSet = new Set(movedItemIds);
	const nextOrderedItemIds = [
		...movedItemIds,
		...orderedItemIds.filter((itemId: string): boolean => !movedItemIdSet.has(itemId)),
	];

	return {
		...reviewPackage,
		revision: delta.revision,
		orderedItemIds: nextOrderedItemIds,
		itemsById,
		groups: delta.operations.updateGroups ?? reviewPackage.groups,
		summary: delta.operations.updateSummary ?? reviewPackage.summary,
	};
}
