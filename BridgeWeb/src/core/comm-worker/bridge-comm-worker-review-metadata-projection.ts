import type { BridgeProductReviewContentSourceDescriptor } from './bridge-product-content-contracts.js';
import type {
	BridgeProductReviewExtentFact,
	BridgeProductReviewItemMetadata,
	BridgeProductReviewMetadataEvent,
	BridgeProductReviewTreeRow,
} from './bridge-product-review-metadata-contracts.js';

type ReviewMetadataDeltaEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.delta' }
>;
type ReviewMetadataInvalidatedEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.invalidated' }
>;
type ReviewMetadataPayloadEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.snapshot' | 'review.window' }
>;

export interface BridgeCommWorkerReviewMetadataIdentity {
	readonly generation: number;
	readonly packageId: string;
	readonly sourceIdentity: string;
}

export interface BridgeCommWorkerReviewMetadataSnapshot {
	readonly contentSources: readonly BridgeProductReviewContentSourceDescriptor[];
	readonly extentFacts: readonly BridgeProductReviewExtentFact[];
	readonly identity: BridgeCommWorkerReviewMetadataIdentity | null;
	readonly itemMetadata: readonly BridgeProductReviewItemMetadata[];
	readonly orderedItemIds: readonly string[];
	readonly revision: number | null;
	readonly totalItemCount: number | null;
	readonly totalTreeRowCount: number | null;
	readonly treeRows: readonly BridgeProductReviewTreeRow[];
}

export interface BridgeCommWorkerReviewMetadataApplyResult {
	readonly affectedItemIds: readonly string[];
	readonly invalidation: ReviewMetadataInvalidatedEvent | null;
	readonly projectionRevision: number;
	readonly reset: boolean;
}

export class BridgeCommWorkerReviewMetadataProjection {
	readonly #contentSourceByDescriptorId = new Map<
		string,
		BridgeProductReviewContentSourceDescriptor
	>();
	readonly #extentFactByKey = new Map<string, BridgeProductReviewExtentFact>();
	readonly #itemIndexById = new Map<string, number>();
	readonly #itemMetadataById = new Map<string, BridgeProductReviewItemMetadata>();
	#identity: BridgeCommWorkerReviewMetadataIdentity | null = null;
	#itemIdsByIndex: Array<string | undefined> = [];
	#projectionRevision = 0;
	#revision: number | null = null;
	#totalItemCount: number | null = null;
	#totalTreeRowCount: number | null = null;
	readonly #treeRowIndexById = new Map<string, number>();
	#treeRows: Array<BridgeProductReviewTreeRow | undefined> = [];

	apply(event: BridgeProductReviewMetadataEvent): BridgeCommWorkerReviewMetadataApplyResult {
		const affectedItemIds = new Set<string>();
		let invalidation: ReviewMetadataInvalidatedEvent | null = null;
		let reset = false;
		switch (event.eventKind) {
			case 'review.sourceAccepted':
				if (!this.#matchesIdentity(event) || this.#revision !== event.revision) {
					this.#resetProjection();
					reset = true;
				}
				this.#identity = reviewMetadataIdentity(event);
				this.#revision = event.revision;
				break;
			case 'review.snapshot':
				this.#resetProjection();
				this.#identity = reviewMetadataIdentity(event);
				this.#revision = event.revision;
				this.#applyPayload(event, affectedItemIds);
				reset = true;
				break;
			case 'review.window':
				this.#assertCurrentIdentity(event);
				this.#assertCurrentRevision(event.revision);
				this.#applyPayload(event, affectedItemIds);
				break;
			case 'review.delta':
				this.#applyDelta(event, affectedItemIds);
				break;
			case 'review.invalidated':
				this.#assertCurrentIdentity(event);
				this.#assertCurrentRevision(event.revision);
				for (const itemId of event.itemIds) affectedItemIds.add(itemId);
				invalidation = event;
				break;
			case 'review.reset':
				this.#assertCurrentIdentity(event);
				this.#resetProjection();
				this.#identity = reviewMetadataIdentity(event);
				this.#revision = event.revision;
				reset = true;
				break;
			default:
				assertNeverReviewMetadataEvent(event);
		}
		this.#projectionRevision += 1;
		return {
			affectedItemIds: [...affectedItemIds],
			invalidation,
			projectionRevision: this.#projectionRevision,
			reset,
		};
	}

