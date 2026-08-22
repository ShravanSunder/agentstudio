import {
	compareReviewMetadataLineages,
	type ReviewMetadataLineage,
} from './bridge-comm-worker-review-publication-transaction.js';
import type {
	BridgeMainCodeViewItem,
	BridgeMainCodeViewItemPatch,
	BridgeMainReviewTreeDisplayRow,
} from './bridge-main-render-snapshot-store.js';
import {
	applyReviewDisplayPatchEventInPlace,
	bridgeMainReviewRenderCopyInvalidationItemIds,
	invalidateBridgeMainReviewRenderCopies,
	reconcileBridgeMainReviewRenderCopyPaths,
	type MutableBridgeMainRenderSnapshot,
} from './bridge-main-review-display-state.js';
import type {
	BridgeWorkerReviewDisplayPatchEvent,
	BridgeWorkerSlicePatch,
} from './bridge-worker-contracts.js';

export type BridgeMainReviewPublicationIdentity = ReviewMetadataLineage;
export type BridgeMainReviewCandidateRole = 'installing' | 'provisional' | 'updateReady';
export interface BridgeMainReviewCandidatePresentation {
	readonly affectedStableFileIdentities: readonly string[];
	readonly identity: BridgeMainReviewPublicationIdentity;
	readonly role: BridgeMainReviewCandidateRole;
}
export interface BridgeMainReviewRefreshPresentation {
	readonly activeIdentity: BridgeMainReviewPublicationIdentity | null;
	readonly candidate: BridgeMainReviewCandidatePresentation | null;
}
export type BridgeMainReviewCandidateWorkerPatch = Exclude<
	BridgeWorkerSlicePatch,
	{ readonly slice: 'selection' | 'viewport' }
>;
export interface BridgeMainReviewCandidateSnapshotUpdate {
	readonly codeViewItemPatches?: readonly BridgeMainCodeViewItemPatch[];
	readonly identity: BridgeMainReviewPublicationIdentity;
	readonly workerPatches?: readonly BridgeMainReviewCandidateWorkerPatch[];
}
export interface BridgeMainReviewCandidateStore {
	readonly getReviewRefreshPresentation: () => BridgeMainReviewRefreshPresentation;
	readonly subscribeReviewRefreshPresentation: (listener: () => void) => () => void;
	readonly setReviewCandidateCodeViewItem: (props: {
		readonly identity: BridgeMainReviewPublicationIdentity;
		readonly itemId: string;
		readonly item: BridgeMainCodeViewItem;
	}) => boolean;
	readonly stageReviewCandidateDisplayEvent: (props: {
		readonly event: BridgeWorkerReviewDisplayPatchEvent;
		readonly identity: BridgeMainReviewPublicationIdentity;
	}) => boolean;
	readonly applyReviewCandidateSnapshotUpdate: (
		update: BridgeMainReviewCandidateSnapshotUpdate,
	) => boolean;
	readonly markReviewCandidateReady: (props: {
		readonly affectedStableFileIdentities: readonly string[];
		readonly identity: BridgeMainReviewPublicationIdentity;
		readonly role: BridgeMainReviewCandidateRole;
	}) => boolean;
	readonly promoteReviewCandidate: (identity: BridgeMainReviewPublicationIdentity) => boolean;
	readonly discardReviewCandidate: (identity?: BridgeMainReviewPublicationIdentity) => boolean;
}
export interface MutableBridgeMainReviewCandidateBank {
	affectedStableFileIdentities: readonly string[];
	readonly identity: BridgeMainReviewPublicationIdentity;
	readonly reviewItemIndexById: Map<string, number>;
	readonly reviewTreeRowById: Map<string, BridgeMainReviewTreeDisplayRow>;
	role: BridgeMainReviewCandidateRole;
	snapshot: MutableBridgeMainRenderSnapshot;
}

export class BridgeMainReviewCandidateBankOwner {
	#activeIdentity: BridgeMainReviewPublicationIdentity | null = null;
	#candidate: MutableBridgeMainReviewCandidateBank | null = null;
	#presentation: BridgeMainReviewRefreshPresentation = presentation(null, null);

	get currentPresentation(): BridgeMainReviewRefreshPresentation {
		return this.#presentation;
	}

