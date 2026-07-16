import type {
	BridgeWorkerFilePierreRenderJobEvent,
	BridgeWorkerReviewPierreRenderJobEvent,
} from './bridge-worker-contracts.js';
import {
	bridgeWorkerRenderDispositionReceiptSchema,
	type BridgeWorkerRenderDispositionReceipt,
	type BridgeWorkerRenderReceiptIdentity,
	type BridgeWorkerRenderRejectionReason,
} from './bridge-worker-render-fulfillment.js';

export type BridgeMainRenderPublication =
	| BridgeWorkerFilePierreRenderJobEvent
	| BridgeWorkerReviewPierreRenderJobEvent;

export type BridgeMainRenderPublicationItem = BridgeMainRenderPublication['job']['payload']['item'];
type BridgeMainRenderSourceCorrelation =
	BridgeMainRenderPublication['job']['sourceCorrelations'][number];

export type BridgeMainPierreItemResidency = 'replaced' | 'reusedPainted';
type BridgeMainPostRenderPhase = 'mount' | 'update' | 'unmount';

interface BridgeMainPaintedSourceCorrelation extends BridgeMainRenderSourceCorrelation {
	readonly disposition: 'painted';
	readonly pierreItemId: string;
	readonly publicationId: string;
	readonly semanticItemId: string;
	readonly surface: BridgeMainRenderPublication['surface'];
}

interface BridgeMainRetainedPaintedEvidence {
	readonly encodedSourceCorrelations: string;
	readonly publicationId: string;
}

export interface BridgeMainRenderedItemReadback {
	readonly element: {
		readonly isConnected: boolean;
		readonly removeAttribute: (qualifiedName: string) => void;
		readonly setAttribute: (qualifiedName: string, value: string) => void;
	};
	readonly item: BridgeMainRenderPublicationItem;
}

export interface BridgeMainRenderReadback {
	readonly readCurrentItem: () => BridgeMainRenderPublicationItem | undefined;
	readonly readRenderedItem: () => BridgeMainRenderedItemReadback | null;
}

export interface BridgeMainRenderFulfillmentCoordinator {
	readonly acceptPublication: (
		publication: BridgeMainRenderPublication,
	) => BridgeMainRenderPublicationAdmission;
	readonly bindPublicationItem: (props: {
		readonly finalItem: BridgeMainRenderPublicationItem;
		readonly publicationItem: BridgeMainRenderPublicationItem;
		readonly residency: BridgeMainPierreItemResidency;
	}) => void;
	readonly dispose: () => void;
	readonly isBoundFinalItem: (item: BridgeMainRenderPublicationItem) => boolean;
	readonly markPublicationQueued: (publication: BridgeMainRenderPublication) => void;
	readonly observePostRender: (
		props: BridgeMainRenderReadback & {
			readonly contextItem: BridgeMainRenderPublicationItem;
			readonly itemId: string;
			readonly phase: BridgeMainPostRenderPhase;
		},
	) => void;
	readonly reconcilePublication: (
		props: BridgeMainRenderReadback & { readonly itemId: string },
	) => void;
	readonly rejectPublication: (
		publication: BridgeMainRenderPublication,
		reason: BridgeWorkerRenderRejectionReason,
	) => void;
	readonly supersedeItem: (itemId: string, reason: BridgeWorkerRenderRejectionReason) => void;
}

export type BridgeMainRenderPublicationAdmission = 'accepted' | 'duplicate';

export interface CreateBridgeMainRenderFulfillmentCoordinatorProps {
	readonly cancelAnimationFrame?: (frameHandle: number) => void;
	readonly nowMilliseconds?: () => number;
	readonly requestAnimationFrame?: (callback: FrameRequestCallback) => number;
	readonly sendDisposition: (receipt: BridgeWorkerRenderDispositionReceipt) => void;
}

interface BridgeMainPendingRenderPublication {
	readonly identityKey: string;
	item: BridgeMainRenderPublicationItem;
	readonly logicalItemId: string;
	readonly pierreItemId: string;
	readonly publication: BridgeMainRenderPublication;
	readonly publicationItem: BridgeMainRenderPublicationItem;
	animationFrameHandle: number | null;
	finalItemBound: boolean;
	postRenderObserved: boolean;
	queuedSubmissionObserved: boolean;
	residency: BridgeMainPierreItemResidency;
	stage: 'accepted' | 'queued' | 'applied';
}

