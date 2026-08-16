import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerReviewInvalidateCommand,
} from './bridge-worker-contracts.js';

export function isBridgeWorkerReviewContentMetadata(
	metadata: BridgeWorkerReviewContentMetadata | BridgeWorkerFileViewContentMetadata | null,
): metadata is BridgeWorkerReviewContentMetadata {
	return metadata !== null && 'availableContentRoles' in metadata;
}

export function resolveReviewInvalidationAffectedItemIds(props: {
	readonly message: BridgeWorkerReviewInvalidateCommand;
	readonly store: BridgeCommWorkerStore;
}): readonly string[] | undefined {
	if (props.message.scope === 'package' || props.message.scope === 'treeWindow') {
		return undefined;
	}
	const itemIds = new Set(props.message.itemIds);
	for (const itemId of findReviewItemIdsByPathHints({
		pathHints: props.message.pathHints,
		store: props.store,
	})) {
		itemIds.add(itemId);
	}
	return Array.from(itemIds);
}

function findReviewItemIdsByPathHints(props: {
	readonly pathHints: readonly string[];
	readonly store: BridgeCommWorkerStore;
}): readonly string[] {
	const pathHints = new Set(props.pathHints);
	return Array.from(props.store.getState().contentMetadataByItemId.values())
		.filter(
			(metadata): metadata is BridgeWorkerReviewContentMetadata =>
				isBridgeWorkerReviewContentMetadata(metadata) && pathHints.has(metadata.path),
		)
		.map((metadata) => metadata.itemId);
}
