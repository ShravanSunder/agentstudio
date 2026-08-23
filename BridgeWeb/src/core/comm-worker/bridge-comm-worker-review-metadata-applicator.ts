import { bridgeCommWorkerReviewDisplayPatches } from './bridge-comm-worker-review-display-projection.js';
import type { BridgeCommWorkerReviewMetadataApplyResult } from './bridge-comm-worker-review-metadata-projection.js';
import { BridgeCommWorkerReviewMetadataProjection } from './bridge-comm-worker-review-metadata-projection.js';
import {
	assertEquivalentReviewPublicationSnapshots,
	compareReviewMetadataLineages,
	requiredReviewPublicationId,
	reviewMetadataEventCompletesProjection,
	reviewMetadataInvalidatedEventFromSnapshot,
	reviewMetadataLineage,
	reviewMetadataSnapshotEventFromCompleteSnapshot,
	reviewDeltaPublicationFingerprint,
	type ReviewMetadataLineage,
	type ReviewMetadataLineageRelationship,
	type ReviewMetadataSnapshotEvent,
} from './bridge-comm-worker-review-publication-transaction.js';
import type {
	BridgeCommWorkerReviewCandidateReadyFacts,
	BridgeCommWorkerReviewCandidateFailedPublication,
	BridgeCommWorkerReviewCandidateReadyPublication,
	BridgeCommWorkerReviewCandidateStartedPublication,
	BridgeCommWorkerReviewComparisonCommit,
} from './bridge-comm-worker-review-publication-types.js';
import type { BridgeCommWorkerReviewMetadataApplication } from './bridge-comm-worker-review-runtime-application.js';
import {
	removeIndexedValue,
	reviewContentRequestKey,
	reviewRuntimeItemSignatures,
	reviewTreeParentPath,
	upsertIndexedValue,
} from './bridge-comm-worker-review-runtime-index.js';
import {
	bridgeCommWorkerReviewRuntimeSourceFromMetadataSnapshot,
	bridgeCommWorkerReviewRuntimeSourceItemsFromMetadataSnapshot,
} from './bridge-comm-worker-review-runtime-source-mapper.js';
import type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-source-diff.js';
import {
	handleBridgeCommWorkerReviewSuccessorReExposureSettlement,
	reconcileBridgeCommWorkerReviewSuccessorReExposureFence,
	type BridgeCommWorkerReviewSuccessorReExposureFence,
	type BridgeCommWorkerReviewSuccessorReExposureSettlement,
} from './bridge-comm-worker-review-successor-re-exposure.js';
import type { BridgeCommWorkerReviewRowMutation } from './bridge-comm-worker-store.js';
import type { BridgeProductReviewMetadataEvent } from './bridge-product-review-metadata-contracts.js';
import type {
	BridgeWorkerReviewCandidateStartDisposition,
	BridgeWorkerReviewDisplayPatch,
	BridgeWorkerReviewPublicationIdentity,
	BridgeWorkerReviewSourceDisplayPayload,
} from './bridge-worker-contracts.js';

export {
	applyBridgeCommWorkerReviewMetadataApplication,
	type BridgeCommWorkerReviewMetadataApplication,
} from './bridge-comm-worker-review-runtime-application.js';

type ReviewMetadataRoutedEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.delta' | 'review.invalidated' | 'review.window' }
>;
type ReviewMetadataActiveEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.invalidated' | 'review.window' }
>;
type ReviewMetadataPendingEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{
		readonly eventKind: 'review.delta' | 'review.invalidated' | 'review.snapshot' | 'review.window';
	}
>;

interface MutableBridgeCommWorkerReviewRuntimeSource extends BridgeCommWorkerReviewRuntimeSource {
	readonly contentItems: BridgeCommWorkerReviewRuntimeSource['contentItems'][number][];
	readonly contentRequestDescriptors: BridgeCommWorkerReviewRuntimeSource['contentRequestDescriptors'][number][];
	readonly renderSemantics: BridgeCommWorkerReviewRuntimeSource['renderSemantics'][number][];
	reviewPublicationIdentity: BridgeCommWorkerReviewRuntimeSource['reviewPublicationIdentity'];
	readonly rows: BridgeCommWorkerReviewRuntimeSource['rows'][number][];
}

