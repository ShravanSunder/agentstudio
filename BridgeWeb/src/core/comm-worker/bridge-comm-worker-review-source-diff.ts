import { canRenderBridgeWorkerReviewContentForSemantics } from './bridge-comm-worker-review-runtime.js';
import type { BridgeCommWorkerRow } from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerReviewContentRequestDescriptor,
	BridgeWorkerReviewRenderSemantics,
} from './bridge-worker-contracts.js';

export interface BridgeCommWorkerReviewRuntimeSource {
	readonly contentItems: readonly BridgeWorkerReviewContentMetadata[];
	readonly contentRequestDescriptors: readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly renderSemantics: readonly BridgeWorkerReviewRenderSemantics[];
	readonly rows: readonly BridgeCommWorkerRow[];
}

export function isReviewRuntimeSourceExecutableForItem(
	source: BridgeCommWorkerReviewRuntimeSource,
	itemId: string,
): boolean {
	const metadata = findReviewContentMetadata(source, itemId);
	const semantics = findReviewRenderSemantics(source, itemId);
	return (
		metadata !== null &&
		metadata.availableContentRoles.length > 0 &&
		semantics !== null &&
		canRenderBridgeWorkerReviewContentForSemantics({
			descriptors: source.contentRequestDescriptors,
			semantics,
		})
	);
}

function findReviewContentMetadata(
	source: BridgeCommWorkerReviewRuntimeSource,
	itemId: string,
): BridgeWorkerReviewContentMetadata | null {
	return source.contentItems.find((metadata) => metadata.itemId === itemId) ?? null;
}

function findReviewRenderSemantics(
	source: BridgeCommWorkerReviewRuntimeSource,
	itemId: string,
): BridgeWorkerReviewRenderSemantics | null {
	return source.renderSemantics.find((semantics) => semantics.itemId === itemId) ?? null;
}
