import type {
	BridgeAttachedResourceDescriptor,
	BridgeIdentity,
	BridgeIntegrityDescriptor,
} from '../../../core/models/bridge-resource-descriptor.js';
import { parseBridgeCoreResourceUrl } from '../../../core/resources/bridge-resource-url.js';
import {
	contentHandlesForItem,
	orderedReviewItems,
} from '../../../foundation/review-package/bridge-review-package-adapter.js';
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../../foundation/review-package/bridge-review-package.js';
import { makeBridgeReviewProjectionInput } from '../../../review-viewer/navigation/review-projection.js';
import type {
	ReviewChangesetClusterMetadata,
	ReviewMetadataDeltaFrame,
	ReviewMetadataOperation,
	ReviewMetadataSnapshotFrame,
	ReviewMetadataWindowFrame,
} from '../models/review-protocol-models.js';

const bridgeContentRoles = [
	'base',
	'head',
	'diff',
	'file',
] as const satisfies readonly BridgeContentRole[];

export interface BuildReviewMetadataSnapshotFrameProps {
	readonly package: BridgeReviewPackage;
	readonly paneId: string;
	readonly sourceIdentity: string;
	readonly streamId: string;
	readonly sequence: number;
	readonly selectedItemId: string | null;
	readonly visibleItemIds: readonly string[];
	readonly changesetCluster?: ReviewChangesetClusterMetadata;
}

export interface BuildReviewMetadataDeltaFrameProps extends Omit<
	BuildReviewMetadataSnapshotFrameProps,
	'selectedItemId' | 'visibleItemIds'
> {
	readonly fromRevision: number;
	readonly toRevision: number;
	readonly operations: readonly ReviewMetadataOperation[];
}

export interface BuildReviewMetadataWindowFrameProps extends Omit<
	BuildReviewMetadataSnapshotFrameProps,
	'selectedItemId' | 'visibleItemIds' | 'changesetCluster'
> {
	readonly itemIds: readonly string[];
}

export function buildReviewMetadataSnapshotFrame(
	props: BuildReviewMetadataSnapshotFrameProps,
): ReviewMetadataSnapshotFrame {
	const projectionInput = makeBridgeReviewProjectionInput(props.package);
	const metadataItems = metadataItemsForSnapshot(props);
	const metadataItemIds = new Set(metadataItems.map((item) => item.itemId));
	const contentDescriptors = [
		...contentDescriptorsForReviewItems({ ...props, items: metadataItems }),
	];
	const itemsById = props.package.itemsById;

	return {
		kind: 'metadataSnapshot',
		streamId: props.streamId,
		generation: props.package.reviewGeneration,
		sequence: props.sequence,
		frameKind: 'review.metadataSnapshot',
		comparison: {
			packageId: props.package.packageId,
			sourceIdentity: props.sourceIdentity,
			generation: props.package.reviewGeneration,
			revision: props.package.revision,
			baseEndpoint: props.package.baseEndpoint,
			headEndpoint: props.package.headEndpoint,
			...(contentDescriptors.length === 0 ? {} : { contentDescriptors }),
			...(props.changesetCluster === undefined ? {} : { changesetCluster: props.changesetCluster }),
		},
		selectedItemId: props.selectedItemId,
		visibleItemIds: [...props.visibleItemIds],
		itemMetadata: projectionInput.orderedItems
			.filter((item) => metadataItemIds.has(item.itemId))
			.map((item) => ({
				...item,
				contentDescriptorIdsByRole: contentDescriptorIdsByRoleForItem(itemsById[item.itemId]),
			})),
		treeRows: metadataItems.map(reviewItemToTreeRow),
		extentFacts: metadataItems.flatMap(reviewItemToExtentFacts),
		summary: props.package.summary,
	};
}

export function buildReviewMetadataDeltaFrame(
	props: BuildReviewMetadataDeltaFrameProps,
): ReviewMetadataDeltaFrame {
	const operationItemIds = itemIdsForDeltaOperations(props.operations);
	const operationItems =
		operationItemIds.length === 0
			? []
			: metadataItemsForIds({
					itemIds: operationItemIds,
					package: props.package,
				});
	const contentDescriptors =
		operationItems.length === 0
			? []
			: [
					...contentDescriptorsForReviewItems({
						...props,
						items: operationItems,
					}),
				];
	const operations = [
		...metadataDeltaOperationsWithContentDescriptorIds({
			operations: props.operations,
			package: props.package,
		}),
	];
	return {
		kind: 'metadataDelta',
		streamId: props.streamId,
		generation: props.package.reviewGeneration,
		sequence: props.sequence,
		frameKind: 'review.metadataDelta',
		packageId: props.package.packageId,
		fromRevision: props.fromRevision,
		toRevision: props.toRevision,
		operations,
		summary: props.package.summary,
		...(contentDescriptors.length === 0 ? {} : { contentDescriptors }),
	};
}

