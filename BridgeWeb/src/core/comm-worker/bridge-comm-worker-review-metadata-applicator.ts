import { bridgeCommWorkerReviewDisplayPatches } from './bridge-comm-worker-review-display-projection.js';
import type { BridgeCommWorkerReviewMetadataApplyResult } from './bridge-comm-worker-review-metadata-projection.js';
import { BridgeCommWorkerReviewMetadataProjection } from './bridge-comm-worker-review-metadata-projection.js';
import {
	bridgeCommWorkerReviewRuntimeSourceFromMetadataSnapshot,
	bridgeCommWorkerReviewRuntimeSourceItemsFromMetadataSnapshot,
} from './bridge-comm-worker-review-runtime-source-mapper.js';
import {
	isReviewRuntimeSourceExecutableForItem,
	type BridgeCommWorkerReviewRuntimeSource,
} from './bridge-comm-worker-review-source-diff.js';
import type {
	BridgeCommWorkerReviewRowMutation,
	BridgeCommWorkerStore,
} from './bridge-comm-worker-store.js';
import type { BridgeProductReviewMetadataEvent } from './bridge-product-review-metadata-contracts.js';
import type {
	BridgeWorkerReviewDisplayPatch,
	BridgeWorkerReviewSourceDisplayPayload,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

interface MutableBridgeCommWorkerReviewRuntimeSource extends BridgeCommWorkerReviewRuntimeSource {
	readonly contentItems: BridgeCommWorkerReviewRuntimeSource['contentItems'][number][];
	readonly contentRequestDescriptors: BridgeCommWorkerReviewRuntimeSource['contentRequestDescriptors'][number][];
	readonly renderSemantics: BridgeCommWorkerReviewRuntimeSource['renderSemantics'][number][];
	readonly rows: BridgeCommWorkerReviewRuntimeSource['rows'][number][];
}

export interface BridgeCommWorkerReviewMetadataApplication {
	readonly affectedItemIds: readonly string[];
	readonly affectedRowIds: readonly string[];
	readonly completeContentItemIds?: readonly string[];
	readonly completeRowIds?: readonly string[];
	readonly projectionRevision: number;
	readonly removedItemIds: readonly string[];
	readonly reset: boolean;
	readonly rowMutation: BridgeCommWorkerReviewRowMutation;
	readonly source: BridgeCommWorkerReviewRuntimeSource;
	readonly sourceEpoch: number;
	readonly workerDerivationEpoch: number;
}

export function applyBridgeCommWorkerReviewMetadataApplication(props: {
	readonly application: BridgeCommWorkerReviewMetadataApplication;
	readonly createSequence: () => number;
	readonly readRuntimeSource: () => BridgeCommWorkerReviewRuntimeSource;
	readonly scheduleDemandExecution?: (request: {
		readonly affectedItemIds: readonly string[];
		readonly cause: 'reviewMetadata';
		readonly epoch: number;
		readonly sourceChurnRevision?: number;
		readonly store: BridgeCommWorkerStore;
	}) => void;
	readonly scheduleReset?: (request: {
		readonly affectedItemIds: readonly string[];
		readonly cause: 'reviewMetadata';
		readonly epoch: number;
		readonly readReviewRuntimeSource: () => BridgeCommWorkerReviewRuntimeSource;
		readonly store: BridgeCommWorkerStore;
	}) => void;
	readonly scheduleSelectedPreparation: (request: {
		readonly epoch: number;
		readonly itemId: string;
		readonly store: BridgeCommWorkerStore;
	}) => void;
	readonly store: BridgeCommWorkerStore;
	readonly updateRuntimeSource: (source: BridgeCommWorkerReviewRuntimeSource) => void;
}): readonly BridgeWorkerServerToMainMessage[] {
	const { application } = props;
	props.updateRuntimeSource(application.source);
	applyUnavailableReviewMetadataTerminals({
		affectedItemIds: application.affectedItemIds,
		epoch: application.sourceEpoch,
		source: application.source,
		store: props.store,
	});
	if (application.reset && props.scheduleReset !== undefined) {
		props.scheduleReset({
			affectedItemIds: application.affectedItemIds,
			cause: 'reviewMetadata',
			epoch: application.sourceEpoch,
			readReviewRuntimeSource: props.readRuntimeSource,
			store: props.store,
		});
		const resetPatch = props.store.actions.takePendingSlicePatchEvent({
			epoch: application.sourceEpoch,
			sequence: props.createSequence(),
		});
		return resetPatch === null ? [] : [resetPatch];
	}
	const affectedItemIds = new Set(application.affectedItemIds);
	props.store.actions.applyReviewSourceUpdateFact({
		...(application.completeContentItemIds === undefined
			? {}
			: { completeContentItemIds: application.completeContentItemIds }),
		...(application.completeRowIds === undefined
			? {}
			: { completeRowIds: application.completeRowIds }),
		contentItems: application.source.contentItems.filter((item) =>
			affectedItemIds.has(item.itemId),
		),
		epoch: application.sourceEpoch,
		removedContentItemIds: application.removedItemIds,
		resetComplete: false,
		rows: application.completeRowIds === undefined ? [] : application.source.rows,
	});
	if (application.completeRowIds === undefined) {
		props.store.actions.applyReviewRowMutationFact({
			epoch: application.sourceEpoch,
			mutation: application.rowMutation,
		});
	}
	const selectedId = props.store.getState().selectedId;
	if (
		selectedId !== null &&
		affectedItemIds.has(selectedId) &&
		isReviewRuntimeSourceExecutableForItem(application.source, selectedId)
	) {
		const selectedDemand = props.store.actions.applySelectedSourceChurnFact({
			itemId: selectedId,
		});
		if (selectedDemand.selectedDemandEpoch !== null) {
			props.scheduleSelectedPreparation({
				epoch: selectedDemand.selectedDemandEpoch,
				itemId: selectedId,
				store: props.store,
			});
		}
	}
	if (application.affectedItemIds.length > 0) {
		props.scheduleDemandExecution?.({
			affectedItemIds: application.affectedItemIds,
			cause: 'reviewMetadata',
			epoch: application.sourceEpoch,
			sourceChurnRevision: application.projectionRevision,
			store: props.store,
		});
	}
	const slicePatch = props.store.actions.takePendingSlicePatchEvent({
		epoch: application.sourceEpoch,
		sequence: props.createSequence(),
	});
	return slicePatch === null ? [] : [slicePatch];
}

function applyUnavailableReviewMetadataTerminals(props: {
	readonly affectedItemIds: readonly string[];
	readonly epoch: number;
	readonly source: BridgeCommWorkerReviewRuntimeSource;
	readonly store: BridgeCommWorkerStore;
}): void {
	const state = props.store.getState();
	const visibleItemIds = new Set(state.visibleIds);
	const terminalItemIds = props.affectedItemIds.filter(
		(itemId) =>
			!isReviewRuntimeSourceExecutableForItem(props.source, itemId) &&
			(state.paintReadyByItemId.has(itemId) ||
				state.selectedId === itemId ||
				visibleItemIds.has(itemId)),
	);
	if (terminalItemIds.length === 0) return;

	props.store.actions.applyReviewInvalidationFact({
		epoch: props.epoch,
		itemIds: terminalItemIds,
		pathHints: [],
		reason: 'sourceChanged',
		scope: 'items',
	});
	for (const itemId of terminalItemIds) {
		props.store.actions.applyContentTerminalAvailability({
			itemId,
			reason: 'source_reset',
			sourceEpoch: props.epoch,
			state: 'unavailable',
		});
	}
}

export class BridgeCommWorkerReviewMetadataApplicator {
	readonly #applyRuntimeSource: (application: BridgeCommWorkerReviewMetadataApplication) => void;
	readonly #currentWorkerDerivationEpoch: () => number;
	readonly #publishDisplayPatches:
		| ((publication: {
				readonly patches: readonly BridgeWorkerReviewDisplayPatch[];
				readonly workerDerivationEpoch: number;
		  }) => void)
		| undefined;
	readonly #recordIncrementalItemMapping: ((itemCount: number) => void) | undefined;
	readonly #projection = new BridgeCommWorkerReviewMetadataProjection();
	readonly #contentItemIndexById = new Map<string, number>();
	readonly #contentRequestIndexByKey = new Map<string, number>();
	readonly #contentRequestKeysByItemId = new Map<string, Set<string>>();
	readonly #itemSignatureById = new Map<string, string>();
	readonly #directoryIdByPath = new Map<string, string>();
	readonly #renderSemanticsIndexById = new Map<string, number>();
	readonly #rowIndexById = new Map<string, number>();
	readonly #treePathByRowId = new Map<string, string>();
	#runtimeSource: MutableBridgeCommWorkerReviewRuntimeSource = emptyReviewRuntimeSource();
	#sourceEpoch = 0;
	#sourceDisplayStatus: BridgeWorkerReviewSourceDisplayPayload['status'] = 'loading';

	constructor(props: {
		readonly applyRuntimeSource: (application: BridgeCommWorkerReviewMetadataApplication) => void;
		readonly currentWorkerDerivationEpoch: () => number;
		readonly publishDisplayPatches?: (publication: {
			readonly patches: readonly BridgeWorkerReviewDisplayPatch[];
			readonly workerDerivationEpoch: number;
		}) => void;
		readonly recordIncrementalItemMapping?: (itemCount: number) => void;
	}) {
		this.#applyRuntimeSource = props.applyRuntimeSource;
		this.#currentWorkerDerivationEpoch = props.currentWorkerDerivationEpoch;
		this.#publishDisplayPatches = props.publishDisplayPatches;
		this.#recordIncrementalItemMapping = props.recordIncrementalItemMapping;
	}

	apply(event: BridgeProductReviewMetadataEvent, workerDerivationEpoch: number): void {
		if (workerDerivationEpoch !== this.#currentWorkerDerivationEpoch()) return;
		const previousItemIds = [...this.#itemSignatureById.keys()];
		const previousRowIds = this.#runtimeSource.rows.map((row) => row.id);
		const projectionResult = this.#projection.apply(event);
		this.#updateSourceDisplayStatus(event);
		if (projectionResult.reset) {
			const snapshot = this.#projection.snapshot();
			this.#sourceEpoch += 1;
			this.#replaceRuntimeSource(
				bridgeCommWorkerReviewRuntimeSourceFromMetadataSnapshot(snapshot),
				snapshot.treeRows,
			);
			const nextItemIds = new Set(this.#itemSignatureById.keys());
			this.#publishApplication({
				affectedItemIds: [...new Set([...previousItemIds, ...projectionResult.affectedItemIds])],
				affectedRowIds: [
					...new Set([
						...previousRowIds,
						...snapshot.treeRows.map((row) => row.itemId ?? row.rowId),
					]),
				],
				completeContentItemIds: snapshot.orderedItemIds,
				completeRowIds: snapshot.treeRows.map((row) => row.itemId ?? row.rowId),
				event,
				projectionResult,
				removedItemIds: previousItemIds.filter((itemId) => !nextItemIds.has(itemId)),
				reset: true,
				rowMutation: { removedRowIds: [], rowUpserts: [] },
				snapshot,
				workerDerivationEpoch,
			});
			return;
		}

		const candidateItemIds = [...new Set(projectionResult.affectedItemIds)];
		this.#recordIncrementalItemMapping?.(candidateItemIds.length);
		const completesProjection = reviewMetadataEventCompletesProjection(event);
		const snapshot = completesProjection
			? this.#projection.snapshot()
			: this.#projection.snapshotItems(candidateItemIds);
		const itemSource = bridgeCommWorkerReviewRuntimeSourceItemsFromMetadataSnapshot({
			itemIds: candidateItemIds,
			snapshot,
		});
		const nextSignaturesByItemId = reviewRuntimeItemSignatures(itemSource);
		const removedItemIds = candidateItemIds.filter(
			(itemId) => this.#itemSignatureById.has(itemId) && !nextSignaturesByItemId.has(itemId),
		);
		const affectedItemIds = candidateItemIds.filter(
			(itemId) => this.#itemSignatureById.get(itemId) !== nextSignaturesByItemId.get(itemId),
		);
		const rowMutation = this.#applyTreeRowMutation(event);
		if (completesProjection) {
			this.#replaceRuntimeSource(
				bridgeCommWorkerReviewRuntimeSourceFromMetadataSnapshot(snapshot),
				snapshot.treeRows,
			);
		} else {
			this.#upsertRuntimeSourceItems(itemSource, candidateItemIds);
		}
		this.#publishApplication({
			affectedItemIds,
			affectedRowIds: rowMutation.rowUpserts.map((row) => row.id),
			...(completesProjection
				? {
						completeContentItemIds: snapshot.orderedItemIds,
						completeRowIds: snapshot.treeRows.map((row) => row.itemId ?? row.rowId),
					}
				: {}),
			event,
			projectionResult,
			removedItemIds,
			reset: false,
			rowMutation,
			snapshot,
			workerDerivationEpoch,
		});
	}

	#updateSourceDisplayStatus(event: BridgeProductReviewMetadataEvent): void {
		switch (event.eventKind) {
			case 'review.sourceAccepted':
			case 'review.reset':
				this.#sourceDisplayStatus = 'loading';
				break;
			case 'review.invalidated':
				this.#sourceDisplayStatus = 'stale';
				break;
			case 'review.snapshot':
				this.#sourceDisplayStatus = reviewMetadataEventCompletesProjection(event)
					? 'ready'
					: 'loading';
				break;
			case 'review.window':
				if (reviewMetadataEventCompletesProjection(event)) this.#sourceDisplayStatus = 'ready';
				break;
			case 'review.delta':
				break;
			default:
				assertNeverReviewMetadataEvent(event);
		}
	}

	#replaceRuntimeSource(
		source: BridgeCommWorkerReviewRuntimeSource,
		treeRows: readonly {
			readonly isDirectory: boolean;
			readonly itemId: string | null;
			readonly path: string;
			readonly rowId: string;
		}[],
	): void {
		this.#runtimeSource = {
			contentItems: [...source.contentItems],
			contentRequestDescriptors: [...source.contentRequestDescriptors],
			renderSemantics: [...source.renderSemantics],
			rows: [...source.rows],
		};
		this.#contentItemIndexById.clear();
		this.#contentRequestIndexByKey.clear();
		this.#contentRequestKeysByItemId.clear();
		this.#directoryIdByPath.clear();
		this.#itemSignatureById.clear();
		this.#renderSemanticsIndexById.clear();
		this.#rowIndexById.clear();
		this.#treePathByRowId.clear();
		for (const [index, item] of source.contentItems.entries()) {
			this.#contentItemIndexById.set(item.itemId, index);
		}
		for (const [index, descriptor] of source.contentRequestDescriptors.entries()) {
			const key = reviewContentRequestKey(descriptor);
			this.#contentRequestIndexByKey.set(key, index);
			const itemKeys = this.#contentRequestKeysByItemId.get(descriptor.itemId) ?? new Set();
			itemKeys.add(key);
			this.#contentRequestKeysByItemId.set(descriptor.itemId, itemKeys);
		}
		for (const [index, semantics] of source.renderSemantics.entries()) {
			this.#renderSemanticsIndexById.set(semantics.itemId, index);
		}
		for (const [itemId, signature] of reviewRuntimeItemSignatures(source)) {
			this.#itemSignatureById.set(itemId, signature);
		}
		for (const [index, row] of source.rows.entries()) this.#rowIndexById.set(row.id, index);
		for (const treeRow of treeRows) {
			this.#treePathByRowId.set(treeRow.itemId ?? treeRow.rowId, treeRow.path);
			if (treeRow.isDirectory) {
				this.#directoryIdByPath.set(treeRow.path, treeRow.itemId ?? treeRow.rowId);
			}
		}
	}

	#upsertRuntimeSourceItems(
		itemSource: BridgeCommWorkerReviewRuntimeSource,
		candidateItemIds: readonly string[],
	): void {
		const { contentItems, contentRequestDescriptors, renderSemantics } = this.#runtimeSource;
		const nextContentItemIds = new Set(itemSource.contentItems.map((item) => item.itemId));
		const nextContentRequestKeys = new Set(
			itemSource.contentRequestDescriptors.map(reviewContentRequestKey),
		);
		const nextRenderSemanticsItemIds = new Set(
			itemSource.renderSemantics.map((semantics) => semantics.itemId),
		);
		const nextItemSignaturesByItemId = reviewRuntimeItemSignatures(itemSource);
		for (const itemId of candidateItemIds) {
			if (!nextContentItemIds.has(itemId)) {
				removeIndexedValue(contentItems, this.#contentItemIndexById, itemId, (item) => item.itemId);
			}
			for (const existingKey of this.#contentRequestKeysByItemId.get(itemId) ?? []) {
				if (nextContentRequestKeys.has(existingKey)) continue;
				removeIndexedValue(
					contentRequestDescriptors,
					this.#contentRequestIndexByKey,
					existingKey,
					reviewContentRequestKey,
				);
				this.#contentRequestKeysByItemId.get(itemId)?.delete(existingKey);
			}
			if (this.#contentRequestKeysByItemId.get(itemId)?.size === 0) {
				this.#contentRequestKeysByItemId.delete(itemId);
			}
			if (!nextRenderSemanticsItemIds.has(itemId)) {
				removeIndexedValue(
					renderSemantics,
					this.#renderSemanticsIndexById,
					itemId,
					(semantics) => semantics.itemId,
				);
			}
		}
		for (const item of itemSource.contentItems) {
			upsertIndexedValue(contentItems, this.#contentItemIndexById, item.itemId, item);
		}
		for (const descriptor of itemSource.contentRequestDescriptors) {
			const key = reviewContentRequestKey(descriptor);
			upsertIndexedValue(
				contentRequestDescriptors,
				this.#contentRequestIndexByKey,
				key,
				descriptor,
			);
			const itemKeys = this.#contentRequestKeysByItemId.get(descriptor.itemId) ?? new Set();
			itemKeys.add(key);
			this.#contentRequestKeysByItemId.set(descriptor.itemId, itemKeys);
		}
		for (const semantics of itemSource.renderSemantics) {
			upsertIndexedValue(
				renderSemantics,
				this.#renderSemanticsIndexById,
				semantics.itemId,
				semantics,
			);
		}
		for (const [itemId, signature] of nextItemSignaturesByItemId) {
			this.#itemSignatureById.set(itemId, signature);
		}
		for (const itemId of candidateItemIds) {
			if (!nextItemSignaturesByItemId.has(itemId)) this.#itemSignatureById.delete(itemId);
		}
	}

	#applyTreeRowMutation(
		event: BridgeProductReviewMetadataEvent,
	): BridgeCommWorkerReviewRowMutation {
		if (event.eventKind === 'review.window') {
			return {
				removedRowIds: [],
				rowUpserts: event.treeRows.map((treeRow, offset) =>
					this.#upsertTreeRow(treeRow, event.treeWindow.startIndex + offset),
				),
			};
		}
		if (event.eventKind !== 'review.delta') return { removedRowIds: [], rowUpserts: [] };
		const removedRowIds: string[] = [];
		const rowUpserts = new Map<string, BridgeCommWorkerReviewRuntimeSource['rows'][number]>();
		for (const operation of event.operations) {
			if (operation.operationKind !== 'spliceTreeRows') continue;
			const removedEndIndex = operation.startIndex + operation.deleteCount;
			for (const row of this.#runtimeSource.rows.slice()) {
				if (row.index < operation.startIndex || row.index >= removedEndIndex) continue;
				removedRowIds.push(row.id);
				removeIndexedValue(
					this.#runtimeSource.rows,
					this.#rowIndexById,
					row.id,
					(value) => value.id,
				);
				const removedPath = this.#treePathByRowId.get(row.id);
				if (removedPath !== undefined && this.#directoryIdByPath.get(removedPath) === row.id) {
					this.#directoryIdByPath.delete(removedPath);
				}
				this.#treePathByRowId.delete(row.id);
			}
			const indexDelta = operation.rows.length - operation.deleteCount;
			if (indexDelta !== 0) {
				for (const row of this.#runtimeSource.rows.slice()) {
					if (row.index < removedEndIndex) continue;
					const shiftedRow = { ...row, index: row.index + indexDelta };
					upsertIndexedValue(this.#runtimeSource.rows, this.#rowIndexById, row.id, shiftedRow);
					rowUpserts.set(row.id, shiftedRow);
				}
			}
			for (const [offset, treeRow] of operation.rows.entries()) {
				const row = this.#upsertTreeRow(treeRow, operation.startIndex + offset);
				rowUpserts.set(row.id, row);
			}
		}
		return { removedRowIds, rowUpserts: [...rowUpserts.values()] };
	}

	#upsertTreeRow(
		treeRow: {
			readonly isDirectory: boolean;
			readonly itemId: string | null;
			readonly path: string;
			readonly rowId: string;
		},
		index: number,
	): MutableBridgeCommWorkerReviewRuntimeSource['rows'][number] {
		const rowId = treeRow.itemId ?? treeRow.rowId;
		if (treeRow.isDirectory) this.#directoryIdByPath.set(treeRow.path, rowId);
		this.#treePathByRowId.set(rowId, treeRow.path);
		const parentPath = reviewTreeParentPath(treeRow.path);
		const row = {
			id: rowId,
			index,
			parentId: parentPath === null ? null : (this.#directoryIdByPath.get(parentPath) ?? null),
		};
		upsertIndexedValue(this.#runtimeSource.rows, this.#rowIndexById, rowId, row);
		return row;
	}

	#publishApplication(props: {
		readonly affectedItemIds: readonly string[];
		readonly affectedRowIds: readonly string[];
		readonly completeContentItemIds?: readonly string[];
		readonly completeRowIds?: readonly string[];
		readonly event: BridgeProductReviewMetadataEvent;
		readonly projectionResult: BridgeCommWorkerReviewMetadataApplyResult;
		readonly removedItemIds: readonly string[];
		readonly reset: boolean;
		readonly rowMutation: BridgeCommWorkerReviewRowMutation;
		readonly snapshot: ReturnType<BridgeCommWorkerReviewMetadataProjection['snapshot']>;
		readonly workerDerivationEpoch: number;
	}): void {
		this.#applyRuntimeSource({
			affectedItemIds: props.affectedItemIds,
			affectedRowIds: props.affectedRowIds,
			...(props.completeContentItemIds === undefined
				? {}
				: { completeContentItemIds: props.completeContentItemIds }),
			...(props.completeRowIds === undefined ? {} : { completeRowIds: props.completeRowIds }),
			projectionRevision: props.projectionResult.projectionRevision,
			removedItemIds: props.removedItemIds,
			reset: props.reset,
			rowMutation: props.rowMutation,
			source: this.#runtimeSource,
			sourceEpoch: this.#sourceEpoch,
			workerDerivationEpoch: props.workerDerivationEpoch,
		});
		this.#publishDisplayPatches?.({
			patches: bridgeCommWorkerReviewDisplayPatches({
				event: props.event,
				projectionResult: props.projectionResult,
				snapshot: props.snapshot,
				sourceStatus: this.#sourceDisplayStatus,
			}),
			workerDerivationEpoch: props.workerDerivationEpoch,
		});
	}
}

