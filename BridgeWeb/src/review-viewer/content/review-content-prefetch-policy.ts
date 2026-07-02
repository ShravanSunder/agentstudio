import type {
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import { contentAddressedResourceKey } from './review-content-registry.js';

/** Upper bound on items warmed per package: prefetch is a smoothness
 * optimization, not a completeness guarantee, and this bounds worst-case
 * memory alongside the registry entry cap. */
export const reviewContentPrefetchMaxItemsPerPackage = 512;

/** Registry capacity for review runtimes that prefetch: must fit the
 * prefetch budget (items x up to two content roles) plus visible/selected
 * churn headroom, or prefetched entries evict each other. */
export const reviewContentRegistryPrefetchMaxEntries = 2048;

/** One in-flight prefetch load at a time: speculative work must never
 * contend with selected/visible demand for executor slots. */
export const reviewContentPrefetchMaxConcurrentLoads = 1;

export interface ReviewContentPrefetchCandidateProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedItemId: string | null;
	readonly cachedResourceKeys: ReadonlySet<string>;
	readonly excludedItemIds: ReadonlySet<string>;
	readonly maxItems?: number;
}

export interface ReviewContentPrefetchGateProps {
	readonly isActive: boolean;
	readonly isCodeViewScrollActive: boolean;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedContentLoading: boolean;
	readonly visibleLoadingItemCount: number;
}

/** Prefetch only fills genuinely idle time: any active scroll, selected
 * load, or visible hydration wins the executor and pauses the pump. */
export function shouldRunReviewContentPrefetch(props: ReviewContentPrefetchGateProps): boolean {
	return (
		props.isActive &&
		props.reviewPackage !== null &&
		!props.isCodeViewScrollActive &&
		!props.selectedContentLoading &&
		props.visibleLoadingItemCount === 0
	);
}

/** Ring order outward from the selected item (next, previous, next+1,
 * previous-1, ...): proximity in review order approximates the user's next
 * selection. Items already fully cached or explicitly excluded are skipped. */
export function reviewContentPrefetchCandidateItemIds(
	props: ReviewContentPrefetchCandidateProps,
): readonly string[] {
	const orderedItemIds = props.reviewPackage.orderedItemIds;
	const maxItems = props.maxItems ?? reviewContentPrefetchMaxItemsPerPackage;
	if (orderedItemIds.length === 0 || maxItems <= 0) {
		return [];
	}
	const selectedIndex =
		props.selectedItemId === null ? -1 : orderedItemIds.indexOf(props.selectedItemId);
	const candidateItemIds: string[] = [];
	for (const itemId of ringOrderedItemIds(orderedItemIds, selectedIndex)) {
		if (candidateItemIds.length >= maxItems) {
			break;
		}
		if (props.excludedItemIds.has(itemId)) {
			continue;
		}
		const item = props.reviewPackage.itemsById[itemId];
		if (item === undefined || isItemFullyCached(item, props.cachedResourceKeys)) {
			continue;
		}
		candidateItemIds.push(itemId);
	}
	return candidateItemIds;
}

function ringOrderedItemIds(orderedItemIds: readonly string[], selectedIndex: number): string[] {
	if (selectedIndex < 0) {
		return [...orderedItemIds];
	}
	const ring: string[] = [];
	for (let distance = 1; distance < orderedItemIds.length; distance += 1) {
		const nextItemId = orderedItemIds[selectedIndex + distance];
		if (nextItemId !== undefined) {
			ring.push(nextItemId);
		}
		const previousItemId = orderedItemIds[selectedIndex - distance];
		if (previousItemId !== undefined) {
			ring.push(previousItemId);
		}
	}
	return ring;
}

/** An item is a prefetch candidate only while it has at least one cacheable
 * (non-sentinel) handle missing from the cache. Sentinel-hash handles can
 * never be cached, so items with none cacheable are skipped outright —
 * otherwise the pump would reload them forever without converging. */
function isItemFullyCached(
	item: BridgeReviewItemDescriptor,
	cachedResourceKeys: ReadonlySet<string>,
): boolean {
	for (const handle of Object.values(item.contentRoles)) {
		if (handle === null || handle === undefined) {
			continue;
		}
		const resourceKey = contentAddressedResourceKey(handle);
		if (resourceKey === null) {
			continue;
		}
		if (!cachedResourceKeys.has(resourceKey)) {
			return false;
		}
	}
	return true;
}