function metadataDeltaOperationsWithContentDescriptorIds(props: {
	readonly operations: readonly ReviewMetadataOperation[];
	readonly package: BridgeReviewPackage;
}): readonly ReviewMetadataOperation[] {
	return props.operations.map((operation): ReviewMetadataOperation => {
		switch (operation.kind) {
			case 'upsertItemMetadata':
				return {
					...operation,
					item: {
						...operation.item,
						contentDescriptorIdsByRole: contentDescriptorIdsByRoleForItem(
							props.package.itemsById[operation.item.itemId],
						),
					},
				};
			case 'appendItems':
				return {
					...operation,
					items: operation.items.map((item) => ({
						...item,
						contentDescriptorIdsByRole: contentDescriptorIdsByRoleForItem(
							props.package.itemsById[item.itemId],
						),
					})),
				};
			case 'removeItems':
			case 'replaceItemOrder':
			case 'upsertTreeRows':
			case 'removeTreeRows':
			case 'replaceTreeWindow':
			case 'movePathPrefix':
			case 'upsertExtentFacts':
			case 'selectItem':
			case 'invalidateContentDescriptors':
				return operation;
		}
		const exhaustiveOperation: never = operation;
		return exhaustiveOperation;
	});
}

function itemIdsForDeltaOperations(
	operations: readonly ReviewMetadataOperation[],
): readonly string[] {
	const itemIds = new Set<string>();
	for (const operation of operations) {
		switch (operation.kind) {
			case 'upsertItemMetadata':
				itemIds.add(operation.item.itemId);
				break;
			case 'appendItems':
				for (const item of operation.items) {
					itemIds.add(item.itemId);
				}
				break;
			case 'removeItems':
			case 'replaceItemOrder':
			case 'upsertTreeRows':
			case 'removeTreeRows':
			case 'replaceTreeWindow':
			case 'movePathPrefix':
			case 'upsertExtentFacts':
			case 'selectItem':
			case 'invalidateContentDescriptors':
				break;
		}
	}
	return [...itemIds];
}

export function buildReviewMetadataWindowFrame(
	props: BuildReviewMetadataWindowFrameProps,
): ReviewMetadataWindowFrame {
	const projectionInput = makeBridgeReviewProjectionInput(props.package);
	const metadataItems = metadataItemsForIds({
		itemIds: props.itemIds,
		package: props.package,
	});
	const metadataItemIds = new Set(metadataItems.map((item) => item.itemId));
	const contentDescriptors = [
		...contentDescriptorsForReviewItems({ ...props, items: metadataItems }),
	];
	const itemsById = props.package.itemsById;

	return {
		kind: 'metadataWindow',
		streamId: props.streamId,
		generation: props.package.reviewGeneration,
		sequence: props.sequence,
		frameKind: 'review.metadataWindow',
		packageId: props.package.packageId,
		revision: props.package.revision,
		itemMetadata: projectionInput.orderedItems
			.filter((item) => metadataItemIds.has(item.itemId))
			.map((item) => ({
				...item,
				contentDescriptorIdsByRole: contentDescriptorIdsByRoleForItem(itemsById[item.itemId]),
			})),
		treeRows: metadataItems.map(reviewItemToTreeRow),
		extentFacts: metadataItems.flatMap(reviewItemToExtentFacts),
		summary: props.package.summary,
		...(contentDescriptors.length === 0 ? {} : { contentDescriptors }),
	};
}

function metadataItemsForSnapshot(
	props: BuildReviewMetadataSnapshotFrameProps,
): readonly BridgeReviewItemDescriptor[] {
	const includedItemIds = new Set<string>(props.visibleItemIds);
	if (
		props.selectedItemId !== null &&
		props.package.itemsById[props.selectedItemId] !== undefined
	) {
		includedItemIds.add(props.selectedItemId);
	}
	return metadataItemsForIds({
		itemIds: [...includedItemIds],
		package: props.package,
	});
}

function metadataItemsForIds(props: {
	readonly itemIds: readonly string[];
	readonly package: BridgeReviewPackage;
}): readonly BridgeReviewItemDescriptor[] {
	const includedItemIds = new Set<string>(
		props.itemIds.filter((itemId) => props.package.itemsById[itemId] !== undefined),
	);
	return orderedReviewItems(props.package).filter((item) => includedItemIds.has(item.itemId));
}

function contentDescriptorsForReviewItems(props: {
	readonly items: readonly BridgeReviewItemDescriptor[];
	readonly package: BridgeReviewPackage;
	readonly paneId: string;
	readonly sourceIdentity: string;
	readonly streamId: string;
}): readonly BridgeAttachedResourceDescriptor[] {
	return props.items.flatMap(contentHandlesForItem).map(
		(handle): BridgeAttachedResourceDescriptor =>
			contentDescriptorForHandle({
				handle,
				package: props.package,
				paneId: props.paneId,
				sourceIdentity: props.sourceIdentity,
				streamId: props.streamId,
			}),
	);
}

