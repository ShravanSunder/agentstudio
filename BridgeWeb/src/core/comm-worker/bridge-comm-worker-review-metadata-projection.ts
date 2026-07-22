import { reviewMetadataSnapshotEventFromCompleteSnapshot } from './bridge-comm-worker-review-publication-transaction.js';
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
type ReviewMetadataSnapshotEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.snapshot' }
>;

export interface BridgeCommWorkerReviewMetadataIdentity {
	readonly generation: number;
	readonly packageId: string;
	readonly publicationId: string;
	readonly sourceIdentity: string;
}

export interface BridgeCommWorkerReviewMetadataSnapshot {
	readonly baseEndpoint: ReviewMetadataSnapshotEvent['baseEndpoint'] | null;
	readonly contentSources: readonly BridgeProductReviewContentSourceDescriptor[];
	readonly extentFacts: readonly BridgeProductReviewExtentFact[];
	readonly headEndpoint: ReviewMetadataSnapshotEvent['headEndpoint'] | null;
	readonly identity: BridgeCommWorkerReviewMetadataIdentity | null;
	readonly itemMetadata: readonly BridgeProductReviewItemMetadata[];
	readonly orderedItemIds: readonly string[];
	readonly query: ReviewMetadataSnapshotEvent['query'] | null;
	readonly revision: number | null;
	readonly summary: ReviewMetadataPayloadEvent['summary'] | null;
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
	#baseEndpoint: ReviewMetadataSnapshotEvent['baseEndpoint'] | null = null;
	readonly #contentSourceByDescriptorId = new Map<
		string,
		BridgeProductReviewContentSourceDescriptor
	>();
	readonly #contentSourceDescriptorIdsByItemId = new Map<string, Set<string>>();
	readonly #extentFactByKey = new Map<string, BridgeProductReviewExtentFact>();
	readonly #extentFactKeysByItemId = new Map<string, Set<string>>();
	readonly #itemIndexById = new Map<string, number>();
	readonly #itemMetadataById = new Map<string, BridgeProductReviewItemMetadata>();
	#headEndpoint: ReviewMetadataSnapshotEvent['headEndpoint'] | null = null;
	#identity: BridgeCommWorkerReviewMetadataIdentity | null = null;
	#itemFinalWindowReceived = false;
	#itemIdsByIndex: Array<string | undefined> = [];
	#projectionRevision = 0;
	#query: ReviewMetadataSnapshotEvent['query'] | null = null;
	#revision: number | null = null;
	#summary: ReviewMetadataPayloadEvent['summary'] | null = null;
	#totalItemCount: number | null = null;
	#totalTreeRowCount: number | null = null;
	#treeFinalWindowReceived = false;
	readonly #treeRowIndexById = new Map<string, number>();
	#treeRows: Array<BridgeProductReviewTreeRow | undefined> = [];