export function createBridgeMainRenderFulfillmentCoordinator(
	props: CreateBridgeMainRenderFulfillmentCoordinatorProps,
): BridgeMainRenderFulfillmentCoordinator {
	const cancelFrame =
		props.cancelAnimationFrame ?? globalThis.cancelAnimationFrame.bind(globalThis);
	const nowMilliseconds = props.nowMilliseconds ?? (() => performance.now());
	const requestFrame =
		props.requestAnimationFrame ?? globalThis.requestAnimationFrame.bind(globalThis);
	const pendingByPierreItemId = new Map<string, BridgeMainPendingRenderPublication>();
	const pendingByPublicationItem = new WeakMap<
		BridgeMainRenderPublicationItem,
		BridgeMainPendingRenderPublication
	>();
	let retainedPaintedEvidenceByFinalItem = new WeakMap<
		BridgeMainRenderPublicationItem,
		BridgeMainRetainedPaintedEvidence
	>();
	const terminalPublicationIdentityKeys = new Set<string>();
	let isDisposed = false;

	const sendPositiveDisposition = (
		entry: BridgeMainPendingRenderPublication,
		disposition: 'queued' | 'applied' | 'painted',
	): void => {
		props.sendDisposition(
			bridgeWorkerRenderDispositionReceiptSchema.parse({
				...entry.publication.renderReceiptIdentity,
				disposition,
				kind: 'render.disposition',
				receivedAtMilliseconds: nowMilliseconds(),
			}),
		);
	};

	const cancelPendingFrame = (entry: BridgeMainPendingRenderPublication): void => {
		if (entry.animationFrameHandle === null) return;
		cancelFrame(entry.animationFrameHandle);
		entry.animationFrameHandle = null;
	};

	const publishQueuedDispositionWhenReady = (entry: BridgeMainPendingRenderPublication): void => {
		if (entry.stage !== 'accepted' || !entry.queuedSubmissionObserved || !entry.finalItemBound) {
			return;
		}
		sendPositiveDisposition(entry, 'queued');
		entry.stage = 'queued';
	};

	const sendTerminalDisposition = (
		publication: BridgeMainRenderPublication,
		disposition: 'rejected' | 'superseded',
		reason: BridgeWorkerRenderRejectionReason,
	): void => {
		const identityKey = bridgeMainRenderReceiptIdentityKey(publication.renderReceiptIdentity);
		if (terminalPublicationIdentityKeys.has(identityKey)) return;
		const receivedAtMilliseconds = nowMilliseconds();
		props.sendDisposition(
			bridgeWorkerRenderDispositionReceiptSchema.parse({
				...publication.renderReceiptIdentity,
				disposition,
				kind: 'render.disposition',
				reason,
				receivedAtMilliseconds,
				retryAtMilliseconds: receivedAtMilliseconds,
			}),
		);
		terminalPublicationIdentityKeys.add(identityKey);
	};

	const closePendingPublication = (
		entry: BridgeMainPendingRenderPublication,
		disposition: 'rejected' | 'superseded',
		reason: BridgeWorkerRenderRejectionReason,
	): void => {
		if (pendingByPierreItemId.get(entry.pierreItemId) !== entry) return;
		cancelPendingFrame(entry);
		pendingByPierreItemId.delete(entry.pierreItemId);
		pendingByPublicationItem.delete(entry.publicationItem);
		sendTerminalDisposition(entry.publication, disposition, reason);
	};

	const schedulePaintValidation = (
		entry: BridgeMainPendingRenderPublication,
		readback: BridgeMainRenderReadback,
	): void => {
		if (
			entry.stage !== 'applied' ||
			!entry.postRenderObserved ||
			entry.animationFrameHandle !== null
		) {
			return;
		}
		const animationFrameHandle = requestFrame((): void => {
			if (
				entry.animationFrameHandle !== animationFrameHandle ||
				pendingByPierreItemId.get(entry.pierreItemId) !== entry
			) {
				return;
			}
			entry.animationFrameHandle = null;
			const renderedItem = matchingRenderedItemForEntry(entry, readback);
			if (renderedItem === null) {
				closePendingPublication(entry, 'rejected', 'stale_attempt');
				return;
			}
			sendPositiveDisposition(entry, 'painted');
			pendingByPierreItemId.delete(entry.pierreItemId);
			pendingByPublicationItem.delete(entry.publicationItem);
			terminalPublicationIdentityKeys.add(entry.identityKey);
			retainAndStampPaintedSourceCorrelation(
				entry,
				renderedItem,
				retainedPaintedEvidenceByFinalItem,
			);
		});
		entry.animationFrameHandle = animationFrameHandle;
	};

	const reconcileEntry = (
		entry: BridgeMainPendingRenderPublication,
		readback: BridgeMainRenderReadback,
	): void => {
		const renderedItem = matchingRenderedItemForEntry(entry, readback);
		if (renderedItem === null) return;
		clearPaintedSourceCorrelation(renderedItem);
		if (entry.stage === 'accepted') return;
		if (entry.residency !== 'reusedPainted' && !entry.postRenderObserved) return;
		if (entry.stage === 'queued') {
			sendPositiveDisposition(entry, 'applied');
			entry.stage = 'applied';
		}
		schedulePaintValidation(entry, readback);
	};

	return {
		acceptPublication: (publication): BridgeMainRenderPublicationAdmission => {
			if (isDisposed) {
				throw new Error('Bridge main render fulfillment coordinator is disposed.');
			}
			assertBridgeMainRenderPublicationIdentity(publication);
			const identityKey = bridgeMainRenderReceiptIdentityKey(publication.renderReceiptIdentity);
			if (terminalPublicationIdentityKeys.has(identityKey)) return 'duplicate';
			const logicalItemId = publication.job.itemId;
			const pierreItemId = publication.job.payload.item.id;
			const existingEntry =
				pendingByPierreItemId.get(pierreItemId) ??
				findPendingPublicationByLogicalItemId(pendingByPierreItemId, logicalItemId);
			if (existingEntry?.identityKey === identityKey) return 'duplicate';
			if (existingEntry !== undefined) {
				closePendingPublication(existingEntry, 'superseded', 'stale_submission');
			}
			const entry: BridgeMainPendingRenderPublication = {
				animationFrameHandle: null,
				finalItemBound: false,
				identityKey,
				item: publication.job.payload.item,
				logicalItemId,
				pierreItemId,
				postRenderObserved: false,
				publication,
				publicationItem: publication.job.payload.item,
				queuedSubmissionObserved: false,
				residency: 'replaced',
				stage: 'accepted',
			};
			retainedPaintedEvidenceByFinalItem.delete(entry.publicationItem);
			pendingByPierreItemId.set(pierreItemId, entry);
			pendingByPublicationItem.set(entry.publicationItem, entry);
			return 'accepted';
		},
		bindPublicationItem: (bindProps): void => {
			if (isDisposed) return;
			const entry = pendingByPublicationItem.get(bindProps.publicationItem);
			if (
				entry === undefined ||
				pendingByPierreItemId.get(entry.pierreItemId) !== entry ||
				bindProps.finalItem.id !== entry.pierreItemId ||
				bindProps.finalItem.bridgeMetadata.itemId !== entry.logicalItemId ||
				bindProps.finalItem.type !== entry.publicationItem.type
			) {
				return;
			}
			if (entry.item === bindProps.finalItem && entry.finalItemBound) return;
			cancelPendingFrame(entry);
			retainedPaintedEvidenceByFinalItem.delete(entry.item);
			retainedPaintedEvidenceByFinalItem.delete(bindProps.finalItem);
			entry.item = bindProps.finalItem;
			entry.finalItemBound = true;
			entry.postRenderObserved = bindProps.residency === 'reusedPainted';
			entry.residency = bindProps.residency;
			publishQueuedDispositionWhenReady(entry);
		},
		dispose: (): void => {
			if (isDisposed) return;
			isDisposed = true;
			for (const entry of pendingByPierreItemId.values()) {
				closePendingPublication(entry, 'superseded', 'stale_submission');
			}
			retainedPaintedEvidenceByFinalItem = new WeakMap();
			terminalPublicationIdentityKeys.clear();
		},
		isBoundFinalItem: (item): boolean => {
			if (isDisposed) return false;
			const entry = pendingByPierreItemId.get(item.id);
			return entry?.finalItemBound === true && entry.item === item;
		},
		markPublicationQueued: (publication): void => {
			if (isDisposed) return;
			assertBridgeMainRenderPublicationIdentity(publication);
			const entry = pendingByPierreItemId.get(publication.job.payload.item.id);
			if (
				entry === undefined ||
				entry.identityKey !==
					bridgeMainRenderReceiptIdentityKey(publication.renderReceiptIdentity) ||
				entry.stage !== 'accepted'
			) {
				return;
			}
			entry.queuedSubmissionObserved = true;
			publishQueuedDispositionWhenReady(entry);
		},
		observePostRender: (observeProps): void => {
			if (isDisposed || observeProps.phase === 'unmount') return;
			const entry = pendingByPierreItemId.get(observeProps.itemId);
			if (entry === undefined || observeProps.contextItem !== entry.item) {
				synchronizeRetainedPaintedEvidence(
					observeProps.contextItem,
					observeProps,
					retainedPaintedEvidenceByFinalItem,
				);
				return;
			}
			entry.postRenderObserved = true;
			reconcileEntry(entry, observeProps);
		},
		reconcilePublication: (reconcileProps): void => {
			if (isDisposed) return;
			const entry = pendingByPierreItemId.get(reconcileProps.itemId);
			if (entry === undefined) {
				const currentItem = reconcileProps.readCurrentItem();
				if (currentItem === undefined) return;
				synchronizeRetainedPaintedEvidence(
					currentItem,
					reconcileProps,
					retainedPaintedEvidenceByFinalItem,
				);
				return;
			}
			reconcileEntry(entry, reconcileProps);
		},
		rejectPublication: (publication, reason): void => {
			if (isDisposed) return;
			assertBridgeMainRenderPublicationIdentity(publication);
			const existingEntry = pendingByPierreItemId.get(publication.job.payload.item.id);
			const identityKey = bridgeMainRenderReceiptIdentityKey(publication.renderReceiptIdentity);
			if (existingEntry?.identityKey === identityKey) {
				closePendingPublication(existingEntry, 'rejected', reason);
				return;
			}
			sendTerminalDisposition(publication, 'rejected', reason);
		},
		supersedeItem: (itemId, reason): void => {
			if (isDisposed) return;
			const entry = findPendingPublicationByLogicalItemId(pendingByPierreItemId, itemId);
			if (entry === undefined) return;
			closePendingPublication(entry, 'superseded', reason);
		},
	};
}

