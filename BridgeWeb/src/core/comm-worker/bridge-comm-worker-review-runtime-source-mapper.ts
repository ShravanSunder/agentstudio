import type { BridgeCommWorkerReviewMetadataSnapshot } from './bridge-comm-worker-review-metadata-projection.js';
import type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-source-diff.js';
import type { BridgeCommWorkerRow } from './bridge-comm-worker-store.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_REVIEW_CONTENT_RANGE_BYTES,
	bridgeProductReviewContentDescriptorSchema,
	type BridgeProductReviewContentSourceDescriptor,
} from './bridge-product-content-contracts.js';
import type {
	BridgeProductReviewExtentFact,
	BridgeProductReviewItemMetadata,
} from './bridge-product-review-metadata-contracts.js';
import type {
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerReviewContentRequestDescriptor,
	BridgeWorkerReviewRenderSemantics,
} from './bridge-worker-contracts.js';

type ReviewContentRole = BridgeProductReviewContentSourceDescriptor['role'];
type ReviewContentLineCounts = BridgeWorkerReviewContentMetadata['contentLineCountsByRole'];

const reviewContentRoleOrder = ['base', 'head', 'diff', 'file'] as const;

export function bridgeCommWorkerReviewRuntimeSourceFromMetadataSnapshot(
	snapshot: BridgeCommWorkerReviewMetadataSnapshot,
): BridgeCommWorkerReviewRuntimeSource {
	return bridgeCommWorkerReviewRuntimeSourceItemsFromMetadataSnapshot({
		itemIds: snapshot.orderedItemIds,
		snapshot,
		rows: reviewRuntimeRowsFromProductTree(snapshot),
	});
}

export function bridgeCommWorkerReviewRuntimeSourceItemsFromMetadataSnapshot(props: {
	readonly itemIds: readonly string[];
	readonly rows?: readonly BridgeCommWorkerRow[];
	readonly snapshot: BridgeCommWorkerReviewMetadataSnapshot;
}): BridgeCommWorkerReviewRuntimeSource {
	const { snapshot } = props;
	const itemMetadataById = new Map(snapshot.itemMetadata.map((item) => [item.itemId, item]));
	const contentSourceByDescriptorId = new Map(
		snapshot.contentSources.map((source) => [source.descriptorId, source]),
	);
	const extentFactsByItemId = groupReviewExtentFactsByItemId(snapshot.extentFacts);
	const orderedItems = props.itemIds.flatMap((itemId) => {
		const item = itemMetadataById.get(itemId);
		return item === undefined ? [] : [item];
	});
	const usableContentSourcesByItemId = new Map<
		string,
		ReadonlyMap<ReviewContentRole, BridgeProductReviewContentSourceDescriptor>
	>();
	for (const item of orderedItems) {
		usableContentSourcesByItemId.set(
			item.itemId,
			usableReviewContentSourcesByRole({ contentSourceByDescriptorId, item, snapshot }),
		);
	}

	return {
		contentItems: orderedItems.map((item) =>
			reviewContentMetadataFromProductItem({
				contentSourcesByRole: usableContentSourcesByItemId.get(item.itemId) ?? new Map(),
				extentFacts: extentFactsByItemId.get(item.itemId) ?? [],
				item,
			}),
		),
		contentRequestDescriptors: orderedItems.flatMap((item) =>
			reviewContentRequestDescriptorsFromProductItem(
				usableContentSourcesByItemId.get(item.itemId) ?? new Map(),
			),
		),
		renderSemantics: orderedItems.map((item) =>
			reviewRenderSemanticsFromProductItem({
				extentFacts: extentFactsByItemId.get(item.itemId) ?? [],
				item,
			}),
		),
		rows: props.rows ?? [],
	};
}

export function bridgeCommWorkerReviewRuntimeRowsFromMetadataSnapshot(
	snapshot: BridgeCommWorkerReviewMetadataSnapshot,
): readonly BridgeCommWorkerRow[] {
	return reviewRuntimeRowsFromProductTree(snapshot);
}

