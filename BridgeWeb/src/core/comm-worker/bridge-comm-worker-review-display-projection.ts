import type {
	BridgeCommWorkerReviewMetadataApplyResult,
	BridgeCommWorkerReviewMetadataSnapshot,
} from './bridge-comm-worker-review-metadata-projection.js';
import type { BridgeProductReviewMetadataEvent } from './bridge-product-review-metadata-contracts.js';
import type {
	BridgeWorkerReviewDisplayItem,
	BridgeWorkerReviewDisplayPatch,
	BridgeWorkerReviewSourceDisplayPayload,
} from './bridge-worker-contracts.js';

type ReviewDeltaEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.delta' }
>;
type ReviewDisplayMutationOperation = Extract<
	BridgeWorkerReviewDisplayPatch,
	{ readonly operation: 'batch'; readonly slice: 'reviewItem' }
>['payload']['operations'][number];

interface ReviewDisplayProjectionIndex {
	readonly displayItem: (itemId: string) => BridgeWorkerReviewDisplayItem | undefined;
}

export function bridgeCommWorkerReviewDisplayPatches(props: {
	readonly event: BridgeProductReviewMetadataEvent;
	readonly projectionResult: BridgeCommWorkerReviewMetadataApplyResult;
	readonly sourceStatus: BridgeWorkerReviewSourceDisplayPayload['status'];
	readonly snapshot: BridgeCommWorkerReviewMetadataSnapshot;
}): readonly BridgeWorkerReviewDisplayPatch[] {
	const sourcePatch = reviewSourceDisplayPatch(props.snapshot, props.sourceStatus);
	switch (props.event.eventKind) {
		case 'review.sourceAccepted':
		case 'review.reset':
			return [
				sourcePatch,
				{ operation: 'reset', slice: 'reviewItem' },
				{ operation: 'reset', slice: 'reviewTree' },
			];
		case 'review.snapshot':
		case 'review.window': {
			const projectionIndex = createReviewDisplayProjectionIndex(props.snapshot);
			return [
				sourcePatch,
				{
					operation: 'batch',
					payload: {
						items: reviewDisplayItemsForItemIds(
							props.event.itemMetadata.map((item) => item.itemId),
							projectionIndex,
						),
						operations: [],
						reset: props.event.eventKind === 'review.snapshot',
						startIndex: props.event.itemWindow.startIndex,
					},
					slice: 'reviewItem',
				},
				{
					operation: 'batch',
					payload: {
						reset: props.event.eventKind === 'review.snapshot',
						windows: [
							{
								rows: props.event.treeRows,
								startIndex: props.event.treeWindow.startIndex,
							},
						],
					},
					slice: 'reviewTree',
				},
			];
		}
		case 'review.delta': {
			const projectionIndex = createReviewDisplayProjectionIndex(props.snapshot);
			const operations = reviewDisplayMutationOperations({
				event: props.event,
				projectionIndex,
				projectionResult: props.projectionResult,
			});
			const items = reviewDisplayItemsForItemIds(
				props.projectionResult.affectedItemIds,
				projectionIndex,
			);
			return operations.length === 0 && items.length === 0
				? [sourcePatch]
				: [
						sourcePatch,
						{
							operation: 'batch',
							payload: { items, operations, reset: false, startIndex: null },
							slice: 'reviewItem',
						},
					];
		}
		case 'review.invalidated':
			return [sourcePatch];
		default:
			return assertNeverReviewMetadataEvent(props.event);
	}
}

function reviewSourceDisplayPatch(
	snapshot: BridgeCommWorkerReviewMetadataSnapshot,
	status: BridgeWorkerReviewSourceDisplayPayload['status'],
): Extract<BridgeWorkerReviewDisplayPatch, { readonly slice: 'reviewSource' }> {
	if (snapshot.identity === null || snapshot.revision === null) {
		throw new Error('Review display projection requires active source identity and revision.');
	}
	const payload: BridgeWorkerReviewSourceDisplayPayload = {
		metadataWindowIdentity: reviewMetadataWindowIdentity(snapshot),
		reviewGeneration: snapshot.identity.generation,
		status,
		summary: snapshot.summary,
		totalItemCount: snapshot.totalItemCount,
		totalTreeRowCount: snapshot.totalTreeRowCount,
	};
	return { operation: 'upsert', payload, slice: 'reviewSource' };
}

