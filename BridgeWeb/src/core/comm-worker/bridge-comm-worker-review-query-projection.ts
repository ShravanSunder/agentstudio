import type { BridgeWorkerReviewProjectionQuery } from './bridge-worker-contracts.js';
import type {
	BridgeWorkerReviewDisplayItem,
	BridgeWorkerReviewDisplayPatch,
} from './bridge-worker-review-display-patch-contracts.js';

type ReviewItemPatch = Extract<BridgeWorkerReviewDisplayPatch, { readonly slice: 'reviewItem' }>;
type ReviewItemOperation = Extract<
	ReviewItemPatch,
	{ readonly operation: 'batch' }
>['payload']['operations'][number];
type ReviewSourcePatch = Extract<
	BridgeWorkerReviewDisplayPatch,
	{ readonly slice: 'reviewSource' }
>;
type ReviewTreePatch = Extract<BridgeWorkerReviewDisplayPatch, { readonly slice: 'reviewTree' }>;
type ReviewTreeRow = Extract<
	ReviewTreePatch,
	{ readonly operation: 'batch' }
>['payload']['windows'][number]['rows'][number];

const defaultReviewProjectionQuery: BridgeWorkerReviewProjectionQuery = {
	fileClassFilter: 'all',
	gitStatusFilter: 'all',
};

export class BridgeCommWorkerReviewQueryProjection {
	readonly #itemsById = new Map<string, BridgeWorkerReviewDisplayItem>();
	#itemIdsByIndex: Array<string | null> = [];
	#query: BridgeWorkerReviewProjectionQuery = defaultReviewProjectionQuery;
	#sourcePatch: ReviewSourcePatch | null = null;
	#treeRowsByIndex: Array<ReviewTreeRow | null> = [];

	applyDisplayPatches(
		patches: readonly BridgeWorkerReviewDisplayPatch[],
	): readonly BridgeWorkerReviewDisplayPatch[] {
		for (const patch of patches) this.#applyRawPatch(patch);
		return reviewProjectionQueryIsDefault(this.#query) ? patches : this.snapshotDisplayPatches();
	}

	updateQuery(query: BridgeWorkerReviewProjectionQuery): readonly BridgeWorkerReviewDisplayPatch[] {
		if (reviewProjectionQueriesEqual(this.#query, query)) return [];
		this.#query = query;
		return this.snapshotDisplayPatches();
	}

	snapshotDisplayPatches(): readonly BridgeWorkerReviewDisplayPatch[] {
		const orderedItems = this.#itemIdsByIndex.flatMap((itemId) => {
			if (itemId === null) return [];
			const item = this.#itemsById.get(itemId);
			return item === undefined ? [] : [item];
		});
		const projectedItems = orderedItems.filter((item) => this.#matchesQuery(item));
		const projectedItemIds = new Set(projectedItems.map((item) => item.metadata.itemId));
		const projectedTreeRows = requiredReviewTreeRows({
			matchedItemIds: projectedItemIds,
			rows: this.#treeRowsByIndex.filter((row): row is ReviewTreeRow => row !== null),
		});
		return [
			...(this.#sourcePatch === null ? [] : [this.#sourcePatch]),
			{
				operation: 'batch',
				payload: {
					items: projectedItems,
					operations: [],
					reset: true,
					startIndex: 0,
				},
				slice: 'reviewItem',
			},
			{
				operation: 'batch',
				payload: {
					reset: true,
					windows: [{ rows: projectedTreeRows, startIndex: 0 }],
				},
				slice: 'reviewTree',
			},
		];
	}

	#applyRawPatch(patch: BridgeWorkerReviewDisplayPatch): void {
		switch (patch.slice) {
			case 'reviewSource':
				this.#sourcePatch = patch;
				break;
			case 'reviewItem':
				this.#applyItemPatch(patch);
				break;
			case 'reviewTree':
				this.#applyTreePatch(patch);
				break;
			default:
				assertNeverReviewDisplayPatch(patch);
		}
	}

	#applyItemPatch(patch: ReviewItemPatch): void {
		if (patch.operation === 'reset') {
			this.#itemsById.clear();
			this.#itemIdsByIndex = [];
			return;
		}
		if (patch.payload.reset) {
			this.#itemsById.clear();
			this.#itemIdsByIndex = [];
		}
		for (const item of patch.payload.items) this.#itemsById.set(item.metadata.itemId, item);
		if (patch.payload.startIndex !== null) {
			for (const [offset, item] of patch.payload.items.entries()) {
				this.#itemIdsByIndex[patch.payload.startIndex + offset] = item.metadata.itemId;
			}
		}
		for (const operation of patch.payload.operations) this.#applyItemOperation(operation);
	}

	#applyItemOperation(operation: ReviewItemOperation): void {
		switch (operation.operationKind) {
			case 'upsertItems':
				for (const item of operation.items) this.#itemsById.set(item.metadata.itemId, item);
				break;
			case 'removeItems': {
				const removedItemIds = new Set(operation.itemIds);
				for (const itemId of removedItemIds) this.#itemsById.delete(itemId);
				this.#itemIdsByIndex = this.#itemIdsByIndex.filter(
					(itemId) => itemId === null || !removedItemIds.has(itemId),
				);
				break;
			}
			case 'replaceItemOrder':
				this.#itemIdsByIndex = operation.itemIds.map((itemId) => itemId);
				break;
			case 'spliceTreeRows':
				this.#treeRowsByIndex.splice(
					operation.startIndex,
					operation.deleteCount,
					...operation.rows,
				);
				break;
			default:
				assertNeverReviewItemOperation(operation);
		}
	}

	#applyTreePatch(patch: ReviewTreePatch): void {
		if (patch.operation === 'reset') {
			this.#treeRowsByIndex = [];
			return;
		}
		if (patch.payload.reset) this.#treeRowsByIndex = [];
		for (const window of patch.payload.windows) {
			for (const [offset, row] of window.rows.entries()) {
				this.#treeRowsByIndex[window.startIndex + offset] = row;
			}
		}
	}

	#matchesQuery(item: BridgeWorkerReviewDisplayItem): boolean {
		return (
			(this.#query.fileClassFilter === 'all' ||
				item.metadata.fileClass === this.#query.fileClassFilter) &&
			(this.#query.gitStatusFilter === 'all' ||
				item.metadata.changeKind === this.#query.gitStatusFilter)
		);
	}
}