interface BridgeCommWorkerReviewApplicatorRollbackSnapshot {
	readonly activeCandidateReadyFacts: BridgeCommWorkerReviewCandidateReadyFacts | null;
	readonly acceptedLineageFloor: ReviewMetadataLineage | null;
	readonly activeDeltaPublicationFingerprint: string | null;
	readonly activeProjection: BridgeCommWorkerReviewMetadataProjection | null;
	readonly contentItemIndexById: ReadonlyMap<string, number>;
	readonly contentRequestIndexByKey: ReadonlyMap<string, number>;
	readonly contentRequestKeysByItemId: ReadonlyMap<string, ReadonlySet<string>>;
	readonly directoryIdByPath: ReadonlyMap<string, string>;
	readonly itemSignatureById: ReadonlyMap<string, string>;
	readonly pendingProjection: BridgeCommWorkerReviewMetadataProjection | null;
	readonly pendingCandidateStart: BridgeWorkerReviewCandidateStartDisposition | null;
	readonly renderSemanticsIndexById: ReadonlyMap<string, number>;
	readonly rowIndexById: ReadonlyMap<string, number>;
	readonly runtimeSource: MutableBridgeCommWorkerReviewRuntimeSource;
	readonly sourceDisplayStatus: BridgeWorkerReviewSourceDisplayPayload['status'];
	readonly sourceEpoch: number;
	readonly treePathByRowId: ReadonlyMap<string, string>;
	readonly lastSuccessorReExposureFence: BridgeCommWorkerReviewSuccessorReExposureFence | null;
}

export type BridgeCommWorkerReviewMetadataFailureDisposition =
	| 'ignored'
	| 'noActive'
	| 'retainedActive';

export interface BridgeCommWorkerReviewPublicationApplicationReceipt {
	readonly publicationId: string;
}

export interface BridgeCommWorkerReviewRuntimeApplicationTransaction {
	readonly commit: () => void;
	readonly rollback: () => void;
	readonly runPostCommitEffects: () => void;
}