function usableReviewContentSourcesByRole(props: {
	readonly contentSourceByDescriptorId: ReadonlyMap<
		string,
		BridgeProductReviewContentSourceDescriptor
	>;
	readonly item: BridgeProductReviewItemMetadata;
	readonly snapshot: BridgeCommWorkerReviewMetadataSnapshot;
}): ReadonlyMap<ReviewContentRole, BridgeProductReviewContentSourceDescriptor> {
	const sourcesByRole = new Map<ReviewContentRole, BridgeProductReviewContentSourceDescriptor>();
	for (const role of reviewContentRoleOrder) {
		const descriptorId = props.item.contentDescriptorIdsByRole[role] ?? null;
		const source =
			descriptorId === null ? null : props.contentSourceByDescriptorId.get(descriptorId);
		if (
			source === undefined ||
			source === null ||
			props.snapshot.identity === null ||
			source.itemId !== props.item.itemId ||
			source.role !== role ||
			source.packageId !== props.snapshot.identity.packageId ||
			source.sourceIdentity !== props.snapshot.identity.sourceIdentity ||
			source.reviewGeneration !== props.snapshot.identity.generation ||
			source.isBinary ||
			source.encoding !== 'utf-8'
		) {
			continue;
		}
		sourcesByRole.set(role, source);
	}
	return sourcesByRole;
}

function reviewContentMetadataFromProductItem(props: {
	readonly contentSourcesByRole: ReadonlyMap<
		ReviewContentRole,
		BridgeProductReviewContentSourceDescriptor
	>;
	readonly extentFacts: readonly BridgeProductReviewExtentFact[];
	readonly item: BridgeProductReviewItemMetadata;
}): BridgeWorkerReviewContentMetadata {
	const contentSources = reviewContentRoleOrder.flatMap((role) => {
		const source = props.contentSourcesByRole.get(role);
		return source === undefined ? [] : [source];
	});
	return {
		availableContentRoles: contentSources.map((source) => source.role),
		cacheKey: semanticReviewItemCacheKey({
			contentSourcesByRole: props.contentSourcesByRole,
			item: props.item,
		}),
		contentLineCountsByRole: reviewContentLineCounts(props.extentFacts),
		itemId: props.item.itemId,
		language: props.item.language,
		path: reviewItemDisplayPath(props.item),
		sizeBytes: Math.max(0, ...contentSources.map((source) => source.wholeByteLength ?? 0)),
	};
}

function reviewContentRequestDescriptorsFromProductItem(
	contentSourcesByRole: ReadonlyMap<ReviewContentRole, BridgeProductReviewContentSourceDescriptor>,
): readonly BridgeWorkerReviewContentRequestDescriptor[] {
	return reviewContentRoleOrder.flatMap((role) => {
		const source = contentSourcesByRole.get(role);
		return source === undefined ? [] : [reviewContentRequestDescriptorFromProductSource(source)];
	});
}

function reviewContentRequestDescriptorFromProductSource(
	source: BridgeProductReviewContentSourceDescriptor,
): BridgeWorkerReviewContentRequestDescriptor {
	const declaredByteLength =
		source.wholeByteLength !== null &&
		source.wholeByteLength <= BRIDGE_PRODUCT_MAXIMUM_REVIEW_CONTENT_RANGE_BYTES
			? source.wholeByteLength
			: null;
	const expectedSha256 =
		declaredByteLength !== null && source.contentDigest.authority === 'authoritative'
			? source.contentDigest.value
			: null;
	return bridgeProductReviewContentDescriptorSchema.parse({
		...source,
		declaredByteLength,
		encoding: 'utf-8',
		expectedSha256,
		isBinary: false,
		maximumBytes: BRIDGE_PRODUCT_MAXIMUM_REVIEW_CONTENT_RANGE_BYTES,
		window: {
			kind: 'byteRange',
			maximumBytes: BRIDGE_PRODUCT_MAXIMUM_REVIEW_CONTENT_RANGE_BYTES,
			startByte: 0,
		},
	});
}