function requiredReviewTreeRows(props: {
	readonly matchedItemIds: ReadonlySet<string>;
	readonly rows: readonly ReviewTreeRow[];
}): readonly ReviewTreeRow[] {
	if (props.matchedItemIds.size === 0) return [];
	const ancestorRowsByDepth: Array<ReviewTreeRow | undefined> = [];
	const includedRowIds = new Set<string>();
	for (const row of props.rows) {
		ancestorRowsByDepth.length = row.depth;
		if (row.isDirectory) {
			ancestorRowsByDepth[row.depth] = row;
			continue;
		}
		if (row.itemId === null || !props.matchedItemIds.has(row.itemId)) continue;
		for (const ancestor of ancestorRowsByDepth) {
			if (ancestor !== undefined) includedRowIds.add(ancestor.rowId);
		}
		includedRowIds.add(row.rowId);
	}
	return props.rows.filter((row) => includedRowIds.has(row.rowId));
}

function reviewProjectionQueryIsDefault(query: BridgeWorkerReviewProjectionQuery): boolean {
	return query.fileClassFilter === 'all' && query.gitStatusFilter === 'all';
}

function reviewProjectionQueriesEqual(
	left: BridgeWorkerReviewProjectionQuery,
	right: BridgeWorkerReviewProjectionQuery,
): boolean {
	return (
		left.fileClassFilter === right.fileClassFilter && left.gitStatusFilter === right.gitStatusFilter
	);
}

function assertNeverReviewDisplayPatch(patch: never): never {
	throw new Error(`Unhandled Review display patch: ${JSON.stringify(patch)}`);
}

function assertNeverReviewItemOperation(operation: never): never {
	throw new Error(`Unhandled Review item operation: ${JSON.stringify(operation)}`);
}
