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

export function findChangedReviewRuntimeSourceItemIds(props: {
	readonly nextSource: BridgeCommWorkerReviewRuntimeSource;
	readonly previousSource: BridgeCommWorkerReviewRuntimeSource;
}): readonly string[] {
	const candidateItemIds = new Set<string>();
	for (const source of [props.previousSource, props.nextSource]) {
		for (const metadata of source.contentItems) candidateItemIds.add(metadata.itemId);
		for (const descriptor of source.contentRequestDescriptors) {
			candidateItemIds.add(descriptor.itemId);
		}
		for (const semantics of source.renderSemantics) candidateItemIds.add(semantics.itemId);
	}
	return Array.from(candidateItemIds).filter(
		(itemId) =>
			!areReviewContentMetadataEquivalent(
				findReviewContentMetadata(props.previousSource, itemId),
				findReviewContentMetadata(props.nextSource, itemId),
			) ||
			!areReviewContentRequestDescriptorsEquivalent(
				findReviewContentRequestDescriptors(props.previousSource, itemId),
				findReviewContentRequestDescriptors(props.nextSource, itemId),
			) ||
			!areReviewRenderSemanticsEquivalent(
				findReviewRenderSemantics(props.previousSource, itemId),
				findReviewRenderSemantics(props.nextSource, itemId),
			),
	);
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

function findReviewContentRequestDescriptors(
	source: BridgeCommWorkerReviewRuntimeSource,
	itemId: string,
): readonly BridgeWorkerReviewContentRequestDescriptor[] {
	return source.contentRequestDescriptors.filter((descriptor) => descriptor.itemId === itemId);
}

function findReviewRenderSemantics(
	source: BridgeCommWorkerReviewRuntimeSource,
	itemId: string,
): BridgeWorkerReviewRenderSemantics | null {
	return source.renderSemantics.find((semantics) => semantics.itemId === itemId) ?? null;
}

function areReviewContentMetadataEquivalent(
	left: BridgeWorkerReviewContentMetadata | null,
	right: BridgeWorkerReviewContentMetadata | null,
): boolean {
	if (left === null || right === null) return left === right;
	return (
		left.itemId === right.itemId &&
		left.path === right.path &&
		left.language === right.language &&
		left.cacheKey === right.cacheKey &&
		left.sizeBytes === right.sizeBytes &&
		areStringArraysEquivalent(left.availableContentRoles, right.availableContentRoles) &&
		left.contentLineCountsByRole.base === right.contentLineCountsByRole.base &&
		left.contentLineCountsByRole.head === right.contentLineCountsByRole.head &&
		left.contentLineCountsByRole.diff === right.contentLineCountsByRole.diff
	);
}

function areReviewContentRequestDescriptorsEquivalent(
	left: readonly BridgeWorkerReviewContentRequestDescriptor[],
	right: readonly BridgeWorkerReviewContentRequestDescriptor[],
): boolean {
	return (
		left.length === right.length &&
		left.every((leftDescriptor, index) =>
			areReviewContentRequestDescriptorEquivalent(leftDescriptor, right[index] ?? null),
		)
	);
}

function areReviewContentRequestDescriptorEquivalent(
	left: BridgeWorkerReviewContentRequestDescriptor,
	right: BridgeWorkerReviewContentRequestDescriptor | null,
): boolean {
	return (
		right !== null &&
		left.itemId === right.itemId &&
		left.role === right.role &&
		left.handleId === right.handleId &&
		left.reviewGeneration === right.reviewGeneration &&
		left.resourceUrl === right.resourceUrl &&
		left.contentHash === right.contentHash &&
		left.contentHashAlgorithm === right.contentHashAlgorithm &&
		left.language === right.language &&
		left.sizeBytes === right.sizeBytes &&
		(left.expectedBytes ?? null) === (right.expectedBytes ?? null) &&
		left.maxBytes === right.maxBytes &&
		left.isBinary === right.isBinary
	);
}

function areReviewRenderSemanticsEquivalent(
	left: BridgeWorkerReviewRenderSemantics | null,
	right: BridgeWorkerReviewRenderSemantics | null,
): boolean {
	if (left === null || right === null) return left === right;
	return (
		left.itemId === right.itemId &&
		left.itemKind === right.itemKind &&
		left.changeKind === right.changeKind &&
		left.displayPath === right.displayPath &&
		left.basePath === right.basePath &&
		left.headPath === right.headPath &&
		left.language === right.language &&
		left.contentLineCountsByRole.base === right.contentLineCountsByRole.base &&
		left.contentLineCountsByRole.head === right.contentLineCountsByRole.head &&
		left.contentLineCountsByRole.diff === right.contentLineCountsByRole.diff
	);
}

function areStringArraysEquivalent(left: readonly string[], right: readonly string[]): boolean {
	return left.length === right.length && left.every((value, index) => value === right[index]);
}