function contentDescriptorIdsByRoleForItem(
	item: BridgeReviewItemDescriptor | undefined,
): ReviewMetadataSnapshotFrame['itemMetadata'][number]['contentDescriptorIdsByRole'] {
	return {
		base: item?.contentRoles.base?.handleId ?? null,
		head: item?.contentRoles.head?.handleId ?? null,
		diff: item?.contentRoles.diff?.handleId ?? null,
		file: item?.contentRoles.file?.handleId ?? null,
	};
}

function contentDescriptorForHandle(props: {
	readonly handle: BridgeContentHandle;
	readonly package: BridgeReviewPackage;
	readonly paneId: string;
	readonly sourceIdentity: string;
	readonly streamId: string;
}): BridgeAttachedResourceDescriptor {
	const parsedResourceUrl = parseBridgeCoreResourceUrl(props.handle.resourceUrl, {
		allowedResourceKindsByProtocol: { review: new Set(['content']) },
	});
	const identity = contentIdentityForHandle({
		handle: props.handle,
		package: props.package,
		paneId: props.paneId,
		sourceIdentity: props.sourceIdentity,
		streamId: props.streamId,
		parsedGeneration: parsedResourceUrl?.generation,
		parsedRevision: parsedResourceUrl?.revision,
		parsedCursor: parsedResourceUrl?.cursor,
	});
	const integrity = integrityForHandle(props.handle);
	const descriptor = {
		descriptorId: props.handle.handleId,
		protocol: 'review',
		resourceKind: 'content',
		resourceUrl: props.handle.resourceUrl,
		identity,
		content: {
			mediaType: props.handle.mimeType,
			encoding: props.handle.isBinary ? 'binary' : 'utf-8',
			expectedBytes: props.handle.sizeBytes,
			maxBytes: Math.max(props.handle.sizeBytes, 1),
			...(integrity === undefined ? {} : { integrity }),
		},
	} satisfies BridgeAttachedResourceDescriptor['descriptor'];
	return {
		ref: {
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: descriptor.resourceKind,
			expectedIdentity: identity,
		},
		descriptor,
	};
}

function contentIdentityForHandle(props: {
	readonly handle: BridgeContentHandle;
	readonly package: BridgeReviewPackage;
	readonly paneId: string;
	readonly sourceIdentity: string;
	readonly streamId: string;
	readonly parsedGeneration: number | undefined;
	readonly parsedRevision: number | undefined;
	readonly parsedCursor: string | undefined;
}): BridgeIdentity {
	return {
		paneId: props.paneId,
		protocol: 'review',
		sourceId: props.sourceIdentity,
		packageId: props.package.packageId,
		generation: props.parsedGeneration ?? props.handle.reviewGeneration,
		...(props.parsedRevision === undefined ? {} : { revision: props.parsedRevision }),
		streamId: props.streamId,
		...(props.parsedCursor === undefined ? {} : { cursor: props.parsedCursor }),
	};
}

function integrityForHandle(handle: BridgeContentHandle): BridgeIntegrityDescriptor | undefined {
	if (!handle.contentHash.startsWith('sha256:') || handle.contentHashAlgorithm !== 'sha256') {
		return undefined;
	}
	return {
		kind: 'wholeHash',
		algorithm: 'sha256',
		value: handle.contentHash,
	};
}

function reviewItemToTreeRow(
	item: BridgeReviewItemDescriptor,
): ReviewMetadataSnapshotFrame['treeRows'][number] {
	return {
		rowId: `review-row:${item.itemId}`,
		itemId: item.itemId,
		path: primaryPathForItem(item),
		depth: primaryPathForItem(item).split('/').length - 1,
		isDirectory: false,
	};
}

function reviewItemToExtentFacts(
	item: BridgeReviewItemDescriptor,
): ReviewMetadataSnapshotFrame['extentFacts'] {
	return bridgeContentRoles.flatMap((contentRole): ReviewMetadataSnapshotFrame['extentFacts'] => {
		const handle = item.contentRoles[contentRole];
		if (handle === null || handle === undefined) {
			return [];
		}
		return [
			{
				itemId: item.itemId,
				contentRole,
				lineCount: lineCountForReviewItemContentRole({ contentRole, item }),
			},
		];
	});
}

function lineCountForReviewItemContentRole(props: {
	readonly contentRole: BridgeContentRole;
	readonly item: BridgeReviewItemDescriptor;
}): number {
	const exactLineCount = props.item.contentLineCountsByRole?.[props.contentRole];
	if (exactLineCount !== null && exactLineCount !== undefined) {
		return exactLineCount;
	}
	switch (props.contentRole) {
		case 'base':
			return Math.max(props.item.deletions, 1);
		case 'head':
		case 'file':
			return Math.max(props.item.additions, 1);
		case 'diff':
			return Math.max(props.item.additions + props.item.deletions, 1);
	}
}

function primaryPathForItem(item: BridgeReviewItemDescriptor): string {
	return item.headPath ?? item.basePath ?? item.itemId;
}