function matchingRenderedItemForEntry(
	entry: BridgeMainPendingRenderPublication,
	readback: BridgeMainRenderReadback,
): BridgeMainRenderedItemReadback | null {
	return matchingRenderedItemForExactItem(entry.item, readback);
}

function matchingRenderedItemForExactItem(
	item: BridgeMainRenderPublicationItem,
	readback: BridgeMainRenderReadback,
): BridgeMainRenderedItemReadback | null {
	if (readback.readCurrentItem() !== item) return null;
	const renderedItem = readback.readRenderedItem();
	return renderedItem !== null && renderedItem.item === item && renderedItem.element.isConnected
		? renderedItem
		: null;
}

const BRIDGE_PAINTED_SOURCE_CORRELATIONS_ATTRIBUTE = 'data-bridge-painted-source-correlations';
const BRIDGE_PAINTED_PUBLICATION_ID_ATTRIBUTE = 'data-bridge-painted-publication-id';

function retainAndStampPaintedSourceCorrelation(
	entry: BridgeMainPendingRenderPublication,
	renderedItem: BridgeMainRenderedItemReadback,
	retainedPaintedEvidenceByFinalItem: WeakMap<
		BridgeMainRenderPublicationItem,
		BridgeMainRetainedPaintedEvidence
	>,
): void {
	try {
		const paintedSourceCorrelations = paintedSourceCorrelationsForEntry(entry);
		if (paintedSourceCorrelations.length === 0) {
			retainedPaintedEvidenceByFinalItem.delete(entry.item);
			clearPaintedSourceCorrelation(renderedItem);
			return;
		}
		const evidence = {
			encodedSourceCorrelations: JSON.stringify(paintedSourceCorrelations),
			publicationId: entry.publication.renderReceiptIdentity.publicationId,
		} satisfies BridgeMainRetainedPaintedEvidence;
		retainedPaintedEvidenceByFinalItem.set(entry.item, evidence);
		stampRetainedPaintedEvidence(renderedItem, evidence);
	} catch {
		// Packaged proof metadata is diagnostic-only and cannot gate product fulfillment.
	}
}

