import type {
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';

export function makeReviewItemContentResourcesKey(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly reviewPackage: BridgeReviewPackage;
}): string {
	// Content-addressed content-validity key. reviewGeneration is the staleness authority and
	// per-role contentHash carries per-file freshness across revisions. This deliberately EXCLUDES
	// revision, itemVersion, and the revision-stamped item/role cacheKeys: benign metadata
	// re-delivery (extent facts, path/summary/tree updates that bump revision but not content) must
	// NOT churn this key, or it would drop already-loaded content and re-arm the loading placeholder.
	// A genuine contentHash change, a role losing its descriptor ('none'), or a generation rotation
	// still changes the key and correctly invalidates.
	const roleContentHashes = [
		props.item.contentRoles.base,
		props.item.contentRoles.head,
		props.item.contentRoles.diff,
		props.item.contentRoles.file,
	]
		.map((handle): string => handle?.contentHash ?? 'none')
		.join('|');
	return [
		props.reviewPackage.packageId,
		String(props.reviewPackage.reviewGeneration),
		props.item.itemId,
		roleContentHashes,
	].join(':');
}

export function makeVisibleReviewItemContentResourcesKey(props: {
	readonly contentInvalidationVersion: number;
	readonly item: BridgeReviewItemDescriptor;
	readonly reviewPackage: BridgeReviewPackage;
}): string {
	return [
		makeReviewItemContentResourcesKey({
			item: props.item,
			reviewPackage: props.reviewPackage,
		}),
		'visibleInvalidation',
		String(props.contentInvalidationVersion),
	].join(':');
}

export function normalizeVisibleReviewItemIds(props: {
	readonly itemIds: readonly string[];
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
}): readonly string[] {
	if (props.reviewPackage === null) {
		return [];
	}
	const normalizedItemIds: string[] = [];
	normalizedItemIds.push(
		...selectedReviewItemNeighborhood(props.reviewPackage, props.selectedItemId),
	);
	normalizedItemIds.push(...props.itemIds);
	const uniqueItemIds: string[] = [];
	const seenItemIds = new Set<string>();
	for (const itemId of normalizedItemIds) {
		if (
			itemId === props.selectedItemId ||
			seenItemIds.has(itemId) ||
			props.reviewPackage.itemsById[itemId] === undefined
		) {
			continue;
		}
		seenItemIds.add(itemId);
		uniqueItemIds.push(itemId);
	}
	return uniqueItemIds;
}

export function selectedAdjacentReviewItemIds(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedItemId: string | null;
}): readonly string[] {
	return selectedReviewItemNeighborhood(props.reviewPackage, props.selectedItemId).filter(
		(itemId): boolean => itemId !== props.selectedItemId,
	);
}

function selectedReviewItemNeighborhood(
	reviewPackage: BridgeReviewPackage,
	selectedItemId: string | null,
): readonly string[] {
	if (selectedItemId === null) {
		return [];
	}
	const selectedIndex = reviewPackage.orderedItemIds.indexOf(selectedItemId);
	if (selectedIndex < 0) {
		return [selectedItemId];
	}
	return reviewPackage.orderedItemIds.slice(
		Math.max(0, selectedIndex - 2),
		Math.min(reviewPackage.orderedItemIds.length, selectedIndex + 3),
	);
}