	apply(
		event: BridgeProductReviewMetadataEvent,
		minimumPriorProjectionRevision = 0,
	): BridgeCommWorkerReviewMetadataApplyResult {
		if (
			!Number.isSafeInteger(minimumPriorProjectionRevision) ||
			minimumPriorProjectionRevision < 0
		) {
			throw new Error('Bridge Review projection revision floor must be nonnegative.');
		}
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
				this.#baseEndpoint = event.baseEndpoint;
				this.#headEndpoint = event.headEndpoint;
				this.#query = event.query;
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
				if (this.#identity !== null) this.#assertCurrentIdentity(event);
				this.#resetProjection();
				this.#identity = reviewMetadataIdentity(event);
				this.#revision = event.revision;
				reset = true;
				break;
			default:
				assertNeverReviewMetadataEvent(event);
		}
		this.#projectionRevision =
			Math.max(this.#projectionRevision, minimumPriorProjectionRevision) + 1;
		return {
			affectedItemIds: [...affectedItemIds],
			invalidation,
			projectionRevision: this.#projectionRevision,
			reset,
		};
	}

	cloneComplete(): BridgeCommWorkerReviewMetadataProjection {
		this.assertCompleteFinalBarrier();
		const clone = new BridgeCommWorkerReviewMetadataProjection();
		clone.apply(reviewMetadataSnapshotEventFromCompleteSnapshot(this.snapshot()));
		clone.#projectionRevision = this.#projectionRevision;
		return clone;
	}

	assertCompleteFinalBarrier(): void {
		if (!this.#itemFinalWindowReceived || !this.#treeFinalWindowReceived) {
			throw new Error('Bridge Review metadata final barrier has not received both final windows.');
		}
		if (!this.isComplete()) {
			throw new Error(
				'Bridge Review metadata final barrier is incomplete or contains ordered holes.',
			);
		}
	}

	isComplete(): boolean {
		return (
			this.#itemFinalWindowReceived &&
			this.#treeFinalWindowReceived &&
			this.#baseEndpoint !== null &&
			this.#headEndpoint !== null &&
			this.#identity !== null &&
			this.#query !== null &&
			this.#revision !== null &&
			this.#summary !== null &&
			this.#totalItemCount !== null &&
			this.#itemIdsByIndex.length === this.#totalItemCount &&
			everyOrderedIndexIsDefined(this.#itemIdsByIndex) &&
			this.#itemIdsByIndex.every(
				(itemId) => itemId !== undefined && this.#itemMetadataById.has(itemId),
			) &&
			this.#totalTreeRowCount !== null &&
			this.#treeRows.length === this.#totalTreeRowCount &&
			everyOrderedIndexIsDefined(this.#treeRows)
		);
	}

	hasFinalBarrier(): boolean {
		return this.#itemFinalWindowReceived && this.#treeFinalWindowReceived;
	}

	matchesEvent(event: BridgeProductReviewMetadataEvent): boolean {
		return this.#matchesIdentity(event) && this.#revision === event.revision;
	}

	canApplySuccessorDelta(event: ReviewMetadataDeltaEvent): boolean {
		return (
			this.#identity !== null &&
			this.#identity.generation === event.generation &&
			this.#identity.packageId === event.packageId &&
			this.#identity.publicationId !== event.publicationId &&
			this.#identity.sourceIdentity === event.sourceIdentity &&
			this.#revision === event.fromRevision
		);
	}

	snapshot(): BridgeCommWorkerReviewMetadataSnapshot {
		const orderedItemIds = this.#itemIdsByIndex.filter(
			(itemId): itemId is string => itemId !== undefined,
		);
		return {
			baseEndpoint: this.#baseEndpoint,
			contentSources: [...this.#contentSourceByDescriptorId.values()].toSorted((left, right) =>
				left.descriptorId.localeCompare(right.descriptorId),
			),
			extentFacts: [...this.#extentFactByKey.values()].toSorted(compareReviewExtentFacts),
			headEndpoint: this.#headEndpoint,
			identity: this.#identity,
			itemMetadata: orderedItemIds.flatMap((itemId) => {
				const item = this.#itemMetadataById.get(itemId);
				return item === undefined ? [] : [item];
			}),
			orderedItemIds,
			query: this.#query,
			revision: this.#revision,
			summary: this.#summary,
			totalItemCount: this.#totalItemCount,
			totalTreeRowCount: this.#totalTreeRowCount,
			treeRows: this.#treeRows.filter(
				(row): row is BridgeProductReviewTreeRow => row !== undefined,
			),
		};
	}

	snapshotItems(itemIds: readonly string[]): BridgeCommWorkerReviewMetadataSnapshot {
		const uniqueItemIds = [...new Set(itemIds)];
		return {
			baseEndpoint: this.#baseEndpoint,
			contentSources: uniqueItemIds.flatMap((itemId) =>
				[...(this.#contentSourceDescriptorIdsByItemId.get(itemId) ?? [])].flatMap(
					(descriptorId) => {
						const source = this.#contentSourceByDescriptorId.get(descriptorId);
						return source === undefined ? [] : [source];
					},
				),
			),
			extentFacts: uniqueItemIds.flatMap((itemId) =>
				[...(this.#extentFactKeysByItemId.get(itemId) ?? [])].flatMap((factKey) => {
					const fact = this.#extentFactByKey.get(factKey);
					return fact === undefined ? [] : [fact];
				}),
			),
			headEndpoint: this.#headEndpoint,
			identity: this.#identity,
			itemMetadata: uniqueItemIds.flatMap((itemId) => {
				const item = this.#itemMetadataById.get(itemId);
				return item === undefined ? [] : [item];
			}),
			orderedItemIds: uniqueItemIds.filter((itemId) => this.#itemMetadataById.has(itemId)),
			query: this.#query,
			revision: this.#revision,
			summary: this.#summary,
			totalItemCount: this.#totalItemCount,
			totalTreeRowCount: this.#totalTreeRowCount,
			treeRows: [],
		};
	}

	#applyPayload(event: ReviewMetadataPayloadEvent, affectedItemIds: Set<string>): void {
		this.#summary = event.summary;
		this.#itemFinalWindowReceived ||= event.itemWindow.finalWindow;
		this.#treeFinalWindowReceived ||= event.treeWindow.finalWindow;
		this.#applyItemWindow(event, affectedItemIds);
		this.#applyTreeWindow(event);
		for (const item of event.itemMetadata) {
			this.#itemMetadataById.set(item.itemId, item);
			affectedItemIds.add(item.itemId);
		}
		this.#upsertContentSources(event.contentSources, affectedItemIds);
		for (const fact of event.extentFacts) {
			this.#upsertExtentFact(fact);
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
		if (!this.canApplySuccessorDelta(event)) {
			throw new Error(
				'Bridge Review metadata delta does not identify the active publication predecessor.',
			);
		}
		this.#assertCurrentRevision(event.fromRevision);
		this.#upsertContentSources(event.contentSources, affectedItemIds);
		this.#summary = event.summary;
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
						this.#upsertExtentFact(fact);
						affectedItemIds.add(fact.itemId);
					}
					break;
				case 'invalidateContentSources':
					for (const descriptorId of operation.descriptorIds) {
						const source = this.#contentSourceByDescriptorId.get(descriptorId);
						if (source !== undefined) affectedItemIds.add(source.itemId);
						if (source !== undefined) {
							this.#contentSourceDescriptorIdsByItemId.get(source.itemId)?.delete(descriptorId);
						}
						this.#contentSourceByDescriptorId.delete(descriptorId);
					}
					break;
				default:
					assertNeverReviewMetadataOperation(operation);
			}
		}
		this.#identity = reviewMetadataIdentity(event);
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
		for (const itemId of itemIds) this.#contentSourceDescriptorIdsByItemId.delete(itemId);
		for (const [factKey, fact] of this.#extentFactByKey) {
			if (removedItemIds.has(fact.itemId)) this.#extentFactByKey.delete(factKey);
		}
		for (const itemId of itemIds) this.#extentFactKeysByItemId.delete(itemId);
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
			const descriptorIds =
				this.#contentSourceDescriptorIdsByItemId.get(source.itemId) ?? new Set<string>();
			descriptorIds.add(source.descriptorId);
			this.#contentSourceDescriptorIdsByItemId.set(source.itemId, descriptorIds);
			affectedItemIds.add(source.itemId);
		}
	}

	#upsertExtentFact(fact: BridgeProductReviewExtentFact): void {
		const factKey = reviewExtentFactKey(fact);
		this.#extentFactByKey.set(factKey, fact);
		const factKeys = this.#extentFactKeysByItemId.get(fact.itemId) ?? new Set<string>();
		factKeys.add(factKey);
		this.#extentFactKeysByItemId.set(fact.itemId, factKeys);
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
			this.#identity.publicationId === event.publicationId &&
			this.#identity.sourceIdentity === event.sourceIdentity
		);
	}

	#resetProjection(): void {
		this.#baseEndpoint = null;
		this.#contentSourceByDescriptorId.clear();
		this.#contentSourceDescriptorIdsByItemId.clear();
		this.#extentFactByKey.clear();
		this.#extentFactKeysByItemId.clear();
		this.#itemIndexById.clear();
		this.#itemMetadataById.clear();
		this.#headEndpoint = null;
		this.#identity = null;
		this.#itemFinalWindowReceived = false;
		this.#itemIdsByIndex = [];
		this.#query = null;
		this.#revision = null;
		this.#summary = null;
		this.#totalItemCount = null;
		this.#totalTreeRowCount = null;
		this.#treeFinalWindowReceived = false;
		this.#treeRowIndexById.clear();
		this.#treeRows = [];
	}
}

function everyOrderedIndexIsDefined(values: readonly unknown[]): boolean {
	for (let index = 0; index < values.length; index += 1) {
		if (values[index] === undefined) return false;
	}
	return true;
}

function reviewMetadataIdentity(
	event: BridgeProductReviewMetadataEvent,
): BridgeCommWorkerReviewMetadataIdentity {
	return {
		generation: event.generation,
		packageId: event.packageId,
		publicationId: event.publicationId,
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
