import type {
	BridgeContentHandle,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from './bridge-review-package.js';

export function orderedReviewItems(
	reviewPackage: BridgeReviewPackage,
): readonly BridgeReviewItemDescriptor[] {
	return reviewPackage.orderedItemIds
		.map(
			(itemId: string): BridgeReviewItemDescriptor | undefined => reviewPackage.itemsById[itemId],
		)
		.filter((item: BridgeReviewItemDescriptor | undefined): item is BridgeReviewItemDescriptor =>
			Boolean(item),
		);
}

export function contentHandlesForItem(
	item: BridgeReviewItemDescriptor,
): readonly BridgeContentHandle[] {
	return [
		item.contentRoles.base,
		item.contentRoles.head,
		item.contentRoles.diff,
		item.contentRoles.file,
	].filter((handle: BridgeContentHandle | null): handle is BridgeContentHandle => handle !== null);
}