	stage(props: {
		readonly activeSnapshot: MutableBridgeMainRenderSnapshot;
		readonly event: BridgeWorkerReviewDisplayPatchEvent;
		readonly identity: BridgeMainReviewPublicationIdentity;
	}): boolean {
		if (this.#activeIdentity !== null && !isNewer(props.identity, this.#activeIdentity))
			return false;
		let candidate = this.#candidate;
		let presentationChanged = false;
		if (candidate === null) {
			candidate = cloneCandidate(props.activeSnapshot, props.identity);
			presentationChanged = true;
		} else if (!isExact(props.identity, candidate.identity)) {
			if (!isNewer(props.identity, candidate.identity)) return false;
			if (candidate.role === 'installing') return false;
			candidate = cloneCandidate(props.activeSnapshot, props.identity);
			presentationChanged = true;
		}
		const replacesWorkerDerivationEpoch =
			candidate.snapshot.reviewDisplayFreshness !== null &&
			props.event.epoch > candidate.snapshot.reviewDisplayFreshness.epoch;
		const effect = applyReviewDisplayPatchEventInPlace({
			event: props.event,
			reviewItemIndexById: candidate.reviewItemIndexById,
			reviewTreeRowById: candidate.reviewTreeRowById,
			snapshot: candidate.snapshot,
		});
		if (effect === null) return false;
		this.#candidate = candidate;
		const invalidation = invalidateBridgeMainReviewRenderCopies({
			itemIds: bridgeMainReviewRenderCopyInvalidationItemIds({
				currentItemsById: candidate.snapshot.reviewItemById,
				previousItemsById: effect.previousItemsById,
				replacesWorkerDerivationEpoch,
			}),
			snapshot: candidate.snapshot,
		});
		candidate.snapshot = reconcileBridgeMainReviewRenderCopyPaths({
			currentItemsById: candidate.snapshot.reviewItemById,
			previousItemsById: effect.previousItemsById,
			snapshot: invalidation.snapshot,
		}).snapshot;
		if (presentationChanged) this.#refresh();
		return true;
	}

	update(
		identity: BridgeMainReviewPublicationIdentity,
		apply: (
			snapshot: MutableBridgeMainRenderSnapshot,
			containsItem: (itemId: string) => boolean,
		) => MutableBridgeMainRenderSnapshot | null,
	): boolean {
		if (this.#candidate === null || !isExact(identity, this.#candidate.identity)) return false;
		const nextSnapshot = apply(
			this.#candidate.snapshot,
			(itemId): boolean => this.#candidate?.reviewItemIndexById.has(itemId) === true,
		);
		if (nextSnapshot === null) return false;
		this.#candidate.snapshot = nextSnapshot;
		return true;
	}

	markReady(props: {
		readonly affectedStableFileIdentities: readonly string[];
		readonly identity: BridgeMainReviewPublicationIdentity;
		readonly role: BridgeMainReviewCandidateRole;
	}): boolean {
		if (
			this.#candidate === null ||
			!isExact(props.identity, this.#candidate.identity) ||
			(this.#candidate.role === 'installing' && props.role !== 'installing') ||
			this.#candidate.snapshot.reviewSourceSlice?.status !== 'ready'
		)
			return false;
		this.#candidate.role = props.role;
		this.#candidate.affectedStableFileIdentities = [...new Set(props.affectedStableFileIdentities)];
		this.#refresh();
		return true;
	}

	promote(
		identity: BridgeMainReviewPublicationIdentity,
	): MutableBridgeMainReviewCandidateBank | null {
		if (
			this.#candidate === null ||
			!isExact(identity, this.#candidate.identity) ||
			this.#candidate.snapshot.reviewSourceSlice?.status !== 'ready'
		)
			return null;
		const candidate = this.#candidate;
		this.#activeIdentity = candidate.identity;
		this.#candidate = null;
		this.#refresh();
		return candidate;
	}

	discard(identity?: BridgeMainReviewPublicationIdentity): boolean {
		if (
			this.#candidate === null ||
			(identity !== undefined && !isExact(identity, this.#candidate.identity))
		)
			return false;
		this.#candidate = null;
		this.#refresh();
		return true;
	}

	dispose(): void {
		this.#activeIdentity = null;
		this.#candidate = null;
		this.#refresh();
	}

	#refresh(): void {
		this.#presentation = presentation(this.#activeIdentity, this.#candidate);
	}
}

export function mergeBridgeMainReviewCandidateSnapshot(props: {
	readonly activeSnapshot: MutableBridgeMainRenderSnapshot;
	readonly candidateSnapshot: MutableBridgeMainRenderSnapshot;
}): MutableBridgeMainRenderSnapshot {
	const oldIds = Object.keys(props.activeSnapshot.reviewItemById);
	const newIds = Object.keys(props.candidateSnapshot.reviewItemById);
	const selectedId = props.activeSnapshot.selectionSlice.selectedItemId;
	const selectionSlice =
		selectedId === null || props.candidateSnapshot.reviewItemById[selectedId] !== undefined
			? props.activeSnapshot.selectionSlice
			: { selectedItemId: null, source: null };
	const viewportValid = props.activeSnapshot.viewportSlice.visibleItemIds.every(
		(itemId): boolean => props.candidateSnapshot.reviewItemById[itemId] !== undefined,
	);
	const { reviewComparison: _oldComparison, ...nonReviewChrome } =
		props.activeSnapshot.panelChromeSlice;
	const nextComparison = props.candidateSnapshot.panelChromeSlice.reviewComparison;
	return {
		...props.activeSnapshot,
		codeViewItemsById: mergeRecords(
			props.activeSnapshot.codeViewItemsById,
			props.candidateSnapshot.codeViewItemsById,
			oldIds,
			newIds,
		),
		contentAvailabilityById: mergeRecords(
			props.activeSnapshot.contentAvailabilityById,
			props.candidateSnapshot.contentAvailabilityById,
			oldIds,
			newIds,
		),
		panelChromeSlice:
			nextComparison === undefined
				? nonReviewChrome
				: { ...nonReviewChrome, reviewComparison: nextComparison },
		reviewDisplayFreshness: props.candidateSnapshot.reviewDisplayFreshness,
		reviewItemById: props.candidateSnapshot.reviewItemById,
		reviewItemIdsByIndex: props.candidateSnapshot.reviewItemIdsByIndex,
		reviewSourceSlice: props.candidateSnapshot.reviewSourceSlice,
		reviewTreeRowsByIndex: props.candidateSnapshot.reviewTreeRowsByIndex,
		rowPaintById: mergeRecords(
			props.activeSnapshot.rowPaintById,
			props.candidateSnapshot.rowPaintById,
			oldIds,
			newIds,
		),
		selectionSlice,
		viewportSlice: viewportValid
			? props.activeSnapshot.viewportSlice
			: { firstVisibleIndex: 0, lastVisibleIndex: 0, visibleItemIds: [] },
	};
}

function cloneCandidate(
	snapshot: MutableBridgeMainRenderSnapshot,
	identity: BridgeMainReviewPublicationIdentity,
): MutableBridgeMainReviewCandidateBank {
	return {
		affectedStableFileIdentities: [],
		identity,
		reviewItemIndexById: itemIndex(snapshot.reviewItemIdsByIndex),
		reviewTreeRowById: rowIndex(snapshot.reviewTreeRowsByIndex),
		role: 'provisional',
		snapshot: {
			...snapshot,
			codeViewItemsById: { ...snapshot.codeViewItemsById },
			contentAvailabilityById: { ...snapshot.contentAvailabilityById },
			panelChromeSlice: { ...snapshot.panelChromeSlice },
			reviewItemById: { ...snapshot.reviewItemById },
			reviewItemIdsByIndex: [...snapshot.reviewItemIdsByIndex],
			reviewTreeRowsByIndex: [...snapshot.reviewTreeRowsByIndex],
			rowPaintById: { ...snapshot.rowPaintById },
		},
	};
}
function isExact(
	left: BridgeMainReviewPublicationIdentity,
	right: BridgeMainReviewPublicationIdentity,
): boolean {
	return compareReviewMetadataLineages(left, right) === 'same';
}
function isNewer(
	candidate: BridgeMainReviewPublicationIdentity,
	current: BridgeMainReviewPublicationIdentity,
): boolean {
	return compareReviewMetadataLineages(candidate, current) === 'newer';
}
function presentation(
	activeIdentity: BridgeMainReviewPublicationIdentity | null,
	candidate: MutableBridgeMainReviewCandidateBank | null,
): BridgeMainReviewRefreshPresentation {
	return {
		activeIdentity,
		candidate:
			candidate === null
				? null
				: {
						affectedStableFileIdentities: [...candidate.affectedStableFileIdentities],
						identity: candidate.identity,
						role: candidate.role,
					},
	};
}
function mergeRecords<T>(
	active: Readonly<Record<string, T>>,
	candidate: Readonly<Record<string, T>>,
	oldIds: readonly string[],
	newIds: readonly string[],
): Record<string, T> {
	const result = { ...active };
	for (const id of oldIds) delete result[id];
	for (const id of newIds) {
		const value = candidate[id];
		if (value !== undefined) result[id] = value;
	}
	return result;
}
function itemIndex(ids: readonly (string | null)[]): Map<string, number> {
	const result = new Map<string, number>();
	for (const [index, id] of ids.entries()) if (id !== null) result.set(id, index);
	return result;
}
function rowIndex(
	rows: readonly (BridgeMainReviewTreeDisplayRow | null)[],
): Map<string, BridgeMainReviewTreeDisplayRow> {
	const result = new Map<string, BridgeMainReviewTreeDisplayRow>();
	for (const row of rows) if (row !== null) result.set(row.rowId, row);
	return result;
}