function upsertIndexedValue<TKey, TValue>(
	values: TValue[],
	indexByKey: Map<TKey, number>,
	key: TKey,
	value: TValue,
): void {
	const existingIndex = indexByKey.get(key);
	if (existingIndex === undefined) {
		indexByKey.set(key, values.length);
		values.push(value);
		return;
	}
	values[existingIndex] = value;
}

function removeIndexedValue<TKey, TValue>(
	values: TValue[],
	indexByKey: Map<TKey, number>,
	key: TKey,
	keyForValue: (value: TValue) => TKey,
): void {
	const removedIndex = indexByKey.get(key);
	if (removedIndex === undefined) return;
	const lastValue = values.pop();
	indexByKey.delete(key);
	if (lastValue === undefined || removedIndex === values.length) return;
	values[removedIndex] = lastValue;
	indexByKey.set(keyForValue(lastValue), removedIndex);
}

function reviewRuntimeItemSignatures(
	source: BridgeCommWorkerReviewRuntimeSource,
): ReadonlyMap<string, string> {
	type ReviewRuntimeItemSignatureInput = {
		contentItem: BridgeCommWorkerReviewRuntimeSource['contentItems'][number] | null;
		contentRequests: BridgeCommWorkerReviewRuntimeSource['contentRequestDescriptors'][number][];
		renderSemantics: BridgeCommWorkerReviewRuntimeSource['renderSemantics'][number] | null;
	};
	const signaturesByItemId = new Map<string, ReviewRuntimeItemSignatureInput>();
	const signatureForItem = (itemId: string): ReviewRuntimeItemSignatureInput => {
		const existing = signaturesByItemId.get(itemId);
		if (existing !== undefined) return existing;
		const created = { contentItem: null, contentRequests: [], renderSemantics: null };
		signaturesByItemId.set(itemId, created);
		return created;
	};
	for (const item of source.contentItems) signatureForItem(item.itemId).contentItem = item;
	for (const descriptor of source.contentRequestDescriptors) {
		signatureForItem(descriptor.itemId).contentRequests.push(descriptor);
	}
	for (const semantics of source.renderSemantics) {
		signatureForItem(semantics.itemId).renderSemantics = semantics;
	}
	return new Map(
		[...signaturesByItemId].map(([itemId, signature]) => [itemId, JSON.stringify(signature)]),
	);
}

function reviewContentRequestKey(
	descriptor: BridgeCommWorkerReviewRuntimeSource['contentRequestDescriptors'][number],
): string {
	return `${descriptor.itemId}\u0000${descriptor.role}`;
}

function reviewTreeParentPath(path: string): string | null {
	const separatorIndex = path.lastIndexOf('/');
	return separatorIndex < 0 ? null : path.slice(0, separatorIndex);
}

function reviewMetadataEventCompletesProjection(event: BridgeProductReviewMetadataEvent): boolean {
	return (
		(event.eventKind === 'review.snapshot' || event.eventKind === 'review.window') &&
		event.itemWindow.finalWindow &&
		event.treeWindow.finalWindow
	);
}

function assertNeverReviewMetadataEvent(event: never): never {
	throw new Error(`Unhandled Review metadata applicator event: ${JSON.stringify(event)}`);
}

function emptyReviewRuntimeSource(): MutableBridgeCommWorkerReviewRuntimeSource {
	return { contentItems: [], contentRequestDescriptors: [], renderSemantics: [], rows: [] };
}