function synchronizeRetainedPaintedEvidence(
	item: BridgeMainRenderPublicationItem,
	readback: BridgeMainRenderReadback,
	retainedPaintedEvidenceByFinalItem: WeakMap<
		BridgeMainRenderPublicationItem,
		BridgeMainRetainedPaintedEvidence
	>,
): void {
	const renderedItem = matchingRenderedItemForExactItem(item, readback);
	if (renderedItem === null) return;
	const evidence = retainedPaintedEvidenceByFinalItem.get(item);
	if (evidence === undefined) {
		clearPaintedSourceCorrelation(renderedItem);
		return;
	}
	stampRetainedPaintedEvidence(renderedItem, evidence);
}

function clearPaintedSourceCorrelation(renderedItem: BridgeMainRenderedItemReadback): void {
	try {
		renderedItem.element.removeAttribute(BRIDGE_PAINTED_PUBLICATION_ID_ATTRIBUTE);
		renderedItem.element.removeAttribute(BRIDGE_PAINTED_SOURCE_CORRELATIONS_ATTRIBUTE);
	} catch {
		// Packaged proof metadata is diagnostic-only and cannot gate product fulfillment.
	}
}

function stampRetainedPaintedEvidence(
	renderedItem: BridgeMainRenderedItemReadback,
	evidence: BridgeMainRetainedPaintedEvidence,
): void {
	try {
		clearPaintedSourceCorrelation(renderedItem);
		renderedItem.element.setAttribute(
			BRIDGE_PAINTED_SOURCE_CORRELATIONS_ATTRIBUTE,
			evidence.encodedSourceCorrelations,
		);
		renderedItem.element.setAttribute(
			BRIDGE_PAINTED_PUBLICATION_ID_ATTRIBUTE,
			evidence.publicationId,
		);
	} catch {
		// Packaged proof metadata is diagnostic-only and cannot gate product fulfillment.
	}
}