function reviewRenderSemanticsFromProductItem(props: {
	readonly extentFacts: readonly BridgeProductReviewExtentFact[];
	readonly item: BridgeProductReviewItemMetadata;
}): BridgeWorkerReviewRenderSemantics {
	return {
		basePath: props.item.basePath,
		changeKind: props.item.changeKind,
		contentLineCountsByRole: reviewContentLineCounts(props.extentFacts),
		displayPath: reviewItemDisplayPath(props.item),
		headPath: props.item.headPath,
		itemId: props.item.itemId,
		itemKind: reviewItemKindFromProductItem(props.item),
		language: props.item.language,
	};
}

function semanticReviewItemCacheKey(props: {
	readonly contentSourcesByRole: ReadonlyMap<
		ReviewContentRole,
		BridgeProductReviewContentSourceDescriptor
	>;
	readonly item: BridgeProductReviewItemMetadata;
}): string {
	const itemKind = reviewItemKindFromProductItem(props.item);
	const roleKeys = reviewContentRoleOrder.flatMap((role) => {
		if (!props.item.contentRoles.includes(role)) return [];
		const source = props.contentSourcesByRole.get(role);
		if (source !== undefined) {
			return [
				`${role}:${source.contentDigest.algorithm}:${source.contentDigest.authority}:${source.contentDigest.value}`,
			];
		}
		const metadataHash = props.item.contentHashesByRole[role] ?? null;
		return metadataHash === null ? [`${role}:unavailable`] : [`${role}:metadata:${metadataHash}`];
	});
	return `review:${itemKind}:${roleKeys.length === 0 ? `item:${props.item.itemId}` : roleKeys.join('|')}`;
}

function reviewItemKindFromProductItem(
	item: BridgeProductReviewItemMetadata,
): BridgeWorkerReviewRenderSemantics['itemKind'] {
	return item.contentRoles.includes('file') &&
		!item.contentRoles.some((role) => role === 'base' || role === 'head' || role === 'diff')
		? 'file'
		: 'diff';
}

function reviewContentLineCounts(
	extentFacts: readonly BridgeProductReviewExtentFact[],
): ReviewContentLineCounts {
	const lineCounts: Partial<Record<ReviewContentRole, number>> = {};
	for (const fact of extentFacts) lineCounts[fact.contentRole] = fact.lineCount;
	return lineCounts;
}

function groupReviewExtentFactsByItemId(
	extentFacts: readonly BridgeProductReviewExtentFact[],
): ReadonlyMap<string, readonly BridgeProductReviewExtentFact[]> {
	const factsByItemId = new Map<string, BridgeProductReviewExtentFact[]>();
	for (const fact of extentFacts) {
		const itemFacts = factsByItemId.get(fact.itemId) ?? [];
		itemFacts.push(fact);
		factsByItemId.set(fact.itemId, itemFacts);
	}
	return factsByItemId;
}

function reviewRuntimeRowsFromProductTree(
	snapshot: BridgeCommWorkerReviewMetadataSnapshot,
): readonly BridgeCommWorkerRow[] {
	const directoryIdByDepth: Array<string | undefined> = [];
	return snapshot.treeRows.map((treeRow, index) => {
		const id = treeRow.itemId ?? treeRow.rowId;
		const parentId = treeRow.depth === 0 ? null : (directoryIdByDepth[treeRow.depth - 1] ?? null);
		directoryIdByDepth.length = treeRow.depth;
		if (treeRow.isDirectory) directoryIdByDepth[treeRow.depth] = id;
		return { id, index, parentId };
	});
}

function reviewItemDisplayPath(item: BridgeProductReviewItemMetadata): string {
	return item.headPath ?? item.basePath ?? item.itemId;
}