function reviewDisplayMutationOperations(props: {
	readonly event: ReviewDeltaEvent;
	readonly projectionIndex: ReviewDisplayProjectionIndex;
	readonly projectionResult: BridgeCommWorkerReviewMetadataApplyResult;
}): readonly ReviewDisplayMutationOperation[] {
	const operations: ReviewDisplayMutationOperation[] = [];
	const sourceItemIds = [...new Set(props.event.contentSources.map((source) => source.itemId))];
	pushReviewDisplayItemUpsert(operations, sourceItemIds, props.projectionIndex);
	for (const operation of props.event.operations) {
		switch (operation.operationKind) {
			case 'upsertItem':
				pushReviewDisplayItemUpsert(operations, [operation.item.itemId], props.projectionIndex);
				break;
			case 'removeItems':
				operations.push({ itemIds: operation.itemIds, operationKind: 'removeItems' });
				break;
			case 'replaceItemOrder':
				operations.push({ itemIds: operation.itemIds, operationKind: 'replaceItemOrder' });
				break;
			case 'spliceTreeRows':
				operations.push({
					deleteCount: operation.deleteCount,
					operationKind: 'spliceTreeRows',
					rows: operation.rows,
					startIndex: operation.startIndex,
				});
				break;
			case 'upsertExtentFacts':
				pushReviewDisplayItemUpsert(
					operations,
					[...new Set(operation.facts.map((fact) => fact.itemId))],
					props.projectionIndex,
				);
				break;
			case 'invalidateContentSources':
				pushReviewDisplayItemUpsert(
					operations,
					props.projectionResult.affectedItemIds,
					props.projectionIndex,
				);
				break;
			default:
				assertNeverReviewMetadataOperation(operation);
		}
	}
	return operations;
}

function pushReviewDisplayItemUpsert(
	operations: ReviewDisplayMutationOperation[],
	itemIds: readonly string[],
	projectionIndex: ReviewDisplayProjectionIndex,
): void {
	const items = reviewDisplayItemsForItemIds(itemIds, projectionIndex);
	if (items.length > 0) operations.push({ items, operationKind: 'upsertItems' });
}

function createReviewDisplayProjectionIndex(
	snapshot: BridgeCommWorkerReviewMetadataSnapshot,
): ReviewDisplayProjectionIndex {
	const metadataById = new Map(snapshot.itemMetadata.map((item) => [item.itemId, item]));
	const contentSourcesByDescriptorId = new Map(
		snapshot.contentSources.map((source) => [source.descriptorId, source]),
	);
	const extentFactsByItemId = new Map<
		string,
		BridgeWorkerReviewDisplayItem['extentFacts'][number][]
	>();
	for (const fact of snapshot.extentFacts) {
		const itemFacts = extentFactsByItemId.get(fact.itemId) ?? [];
		itemFacts.push(fact);
		extentFactsByItemId.set(fact.itemId, itemFacts);
	}
	return {
		displayItem: (itemId): BridgeWorkerReviewDisplayItem | undefined => {
			const metadata = metadataById.get(itemId);
			if (metadata === undefined) return undefined;
			const referencedContentSources = metadata.contentRoles.flatMap((role) => {
				const descriptorId = metadata.contentDescriptorIdsByRole[role];
				if (descriptorId === null || descriptorId === undefined) return [];
				const source = contentSourcesByDescriptorId.get(descriptorId);
				return source === undefined ? [] : [source];
			});
			const semanticDocumentRevision = reviewSemanticDocumentRevision({
				contentSources: referencedContentSources,
				contentRoles: metadata.contentRoles,
			});
			return {
				contentFacts: referencedContentSources.map((source) => ({
					contentDigest: source.contentDigest,
					role: source.role,
					semanticDocumentRevision,
				})),
				extentFacts: extentFactsByItemId.get(itemId) ?? [],
				metadata,
				metadataWindowIdentity: reviewMetadataWindowIdentity(snapshot, itemId),
			};
		},
	};
}

function reviewDisplayItemsForItemIds(
	itemIds: readonly string[],
	projectionIndex: ReviewDisplayProjectionIndex,
): readonly BridgeWorkerReviewDisplayItem[] {
	return itemIds.flatMap((itemId): readonly BridgeWorkerReviewDisplayItem[] => {
		const displayItem = projectionIndex.displayItem(itemId);
		return displayItem === undefined ? [] : [displayItem];
	});
}

function reviewMetadataWindowIdentity(
	snapshot: BridgeCommWorkerReviewMetadataSnapshot,
	itemId?: string,
): string {
	if (snapshot.identity === null || snapshot.revision === null) {
		throw new Error(
			'Review metadata window identity requires active source identity and revision.',
		);
	}
	return JSON.stringify([
		'bridge-review-metadata-window-v1',
		snapshot.identity.sourceIdentity,
		snapshot.identity.generation,
		snapshot.identity.publicationId,
		snapshot.revision,
		...(itemId === undefined ? [] : [itemId]),
	]);
}

function reviewSemanticDocumentRevision(props: {
	readonly contentRoles: readonly string[];
	readonly contentSources: readonly {
		readonly contentDigest: {
			readonly algorithm: string;
			readonly authority: string;
			readonly value: string;
		};
		readonly role: string;
	}[];
}): string {
	const documentKind =
		props.contentRoles.includes('base') || props.contentRoles.includes('diff') ? 'diff' : 'file';
	return JSON.stringify([
		'bridge-semantic-document-v1',
		documentKind,
		props.contentSources.map((source) => [
			source.role,
			source.contentDigest.algorithm,
			source.contentDigest.authority,
			source.contentDigest.value,
		]),
	]);
}

function assertNeverReviewMetadataEvent(event: never): never {
	throw new Error(`Unhandled Review metadata display event: ${JSON.stringify(event)}`);
}

function assertNeverReviewMetadataOperation(operation: never): never {
	throw new Error(`Unhandled Review metadata display operation: ${JSON.stringify(operation)}`);
}