function paintedSourceCorrelationsForEntry(
	entry: BridgeMainPendingRenderPublication,
): readonly BridgeMainPaintedSourceCorrelation[] {
	return entry.publication.job.sourceCorrelations.map((sourceCorrelation) => ({
		...sourceCorrelation,
		disposition: 'painted',
		pierreItemId: entry.pierreItemId,
		publicationId: entry.publication.renderReceiptIdentity.publicationId,
		semanticItemId: entry.logicalItemId,
		surface: entry.publication.surface,
	}));
}

function assertBridgeMainRenderPublicationIdentity(publication: BridgeMainRenderPublication): void {
	const item = publication.job.payload.item;
	if (
		item.id.length === 0 ||
		item.bridgeMetadata.itemId !== publication.job.itemId ||
		publication.renderReceiptIdentity.itemId !== publication.job.itemId ||
		publication.renderReceiptIdentity.surface !== publication.surface ||
		publication.renderReceiptIdentity.publicationSequence !== publication.publicationSequence ||
		publication.renderReceiptIdentity.workerDerivationEpoch !== publication.workerDerivationEpoch
	) {
		throw new Error('Bridge main render publication carries mismatched item or receipt identity.');
	}
}

function findPendingPublicationByLogicalItemId(
	pendingByPierreItemId: ReadonlyMap<string, BridgeMainPendingRenderPublication>,
	logicalItemId: string,
): BridgeMainPendingRenderPublication | undefined {
	for (const entry of pendingByPierreItemId.values()) {
		if (entry.logicalItemId === logicalItemId) return entry;
	}
	return undefined;
}

function bridgeMainRenderReceiptIdentityKey(identity: BridgeWorkerRenderReceiptIdentity): string {
	return JSON.stringify([
		identity.attemptId,
		identity.itemId,
		identity.paneSessionId,
		identity.publicationId,
		identity.publicationSequence,
		identity.submissionId,
		identity.surface,
		identity.windowKey,
		identity.workerDerivationEpoch,
		identity.workerInstanceId,
	]);
}