	snapshot(): BridgeCommWorkerReviewMetadataSnapshot {
		const orderedItemIds = this.#itemIdsByIndex.filter(
			(itemId): itemId is string => itemId !== undefined,
		);
		return {
			contentSources: [...this.#contentSourceByDescriptorId.values()].toSorted((left, right) =>
				left.descriptorId.localeCompare(right.descriptorId),
			),
			extentFacts: [...this.#extentFactByKey.values()].toSorted(compareReviewExtentFacts),
			identity: this.#identity,
			itemMetadata: orderedItemIds.flatMap((itemId) => {
				const item = this.#itemMetadataById.get(itemId);
				return item === undefined ? [] : [item];
			}),
			orderedItemIds,
			revision: this.#revision,
			totalItemCount: this.#totalItemCount,
			totalTreeRowCount: this.#totalTreeRowCount,
			treeRows: this.#treeRows.filter(
				(row): row is BridgeProductReviewTreeRow => row !== undefined,
			),
		};
	}

	#applyPayload(event: ReviewMetadataPayloadEvent, affectedItemIds: Set<string>): void {
		this.#applyItemWindow(event, affectedItemIds);
		this.#applyTreeWindow(event);
		for (const item of event.itemMetadata) {
			this.#itemMetadataById.set(item.itemId, item);
			affectedItemIds.add(item.itemId);
		}
		this.#upsertContentSources(event.contentSources, affectedItemIds);
		for (const fact of event.extentFacts) {
			this.#extentFactByKey.set(reviewExtentFactKey(fact), fact);
			affectedItemIds.add(fact.itemId);
		}
	}

	#applyItemWindow(event: ReviewMetadataPayloadEvent, affectedItemIds: Set<string>): void {
		const window = event.itemWindow;
		if (this.#totalItemCount !== null && this.#totalItemCount !== window.totalItemCount) {
			throw new Error('Bridge Review item window changed its declared ordered total.');
		}
		this.#totalItemCount = window.totalItemCount;
		this.#itemIdsByIndex.length = window.totalItemCount;
		for (const [offset, item] of event.itemMetadata.entries()) {
			const index = window.startIndex + offset;
			const existingItemId = this.#itemIdsByIndex[index];
			const existingIndex = this.#itemIndexById.get(item.itemId);
			if (
				(existingItemId !== undefined && existingItemId !== item.itemId) ||
				(existingIndex !== undefined && existingIndex !== index)
			) {
				throw new Error('Bridge Review item window conflicts with existing ordered identity.');
			}
			this.#itemIdsByIndex[index] = item.itemId;
			this.#itemIndexById.set(item.itemId, index);
			affectedItemIds.add(item.itemId);
		}
	}

	#applyTreeWindow(event: ReviewMetadataPayloadEvent): void {
		const window = event.treeWindow;
		if (this.#totalTreeRowCount !== null && this.#totalTreeRowCount !== window.totalRowCount) {
			throw new Error('Bridge Review tree window changed its declared ordered total.');
		}
		this.#totalTreeRowCount = window.totalRowCount;
		this.#treeRows.length = window.totalRowCount;
		for (const [offset, row] of event.treeRows.entries()) {
			const index = window.startIndex + offset;
			const existingRow = this.#treeRows[index];
			const existingIndex = this.#treeRowIndexById.get(row.rowId);
			if (
				(existingRow !== undefined && existingRow.rowId !== row.rowId) ||
				(existingIndex !== undefined && existingIndex !== index)
			) {
				throw new Error('Bridge Review tree window conflicts with existing ordered identity.');
			}
			this.#treeRows[index] = row;
			this.#treeRowIndexById.set(row.rowId, index);
		}
	}

	#applyDelta(event: ReviewMetadataDeltaEvent, affectedItemIds: Set<string>): void {
		this.#assertCurrentIdentity(event);
		this.#assertCurrentRevision(event.fromRevision);
		this.#upsertContentSources(event.contentSources, affectedItemIds);
		for (const operation of event.operations) {
			switch (operation.operationKind) {
				case 'upsertItem':
					this.#itemMetadataById.set(operation.item.itemId, operation.item);
					affectedItemIds.add(operation.item.itemId);
					break;
				case 'removeItems':
					this.#removeItems(operation.itemIds, affectedItemIds);
					break;
				case 'replaceItemOrder':
					this.#itemIdsByIndex = [...operation.itemIds];
					this.#itemIndexById.clear();
					for (const [index, itemId] of operation.itemIds.entries()) {
						this.#itemIndexById.set(itemId, index);
					}
					this.#totalItemCount = operation.itemIds.length;
					for (const itemId of operation.itemIds) affectedItemIds.add(itemId);
					break;
				case 'spliceTreeRows':
					this.#spliceTreeRows(operation.startIndex, operation.deleteCount, operation.rows);
					break;
				case 'upsertExtentFacts':
					for (const fact of operation.facts) {
						this.#extentFactByKey.set(reviewExtentFactKey(fact), fact);
						affectedItemIds.add(fact.itemId);
					}
					break;
				case 'invalidateContentSources':
					for (const descriptorId of operation.descriptorIds) {
						const source = this.#contentSourceByDescriptorId.get(descriptorId);
						if (source !== undefined) affectedItemIds.add(source.itemId);
						this.#contentSourceByDescriptorId.delete(descriptorId);
					}
					break;
				default:
					assertNeverReviewMetadataOperation(operation);
			}
		}
		this.#revision = event.toRevision;
	}

	#removeItems(itemIds: readonly string[], affectedItemIds: Set<string>): void {
		const removedItemIds = new Set(itemIds);
		for (const itemId of itemIds) {
			this.#itemMetadataById.delete(itemId);
			affectedItemIds.add(itemId);
		}
		this.#itemIdsByIndex = this.#itemIdsByIndex.filter(
			(itemId) => itemId === undefined || !removedItemIds.has(itemId),
		);
		this.#itemIndexById.clear();
		for (const [index, itemId] of this.#itemIdsByIndex.entries()) {
			if (itemId !== undefined) this.#itemIndexById.set(itemId, index);
		}
		this.#totalItemCount = this.#itemIdsByIndex.length;
		for (const [descriptorId, source] of this.#contentSourceByDescriptorId) {
			if (removedItemIds.has(source.itemId)) this.#contentSourceByDescriptorId.delete(descriptorId);
		}
		for (const [factKey, fact] of this.#extentFactByKey) {
			if (removedItemIds.has(fact.itemId)) this.#extentFactByKey.delete(factKey);
		}
	}

	#spliceTreeRows(
		startIndex: number,
		deleteCount: number,
		rows: readonly BridgeProductReviewTreeRow[],
	): void {
		if (startIndex > this.#treeRows.length || startIndex + deleteCount > this.#treeRows.length) {
			throw new Error('Bridge Review tree splice exceeds the current ordered extent.');
		}
		const nextRows = [...this.#treeRows];
		nextRows.splice(startIndex, deleteCount, ...rows);
		const rowIds = nextRows.flatMap((row) => (row === undefined ? [] : [row.rowId]));
		if (new Set(rowIds).size !== rowIds.length) {
			throw new Error('Bridge Review tree splice produces duplicate row identities.');
		}
		this.#treeRows = nextRows;
		this.#treeRowIndexById.clear();
		for (const [index, row] of nextRows.entries()) {
			if (row !== undefined) this.#treeRowIndexById.set(row.rowId, index);
		}
		this.#totalTreeRowCount = nextRows.length;
	}

	#upsertContentSources(
		sources: readonly BridgeProductReviewContentSourceDescriptor[],
		affectedItemIds: Set<string>,
	): void {
		for (const source of sources) {
			const existingSource = this.#contentSourceByDescriptorId.get(source.descriptorId);
			if (existingSource !== undefined && !reviewContentSourcesEqual(existingSource, source)) {
				throw new Error('Bridge Review content descriptor identity changed without invalidation.');
			}
			this.#contentSourceByDescriptorId.set(source.descriptorId, source);
			affectedItemIds.add(source.itemId);
		}
	}

	#assertCurrentIdentity(event: BridgeProductReviewMetadataEvent): void {
		if (!this.#matchesIdentity(event)) {
			throw new Error('Bridge Review metadata event does not match the active worker source.');
		}
	}

	#assertCurrentRevision(revision: number): void {
		if (this.#revision !== revision) {
			throw new Error('Bridge Review metadata event does not continue the active revision.');
		}
	}

	#matchesIdentity(event: BridgeProductReviewMetadataEvent): boolean {
		return (
			this.#identity !== null &&
			this.#identity.generation === event.generation &&
			this.#identity.packageId === event.packageId &&
			this.#identity.sourceIdentity === event.sourceIdentity
		);
	}

	#resetProjection(): void {
		this.#contentSourceByDescriptorId.clear();
		this.#extentFactByKey.clear();
		this.#itemIndexById.clear();
		this.#itemMetadataById.clear();
		this.#identity = null;
		this.#itemIdsByIndex = [];
		this.#revision = null;
		this.#totalItemCount = null;
		this.#totalTreeRowCount = null;
		this.#treeRowIndexById.clear();
		this.#treeRows = [];
	}
}

function reviewMetadataIdentity(
	event: BridgeProductReviewMetadataEvent,
): BridgeCommWorkerReviewMetadataIdentity {
	return {
		generation: event.generation,
		packageId: event.packageId,
		sourceIdentity: event.sourceIdentity,
	};
}

function reviewExtentFactKey(fact: BridgeProductReviewExtentFact): string {
	return `${fact.itemId}\u0000${fact.contentRole}`;
}

function compareReviewExtentFacts(
	left: BridgeProductReviewExtentFact,
	right: BridgeProductReviewExtentFact,
): number {
	return reviewExtentFactKey(left).localeCompare(reviewExtentFactKey(right));
}

function reviewContentSourcesEqual(
	left: BridgeProductReviewContentSourceDescriptor,
	right: BridgeProductReviewContentSourceDescriptor,
): boolean {
	return JSON.stringify(left) === JSON.stringify(right);
}

function assertNeverReviewMetadataEvent(_event: never): never {
	throw new Error('Unhandled Bridge Review metadata event.');
}

function assertNeverReviewMetadataOperation(_operation: never): never {
	throw new Error('Unhandled Bridge Review metadata operation.');
}