export class BridgeCommWorkerReviewMetadataApplicator {
	readonly #applyRuntimeSource: (
		application: BridgeCommWorkerReviewMetadataApplication,
	) => BridgeCommWorkerReviewRuntimeApplicationTransaction | void;
	readonly #currentWorkerDerivationEpoch: () => number;
	readonly #publishCandidateReady:
		| ((publication: BridgeCommWorkerReviewCandidateReadyPublication) => void)
		| undefined;
	readonly #publishCandidateFailed:
		| ((publication: BridgeCommWorkerReviewCandidateFailedPublication) => void)
		| undefined;
	readonly #publishCandidateStarted:
		| ((publication: BridgeCommWorkerReviewCandidateStartedPublication) => void)
		| undefined;
	readonly #publishDisplayPatches:
		| ((publication: {
				readonly comparisonCommit?: BridgeCommWorkerReviewComparisonCommit | undefined;
				readonly operationCorrelationId?: string | null;
				readonly patches: readonly BridgeWorkerReviewDisplayPatch[];
				readonly reviewPublicationIdentity: BridgeWorkerReviewPublicationIdentity | null;
				readonly workerDerivationEpoch: number;
		  }) => void)
		| undefined;
	readonly #recordIncrementalItemMapping: ((itemCount: number) => void) | undefined;
	#activeProjection: BridgeCommWorkerReviewMetadataProjection | null = null;
	#activeCandidateReadyFacts: BridgeCommWorkerReviewCandidateReadyFacts | null = null;
	#acceptedLineageFloor: ReviewMetadataLineage | null = null;
	#activeDeltaPublicationFingerprint: string | null = null;
	#latestProjectionRevision = 0;
	#lastSuccessorReExposureFence: BridgeCommWorkerReviewSuccessorReExposureFence | null = null;
	#pendingProjection: BridgeCommWorkerReviewMetadataProjection | null = null;
	#pendingCandidateStart: BridgeWorkerReviewCandidateStartDisposition | null = null;
	#reportedCandidateFailurePublicationId: string | null = null;
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
		readonly applyRuntimeSource: (
			application: BridgeCommWorkerReviewMetadataApplication,
		) => BridgeCommWorkerReviewRuntimeApplicationTransaction | void;
		readonly currentWorkerDerivationEpoch: () => number;
		readonly publishCandidateReady?: (
			publication: BridgeCommWorkerReviewCandidateReadyPublication,
		) => void;
		readonly publishCandidateFailed?: (
			publication: BridgeCommWorkerReviewCandidateFailedPublication,
		) => void;
		readonly publishCandidateStarted?: (
			publication: BridgeCommWorkerReviewCandidateStartedPublication,
		) => void;
		readonly publishDisplayPatches?: (publication: {
			readonly comparisonCommit?: BridgeCommWorkerReviewComparisonCommit | undefined;
			readonly operationCorrelationId?: string | null;
			readonly patches: readonly BridgeWorkerReviewDisplayPatch[];
			readonly reviewPublicationIdentity: BridgeWorkerReviewPublicationIdentity | null;
			readonly workerDerivationEpoch: number;
		}) => void;
		readonly recordIncrementalItemMapping?: (itemCount: number) => void;
	}) {
		this.#applyRuntimeSource = props.applyRuntimeSource;
		this.#currentWorkerDerivationEpoch = props.currentWorkerDerivationEpoch;
		this.#publishCandidateReady = props.publishCandidateReady;
		this.#publishCandidateFailed = props.publishCandidateFailed;
		this.#publishCandidateStarted = props.publishCandidateStarted;
		this.#publishDisplayPatches = props.publishDisplayPatches;
		this.#recordIncrementalItemMapping = props.recordIncrementalItemMapping;
	}

	apply(
		event: BridgeProductReviewMetadataEvent,
		workerDerivationEpoch: number,
	): BridgeCommWorkerReviewPublicationApplicationReceipt | null {
		if (workerDerivationEpoch !== this.#currentWorkerDerivationEpoch()) return null;
		switch (event.eventKind) {
			case 'review.reset':
			case 'review.sourceAccepted':
				this.#applyCandidateBoundaryEvent(event, workerDerivationEpoch);
				return null;
			case 'review.snapshot':
				return this.#applySnapshotEvent(event, workerDerivationEpoch);
			case 'review.window':
			case 'review.delta':
			case 'review.invalidated':
				return this.#applyRoutedEvent(event, workerDerivationEpoch);
			default:
				return assertNeverReviewMetadataEvent(event);
		}
	}

	admittedPublicationIdentity(): BridgeWorkerReviewPublicationIdentity | null {
		const lineage = this.#acceptedLineageFloor;
		if (lineage === null) return null;
		return {
			packageId: lineage.packageId,
			publicationId: lineage.publicationId,
			reviewGeneration: lineage.generation,
			revision: lineage.revision,
			sourceIdentity: lineage.sourceIdentity,
		};
	}

	handleSuccessorReExposureSettlement(
		settlement: BridgeCommWorkerReviewSuccessorReExposureSettlement,
		workerDerivationEpoch: number | null,
	): boolean {
		const result = handleBridgeCommWorkerReviewSuccessorReExposureSettlement({
			activeSnapshot: this.#activeProjection?.snapshot() ?? null,
			currentWorkerDerivationEpoch: this.#currentWorkerDerivationEpoch(),
			lastReExposureFence: this.#lastSuccessorReExposureFence,
			latestProjectionRevision: this.#latestProjectionRevision,
			publishCandidateReady: this.#publishCandidateReady,
			publishCandidateStarted: this.#publishCandidateStarted,
			publishDisplayPatches: this.#publishDisplayPatches,
			readyFacts: this.#activeCandidateReadyFacts,
			settlement,
			sourceDisplayStatus: this.#sourceDisplayStatus,
			workerDerivationEpoch,
		});
		this.#lastSuccessorReExposureFence = result.lastReExposureFence;
		return result.reExposed;
	}

	handleMetadataFailure(
		workerDerivationEpoch: number,
	): BridgeCommWorkerReviewMetadataFailureDisposition {
		if (workerDerivationEpoch !== this.#currentWorkerDerivationEpoch()) return 'ignored';
		const failedSnapshot = this.#pendingProjection?.snapshot() ?? null;
		const failedIdentity = failedSnapshot?.identity ?? null;
		if (
			failedIdentity !== null &&
			failedSnapshot?.revision !== null &&
			failedSnapshot?.revision !== undefined &&
			this.#pendingCandidateStart !== null &&
			this.#reportedCandidateFailurePublicationId !== failedIdentity.publicationId
		) {
			this.#publishCandidateFailed?.({
				identity: {
					generation: failedIdentity.generation,
					packageId: failedIdentity.packageId,
					publicationId: failedIdentity.publicationId,
					revision: failedSnapshot.revision,
					sourceIdentity: failedIdentity.sourceIdentity,
				},
				retryable: true,
				workerDerivationEpoch,
			});
		}
		this.#reportedCandidateFailurePublicationId = null;
		this.#pendingProjection = null;
		this.#pendingCandidateStart = null;
		if (this.#activeProjection === null) return 'noActive';
		this.#publishActiveSourceStale(workerDerivationEpoch);
		return 'retainedActive';
	}

	#applyCandidateBoundaryEvent(
		event: Extract<
			BridgeProductReviewMetadataEvent,
			{ readonly eventKind: 'review.reset' | 'review.sourceAccepted' }
		>,
		workerDerivationEpoch: number,
	): void {
		const existingPendingProjection = this.#pendingProjection;
		if (existingPendingProjection !== null && existingPendingProjection.matchesEvent(event)) {
			this.#applyProjectionEvent(existingPendingProjection, event);
			return;
		}
		if (!this.#admitCandidateLineage(event)) return;

		const pendingProjection = new BridgeCommWorkerReviewMetadataProjection();
		this.#applyProjectionEvent(pendingProjection, event);
		this.#pendingProjection = pendingProjection;
		this.#pendingCandidateStart = candidateStartDisposition(event);
		this.#publishCandidateStarted?.({
			disposition: this.#pendingCandidateStart,
			identity: reviewMetadataLineage(event),
			workerDerivationEpoch,
		});
		if (
			existingPendingProjection === null &&
			this.#activeProjection !== null &&
			!this.#activeProjection.matchesEvent(event)
		) {
			this.#publishActiveSourceStale(workerDerivationEpoch);
		}
	}

	#applySnapshotEvent(
		event: ReviewMetadataSnapshotEvent,
		workerDerivationEpoch: number,
	): BridgeCommWorkerReviewPublicationApplicationReceipt | null {
		if (this.#pendingProjection?.matchesEvent(event) === true) {
			return this.#applyPendingEvent(event, workerDerivationEpoch);
		}
		if (!this.#admitCandidateLineage(event)) return null;

		const pendingProjection = new BridgeCommWorkerReviewMetadataProjection();
		const projectionResult = this.#applyProjectionEvent(pendingProjection, event);
		this.#pendingProjection = pendingProjection;
		this.#pendingCandidateStart = { kind: 'replacement' };
		this.#publishCandidateStarted?.({
			disposition: this.#pendingCandidateStart,
			identity: reviewMetadataLineage(event),
			workerDerivationEpoch,
		});
		if (pendingProjection.hasFinalBarrier()) {
			pendingProjection.assertCompleteFinalBarrier();
			return this.#commitPendingProjection({
				finalBarrierEvent: event,
				projectionResult,
				workerDerivationEpoch,
			});
		}
		if (this.#activeProjection !== null && !this.#activeProjection.matchesEvent(event)) {
			this.#publishActiveSourceStale(workerDerivationEpoch);
		}
		return null;
	}

	#applyRoutedEvent(
		event: ReviewMetadataRoutedEvent,
		workerDerivationEpoch: number,
	): BridgeCommWorkerReviewPublicationApplicationReceipt | null {
		if (this.#pendingProjection?.matchesEvent(event) === true) {
			return this.#applyPendingEvent(event, workerDerivationEpoch);
		}
		if (this.#activeProjection?.matchesEvent(event) === true) {
			if (event.eventKind === 'review.delta') {
				if (this.#activeDeltaPublicationFingerprint !== reviewDeltaPublicationFingerprint(event)) {
					throw new Error(
						'Bridge Review delta replay changed payload for an active publication identity.',
					);
				}
				return { publicationId: event.publicationId };
			}
			if (reviewMetadataEventCompletesProjection(event)) {
				const activeProjection = this.#activeProjection;
				if (activeProjection === null) {
					throw new Error('Bridge Review replay validation requires an active projection.');
				}
				const replayProjection = activeProjection.cloneComplete();
				this.#applyProjectionEvent(replayProjection, event);
				replayProjection.assertCompleteFinalBarrier();
				assertEquivalentReviewPublicationSnapshots(
					activeProjection.snapshot(),
					replayProjection.snapshot(),
				);
				return { publicationId: event.publicationId };
			}
			this.#applyActiveEvent(event, workerDerivationEpoch);
			return null;
		}
		if (
			event.eventKind === 'review.delta' &&
			this.#activeProjection?.canApplySuccessorDelta(event) === true
		) {
			const lineageRelationship = this.#lineageRelationshipToAcceptedFloor(event);
			if (lineageRelationship === 'older') return null;
			if (lineageRelationship === 'ambiguous') {
				throw new Error(
					'Bridge Review metadata cannot order distinct sources within one generation.',
				);
			}
			return this.#applySuccessorDelta(event, workerDerivationEpoch);
		}

		const lineageRelationship = this.#lineageRelationshipToAcceptedFloor(event);
		if (lineageRelationship === 'older') return null;
		if (lineageRelationship === 'ambiguous') {
			throw new Error(
				'Bridge Review metadata cannot order distinct sources within one generation.',
			);
		}
		throw new Error('Bridge Review metadata event does not continue the active or pending source.');
	}

	#applyPendingEvent(
		event: ReviewMetadataPendingEvent,
		workerDerivationEpoch: number,
	): BridgeCommWorkerReviewPublicationApplicationReceipt | null {
		const pendingProjection = this.#pendingProjection;
		if (pendingProjection === null || !pendingProjection.matchesEvent(event)) {
			throw new Error('Bridge Review metadata payload does not match the pending worker source.');
		}
		const projectionResult = this.#applyProjectionEvent(pendingProjection, event);
		this.#recordIncrementalItemMapping?.(projectionResult.affectedItemIds.length);
		if (!pendingProjection.hasFinalBarrier()) return null;
		pendingProjection.assertCompleteFinalBarrier();
		return this.#commitPendingProjection({
			finalBarrierEvent: event,
			projectionResult,
			workerDerivationEpoch,
		});
	}

	#admitCandidateLineage(event: BridgeProductReviewMetadataEvent): boolean {
		const lineageRelationship = this.#lineageRelationshipToAcceptedFloor(event);
		if (lineageRelationship === 'older') return false;
		if (lineageRelationship === 'ambiguous') {
			throw new Error(
				'Bridge Review metadata cannot order distinct sources within one generation.',
			);
		}
		if (lineageRelationship === null || lineageRelationship === 'newer') {
			this.#acceptedLineageFloor = reviewMetadataLineage(event);
		}
		return true;
	}

	#lineageRelationshipToAcceptedFloor(
		event: BridgeProductReviewMetadataEvent,
	): ReviewMetadataLineageRelationship | null {
		if (this.#acceptedLineageFloor === null) return null;
		return compareReviewMetadataLineages(reviewMetadataLineage(event), this.#acceptedLineageFloor);
	}

	#commitPendingProjection(props: {
		readonly finalBarrierEvent: ReviewMetadataPendingEvent;
		readonly projectionResult: BridgeCommWorkerReviewMetadataApplyResult;
		readonly workerDerivationEpoch: number;
	}): BridgeCommWorkerReviewPublicationApplicationReceipt {
		const pendingProjection = this.#pendingProjection;
		if (pendingProjection === null) {
			throw new Error('Bridge Review metadata commit requires a pending worker projection.');
		}
		pendingProjection.assertCompleteFinalBarrier();
		const snapshot = pendingProjection.snapshot();
		const candidateStart = this.#pendingCandidateStart;
		if (candidateStart === null) {
			throw new Error('Bridge Review candidate commit requires one leading start disposition.');
		}
		const publicationId = requiredReviewPublicationId(snapshot);
		if (
			this.#activeProjection?.matchesEvent(
				reviewMetadataSnapshotEventFromCompleteSnapshot(snapshot),
			)
		) {
			assertEquivalentReviewPublicationSnapshots(this.#activeProjection.snapshot(), snapshot);
			this.#pendingProjection = null;
			this.#pendingCandidateStart = null;
			if (this.#sourceDisplayStatus === 'stale') {
				this.#publishActiveSourceReady(props.workerDerivationEpoch);
			}
			return { publicationId };
		}
		const previousItemIds = [...this.#itemSignatureById.keys()];
		const previousRowIds = this.#runtimeSource.rows.map((row) => row.id);
		const nextItemIds = new Set(snapshot.orderedItemIds);
		const rollbackSnapshot = this.#captureRollbackSnapshot();
		try {
			this.#sourceEpoch += 1;
			this.#replaceRuntimeSource(
				bridgeCommWorkerReviewRuntimeSourceFromMetadataSnapshot(snapshot),
				snapshot.treeRows,
			);
			this.#activeProjection = pendingProjection;
			this.#activeDeltaPublicationFingerprint = null;
			this.#pendingProjection = null;
			this.#sourceDisplayStatus = 'ready';
			this.#publishApplication({
				candidateStart,
				affectedItemIds: [...new Set([...previousItemIds, ...snapshot.orderedItemIds])],
				affectedRowIds: [
					...new Set([
						...previousRowIds,
						...snapshot.treeRows.map((row) => row.itemId ?? row.rowId),
					]),
				],
				completeContentItemIds: snapshot.orderedItemIds,
				completeRowIds: snapshot.treeRows.map((row) => row.itemId ?? row.rowId),
				candidateReadyEvent: props.finalBarrierEvent,
				event: reviewMetadataSnapshotEventFromCompleteSnapshot(snapshot),
				projectionResult: props.projectionResult,
				removedItemIds: previousItemIds.filter((itemId) => !nextItemIds.has(itemId)),
				reset: true,
				rowMutation: { removedRowIds: [], rowUpserts: [] },
				snapshot,
				workerDerivationEpoch: props.workerDerivationEpoch,
			});
			this.#pendingCandidateStart = null;
		} catch (error) {
			this.#restoreRollbackSnapshot(rollbackSnapshot);
			throw error;
		}
		return { publicationId };
	}

	#applySuccessorDelta(
		event: Extract<BridgeProductReviewMetadataEvent, { readonly eventKind: 'review.delta' }>,
		workerDerivationEpoch: number,
	): BridgeCommWorkerReviewPublicationApplicationReceipt {
		const activeProjection = this.#activeProjection;
		if (activeProjection === null || !activeProjection.canApplySuccessorDelta(event)) {
			throw new Error('Bridge Review delta publication requires its exact active predecessor.');
		}
		const candidateProjection = activeProjection.cloneComplete();
		const projectionResult = this.#applyProjectionEvent(candidateProjection, event);
		const disposition = candidateStartDisposition(event);
		this.#publishCandidateStarted?.({
			disposition,
			identity: reviewMetadataLineage(event),
			workerDerivationEpoch,
		});
		candidateProjection.assertCompleteFinalBarrier();
		const snapshot = candidateProjection.snapshot();
		const candidateItemIds = [...new Set(projectionResult.affectedItemIds)];
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
		const rollbackSnapshot = this.#captureRollbackSnapshot();
		try {
			const rowMutation = this.#applyTreeRowMutation(event);
			this.#upsertRuntimeSourceItems(itemSource, candidateItemIds);
			this.#activeProjection = candidateProjection;
			this.#activeDeltaPublicationFingerprint = reviewDeltaPublicationFingerprint(event);
			this.#pendingProjection = null;
			this.#pendingCandidateStart = null;
			this.#acceptedLineageFloor = reviewMetadataLineage(event);
			this.#sourceDisplayStatus = 'ready';
			this.#publishApplication({
				candidateStart: disposition,
				affectedItemIds,
				affectedRowIds: rowMutation.rowUpserts.map((row) => row.id),
				event,
				projectionResult,
				removedItemIds,
				reset: false,
				rowMutation,
				snapshot,
				workerDerivationEpoch,
			});
		} catch (error) {
			this.#restoreRollbackSnapshot(rollbackSnapshot);
			throw error;
		}
		return { publicationId: event.publicationId };
	}

	#applyActiveEvent(event: ReviewMetadataActiveEvent, workerDerivationEpoch: number): void {
		const activeProjection = this.#activeProjection;
		if (activeProjection === null || !activeProjection.matchesEvent(event)) {
			throw new Error('Bridge Review metadata event does not continue the active worker source.');
		}
		const candidateProjection = activeProjection.cloneComplete();
		const projectionResult = this.#applyProjectionEvent(candidateProjection, event);

		const candidateItemIds = [...new Set(projectionResult.affectedItemIds)];
		this.#recordIncrementalItemMapping?.(candidateItemIds.length);
		const completesProjection = reviewMetadataEventCompletesProjection(event);
		const snapshot = completesProjection
			? candidateProjection.snapshot()
			: candidateProjection.snapshotItems(candidateItemIds);
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
		const rollbackSnapshot = this.#captureRollbackSnapshot();
		try {
			if (this.#pendingProjection === null) this.#updateSourceDisplayStatus(event);
			const rowMutation = this.#applyTreeRowMutation(event);
			if (completesProjection) {
				this.#replaceRuntimeSource(
					bridgeCommWorkerReviewRuntimeSourceFromMetadataSnapshot(snapshot),
					snapshot.treeRows,
				);
			} else {
				this.#upsertRuntimeSourceItems(itemSource, candidateItemIds);
			}
			this.#activeProjection = candidateProjection;
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
		} catch (error) {
			this.#restoreRollbackSnapshot(rollbackSnapshot);
			throw error;
		}
	}

	#publishActiveSourceStale(workerDerivationEpoch: number): void {
		const activeProjection = this.#activeProjection;
		if (activeProjection === null) return;
		this.#sourceDisplayStatus = 'stale';
		if (this.#publishDisplayPatches === undefined) return;
		const snapshot = activeProjection.snapshot();
		const event = reviewMetadataInvalidatedEventFromSnapshot(snapshot);
		this.#publishDisplayPatches({
			patches: bridgeCommWorkerReviewDisplayPatches({
				event,
				projectionResult: {
					affectedItemIds: [],
					invalidation: event,
					projectionRevision: 0,
					reset: false,
				},
				snapshot,
				sourceStatus: 'stale',
			}),
			reviewPublicationIdentity: null,
			workerDerivationEpoch,
		});
	}

	#publishActiveSourceReady(workerDerivationEpoch: number): void {
		const activeProjection = this.#activeProjection;
		if (activeProjection === null) return;
		this.#sourceDisplayStatus = 'ready';
		if (this.#publishDisplayPatches === undefined) return;
		const snapshot = activeProjection.snapshot();
		const event = reviewMetadataSnapshotEventFromCompleteSnapshot(snapshot);
		const sourcePatches = bridgeCommWorkerReviewDisplayPatches({
			event,
			projectionResult: {
				affectedItemIds: [],
				invalidation: null,
				projectionRevision: 0,
				reset: false,
			},
			snapshot,
			sourceStatus: 'ready',
		}).filter((patch) => patch.slice === 'reviewSource');
		this.#publishDisplayPatches({
			patches: sourcePatches,
			reviewPublicationIdentity: null,
			workerDerivationEpoch,
		});
	}

	#updateSourceDisplayStatus(event: BridgeProductReviewMetadataEvent): void {
		switch (event.eventKind) {
			case 'review.invalidated':
				this.#sourceDisplayStatus = 'stale';
				break;
			case 'review.window':
				if (reviewMetadataEventCompletesProjection(event)) this.#sourceDisplayStatus = 'ready';
				break;
			case 'review.delta':
				break;
			case 'review.sourceAccepted':
			case 'review.reset':
			case 'review.snapshot':
				throw new Error('Candidate Review metadata cannot update active display status.');
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
			reviewPublicationIdentity: source.reviewPublicationIdentity,
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
		this.#runtimeSource.reviewPublicationIdentity = itemSource.reviewPublicationIdentity;
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
		readonly candidateStart?: BridgeWorkerReviewCandidateStartDisposition | undefined;
		readonly candidateReadyEvent?: BridgeProductReviewMetadataEvent;
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
		if (props.snapshot.identity === null || props.snapshot.revision === null) {
			throw new Error('Review publication requires an exact source identity and revision.');
		}
		const displayPatches = bridgeCommWorkerReviewDisplayPatches({
			event: props.event,
			projectionResult: props.projectionResult,
			snapshot: props.snapshot,
			sourceStatus: this.#sourceDisplayStatus,
		});
		const runtimeApplicationResult = this.#applyRuntimeSource({
			affectedItemIds: props.affectedItemIds,
			affectedRowIds: props.affectedRowIds,
			operationCorrelationId: props.snapshot.identity?.operationCorrelationId ?? null,
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
		const runtimeApplication = runtimeApplicationResult ?? undefined;
		const candidateIdentity: ReviewMetadataLineage = {
			generation: props.snapshot.identity.generation,
			packageId: props.snapshot.identity.packageId,
			publicationId: props.snapshot.identity.publicationId,
			revision: props.snapshot.revision,
			sourceIdentity: props.snapshot.identity.sourceIdentity,
		};
		try {
			this.#publishDisplayPatches?.({
				...(!('presentationRevision' in props.event) ||
				props.event.presentationRevision === undefined ||
				!('reviewComparison' in props.event) ||
				props.event.reviewComparison === undefined
					? {}
					: {
							comparisonCommit: {
								presentationRevision: props.event.presentationRevision,
								reviewComparison: props.event.reviewComparison,
							},
						}),
				operationCorrelationId: props.snapshot.identity?.operationCorrelationId ?? null,
				patches: displayPatches,
				reviewPublicationIdentity: {
					packageId: props.snapshot.identity.packageId,
					publicationId: props.snapshot.identity.publicationId,
					reviewGeneration: props.snapshot.identity.generation,
					revision: props.snapshot.revision,
					sourceIdentity: props.snapshot.identity.sourceIdentity,
				},
				workerDerivationEpoch: props.workerDerivationEpoch,
			});
			const candidateReadyEvent = props.candidateReadyEvent ?? props.event;
			if (
				props.candidateStart !== undefined &&
				(candidateReadyEvent.eventKind === 'review.delta' ||
					reviewMetadataEventCompletesProjection(candidateReadyEvent))
			) {
				const readyFacts: BridgeCommWorkerReviewCandidateReadyFacts = {
					disposition: props.candidateStart,
					identity: candidateIdentity,
				};
				this.#publishCandidateReady?.({
					...readyFacts,
					workerDerivationEpoch: props.workerDerivationEpoch,
				});
				this.#activeCandidateReadyFacts = readyFacts;
				this.#lastSuccessorReExposureFence =
					reconcileBridgeCommWorkerReviewSuccessorReExposureFence(
						this.#lastSuccessorReExposureFence,
						readyFacts.identity,
					);
			}
		} catch (error) {
			runtimeApplication?.rollback();
			if (props.candidateStart !== undefined) {
				this.#publishCandidateFailed?.({
					identity: candidateIdentity,
					retryable: true,
					workerDerivationEpoch: props.workerDerivationEpoch,
				});
				this.#reportedCandidateFailurePublicationId = candidateIdentity.publicationId;
			}
			throw error;
		}
		runtimeApplication?.commit();
		runtimeApplication?.runPostCommitEffects();
	}

	#applyProjectionEvent(
		projection: BridgeCommWorkerReviewMetadataProjection,
		event: BridgeProductReviewMetadataEvent,
	): BridgeCommWorkerReviewMetadataApplyResult {
		const result = projection.apply(event, this.#latestProjectionRevision);
		this.#latestProjectionRevision = result.projectionRevision;
		return result;
	}

	#captureRollbackSnapshot(): BridgeCommWorkerReviewApplicatorRollbackSnapshot {
		return {
			activeCandidateReadyFacts: this.#activeCandidateReadyFacts,
			acceptedLineageFloor: this.#acceptedLineageFloor,
			activeDeltaPublicationFingerprint: this.#activeDeltaPublicationFingerprint,
			activeProjection: this.#activeProjection,
			contentItemIndexById: new Map(this.#contentItemIndexById),
			contentRequestIndexByKey: new Map(this.#contentRequestIndexByKey),
			contentRequestKeysByItemId: new Map(
				[...this.#contentRequestKeysByItemId].map(([itemId, keys]) => [itemId, new Set(keys)]),
			),
			directoryIdByPath: new Map(this.#directoryIdByPath),
			itemSignatureById: new Map(this.#itemSignatureById),
			lastSuccessorReExposureFence: this.#lastSuccessorReExposureFence,
			pendingProjection: this.#pendingProjection,
			pendingCandidateStart: this.#pendingCandidateStart,
			renderSemanticsIndexById: new Map(this.#renderSemanticsIndexById),
			rowIndexById: new Map(this.#rowIndexById),
			runtimeSource: {
				contentItems: [...this.#runtimeSource.contentItems],
				contentRequestDescriptors: [...this.#runtimeSource.contentRequestDescriptors],
				renderSemantics: [...this.#runtimeSource.renderSemantics],
				reviewPublicationIdentity: this.#runtimeSource.reviewPublicationIdentity,
				rows: [...this.#runtimeSource.rows],
			},
			sourceDisplayStatus: this.#sourceDisplayStatus,
			sourceEpoch: this.#sourceEpoch,
			treePathByRowId: new Map(this.#treePathByRowId),
		};
	}

	#restoreRollbackSnapshot(snapshot: BridgeCommWorkerReviewApplicatorRollbackSnapshot): void {
		this.#activeCandidateReadyFacts = snapshot.activeCandidateReadyFacts;
		this.#acceptedLineageFloor = snapshot.acceptedLineageFloor;
		this.#activeDeltaPublicationFingerprint = snapshot.activeDeltaPublicationFingerprint;
		this.#activeProjection = snapshot.activeProjection;
		replaceMapContents(this.#contentItemIndexById, snapshot.contentItemIndexById);
		replaceMapContents(this.#contentRequestIndexByKey, snapshot.contentRequestIndexByKey);
		this.#contentRequestKeysByItemId.clear();
		for (const [itemId, keys] of snapshot.contentRequestKeysByItemId) {
			this.#contentRequestKeysByItemId.set(itemId, new Set(keys));
		}
		replaceMapContents(this.#directoryIdByPath, snapshot.directoryIdByPath);
		replaceMapContents(this.#itemSignatureById, snapshot.itemSignatureById);
		this.#lastSuccessorReExposureFence = snapshot.lastSuccessorReExposureFence;
		this.#pendingProjection = snapshot.pendingProjection;
		this.#pendingCandidateStart = snapshot.pendingCandidateStart;
		replaceMapContents(this.#renderSemanticsIndexById, snapshot.renderSemanticsIndexById);
		replaceMapContents(this.#rowIndexById, snapshot.rowIndexById);
		this.#runtimeSource = snapshot.runtimeSource;
		this.#sourceDisplayStatus = snapshot.sourceDisplayStatus;
		this.#sourceEpoch = snapshot.sourceEpoch;
		replaceMapContents(this.#treePathByRowId, snapshot.treePathByRowId);
	}
}

function candidateStartDisposition(
	event: Extract<
		BridgeProductReviewMetadataEvent,
		{ readonly eventKind: 'review.delta' | 'review.reset' | 'review.sourceAccepted' }
	>,
): BridgeWorkerReviewCandidateStartDisposition {
	if (
		(event.eventKind === 'review.delta' || event.eventKind === 'review.reset') &&
		event.preDeliveryPresentationClass !== undefined &&
		event.affectedStableFileIdentities !== undefined
	) {
		return {
			affectedStableFileIdentities: event.affectedStableFileIdentities,
			kind: 'sameSource',
			presentationClass: event.preDeliveryPresentationClass,
		};
	}
	return { kind: 'replacement' };
}

function replaceMapContents<TKey, TValue>(
	target: Map<TKey, TValue>,
	source: ReadonlyMap<TKey, TValue>,
): void {
	target.clear();
	for (const [key, value] of source) target.set(key, value);
}

function assertNeverReviewMetadataEvent(event: never): never {
	throw new Error(`Unhandled Review metadata applicator event: ${JSON.stringify(event)}`);
}

function emptyReviewRuntimeSource(): MutableBridgeCommWorkerReviewRuntimeSource {
	return {
		contentItems: [],
		contentRequestDescriptors: [],
		renderSemantics: [],
		reviewPublicationIdentity: null,
		rows: [],
	};
}
