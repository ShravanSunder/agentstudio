import {
	BridgeCommWorkerReviewMetadataApplicator,
	type BridgeCommWorkerReviewMetadataApplication,
} from './bridge-comm-worker-review-metadata-applicator.js';
import type {
	BridgeCommWorkerReviewCandidateReadyPublication,
	BridgeCommWorkerReviewCandidateFailedPublication,
	BridgeCommWorkerReviewCandidateStartedPublication,
} from './bridge-comm-worker-review-publication-types.js';
import type { ReviewMetadataSubscription } from './bridge-comm-worker-runtime-protocol.review-product-transport.test-support.js';
import type { BridgeProductBatchFrameSinks } from './bridge-product-batch-frame-router.js';
import { BridgeProductBatchFrameRouter } from './bridge-product-batch-frame-router.js';
import {
	bridgeProductBatchFrameSchema,
	type BridgeProductBatchFrame,
} from './bridge-product-batch-wire-contracts.js';
import { bridgeProductReviewBatchRecordSchema } from './bridge-product-review-batch-record-contracts.js';
import type { BridgeProductReviewMetadataEvent } from './bridge-product-review-metadata-contracts.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import type { BridgeProductViewInstallation } from './bridge-product-view-batch-receiver.js';
import type { BridgeWorkerReviewDisplayPatch } from './bridge-worker-contracts.js';

type ReviewMetadataIdentity = Pick<
	BridgeProductReviewMetadataEvent,
	| 'generation'
	| 'operationCorrelationId'
	| 'packageId'
	| 'publicationId'
	| 'revision'
	| 'sourceIdentity'
>;
type ReviewSnapshotEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.snapshot' }
>;
type ReviewWindowEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.window' }
>;
type ReviewDeltaEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.delta' }
>;
type ReviewInvalidatedEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.invalidated' }
>;

export const workerDerivationEpoch = 31;
export const activeIdentity = reviewIdentity('active', 7, 11);
export const candidateIdentity = reviewIdentity('candidate', 8, 21);
let nextReviewTransactionStreamSequence = 0;
let nextReviewTransactionDeliverySequence = 0;
const pendingReviewTransactionInstalls = new Set<Promise<void>>();

export async function publishReviewTransactionBatch(
	router: BridgeProductBatchFrameRouter,
	installation: BridgeProductViewInstallation,
): Promise<void> {
	const begin = { ...installation.begin, streamSequence: ++nextReviewTransactionStreamSequence };
	router.accept(begin);
	const frameIdentity = {
		batchId: begin.batchId,
		domain: begin.domain,
		handle: begin.handle,
		incarnation: begin.incarnation,
		metadataStreamId: begin.metadataStreamId,
		paneSessionId: begin.paneSessionId,
		scopeRevision: begin.scopeRevision,
		subscriptionId: begin.subscriptionId,
		subscriptionKind: begin.subscriptionKind,
		wireVersion: begin.wireVersion,
		workerInstanceId: begin.workerInstanceId,
	};
	for (const [partIndex, record] of installation.records.entries()) {
		const part: BridgeProductBatchFrame = bridgeProductBatchFrameSchema.parse({
			...frameIdentity,
			deliverySequence: ++nextReviewTransactionDeliverySequence,
			kind: 'subscription.batchPart',
			part: { key: record.key, operation: 'put', revision: record.revision, value: record.value },
			partIndex,
			streamSequence: ++nextReviewTransactionStreamSequence,
		});
		router.accept(part);
	}
	router.accept(
		bridgeProductBatchFrameSchema.parse({
			...frameIdentity,
			coveredScope: begin.scope,
			kind: 'subscription.batchComplete',
			streamSequence: ++nextReviewTransactionStreamSequence,
		}),
	);
	await Promise.all(pendingReviewTransactionInstalls);
}

export function reviewTransactionBatch(
	subscriptionId: string,
	identity: ReviewMetadataIdentity,
	itemIds: readonly string[],
	incarnation = 'review-transaction-incarnation',
): BridgeProductViewInstallation {
	const templateItem = reviewBatchCorpus.records[0]?.record;
	const templatePublication = reviewBatchCorpus.records[2]?.record;
	const displayed =
		templatePublication?.recordKind === 'publication' ? templatePublication.displayed : undefined;
	if (templateItem?.recordKind !== 'item' || displayed === undefined || displayed === null) {
		throw new Error('Review transaction batch corpus is incomplete.');
	}
	const begin = bridgeProductBatchFrameSchema.parse({
		...sessionCorpus.transportV2.batchFrames[0],
		batchId: uuidv7(),
		baseRevision: 0,
		handle: 'review-transaction-handle',
		incarnation,
		mode: 'snapshot',
		partCount: itemIds.length + 1,
		publicationId: identity.publicationId,
		scope: { kind: 'review', interests: [] },
		subscriptionId,
		subscriptionKind: 'review.metadata',
		targetRevision: identity.revision,
	});
	if (begin.kind !== 'subscription.batchBegin')
		throw new Error('Review transaction batch begin missing.');
	const records = itemIds.map((itemId, sortKey) => ({
		key: itemId,
		revision: identity.revision,
		value: bridgeProductReviewBatchRecordSchema.parse({
			...templateItem,
			basePath: `Sources/${itemId}.swift`,
			contentByRole: {
				base: { state: 'absent' },
				diff: { state: 'absent' },
				file: { state: 'absent' },
				head: { state: 'absent' },
			},
			contentHashesByRole: {},
			extentByRole: { base: null, diff: null, file: null, head: null },
			headPath: `Sources/${itemId}.swift`,
			itemId,
			parentPath: 'Sources',
			sortKey,
		}),
	}));
	const publication = bridgeProductReviewBatchRecordSchema.parse({
		...templatePublication,
		desired: { reviewComparison: null, status: 'ready' },
		displayed: {
			...displayed,
			generation: identity.generation,
			packageId: identity.packageId,
			publicationId: identity.publicationId,
			query: { ...displayed.query, queryId: identity.sourceIdentity },
			revision: identity.revision,
			summary: {
				additions: itemIds.length,
				deletions: 0,
				filesChanged: itemIds.length,
				hiddenFileCount: 0,
				visibleFileCount: itemIds.length,
			},
		},
		publicationId: identity.publicationId,
		revision: identity.revision,
	});
	return {
		begin,
		domain: 'default',
		records: [...records, { key: 'publication', revision: identity.revision, value: publication }],
	};
}
export const reviewComparisonOrigin = {
	baseOID: 'contribution-base-oid',
	baseRole: 'commonCommit',
	comparedRole: 'capturedWorkingTree',
	kind: 'contribution',
	resolvedTargetOID: 'resolved-target-oid',
	reviewedHeadOID: 'reviewed-head-oid',
	symbolicTarget: { basis: 'commonCommit', kind: 'branch', name: 'integration' },
} as const;

export function makeApplicatorHarness(
	props: {
		readonly beforeApplyRuntimeSource?: (
			application: BridgeCommWorkerReviewMetadataApplication,
		) => void;
		readonly beforePublishDisplayPatches?: (publication: {
			readonly patches: readonly BridgeWorkerReviewDisplayPatch[];
			readonly reviewPublicationIdentity?: unknown;
			readonly workerDerivationEpoch: number;
		}) => void;
	} = {},
): {
	readonly applications: BridgeCommWorkerReviewMetadataApplication[];
	readonly applicator: BridgeCommWorkerReviewMetadataApplicator;
	readonly candidateReadyPublications: BridgeCommWorkerReviewCandidateReadyPublication[];
	readonly candidateFailedPublications: BridgeCommWorkerReviewCandidateFailedPublication[];
	readonly candidateStartedPublications: BridgeCommWorkerReviewCandidateStartedPublication[];
	readonly publicationOrder: Array<'display' | 'failed' | 'ready' | 'started'>;
	readonly displayPublications: Array<{
		readonly patches: readonly BridgeWorkerReviewDisplayPatch[];
		readonly reviewPublicationIdentity?: unknown;
		readonly workerDerivationEpoch: number;
	}>;
} {
	const applications: BridgeCommWorkerReviewMetadataApplication[] = [];
	const candidateReadyPublications: BridgeCommWorkerReviewCandidateReadyPublication[] = [];
	const candidateFailedPublications: BridgeCommWorkerReviewCandidateFailedPublication[] = [];
	const candidateStartedPublications: BridgeCommWorkerReviewCandidateStartedPublication[] = [];
	const publicationOrder: Array<'display' | 'failed' | 'ready' | 'started'> = [];
	const displayPublications: Array<{
		readonly patches: readonly BridgeWorkerReviewDisplayPatch[];
		readonly reviewPublicationIdentity?: unknown;
		readonly workerDerivationEpoch: number;
	}> = [];
	return {
		applications,
		applicator: new BridgeCommWorkerReviewMetadataApplicator({
			applyRuntimeSource: (application): void => {
				props.beforeApplyRuntimeSource?.(application);
				applications.push(application);
			},
			currentWorkerDerivationEpoch: (): number => workerDerivationEpoch,
			publishCandidateReady: (publication): void => {
				candidateReadyPublications.push(publication);
				publicationOrder.push('ready');
			},
			publishCandidateFailed: (publication): void => {
				candidateFailedPublications.push(publication);
				publicationOrder.push('failed');
			},
			publishCandidateStarted: (publication): void => {
				candidateStartedPublications.push(publication);
				publicationOrder.push('started');
			},
			publishDisplayPatches: (publication): void => {
				props.beforePublishDisplayPatches?.(publication);
				displayPublications.push(publication);
				if (publication.reviewPublicationIdentity !== null) publicationOrder.push('display');
			},
		}),
		candidateReadyPublications,
		candidateFailedPublications,
		candidateStartedPublications,
		displayPublications,
		publicationOrder,
	};
}

export function reviewIdentity(
	label: string,
	generation: number,
	revision: number,
): ReviewMetadataIdentity {
	return {
		generation,
		operationCorrelationId: null,
		packageId: `package-${label}`,
		publicationId: reviewPublicationId(revision),
		revision,
		sourceIdentity: `source-${label}`,
	};
}

export function reviewReset(
	identity: ReviewMetadataIdentity,
	refreshImpact?: {
		readonly addedLineCount: number | null;
		readonly affectedFileCount: number | null;
		readonly affectedStableFileIdentities: readonly string[];
		readonly deletedLineCount: number | null;
		readonly newlyImportedCommitCount: number | null;
		readonly preDeliveryPresentationClass:
			| { readonly kind: 'ordinary' }
			| {
					readonly kind: 'promoted';
					readonly reason: 'commits' | 'files' | 'lines' | 'unknown';
			  };
	},
): BridgeProductReviewMetadataEvent {
	return {
		...identity,
		...refreshImpact,
		comparisonOrigin: reviewComparisonOrigin,
		eventKind: 'review.reset',
		operationCorrelationId: null,
		reason: 'sourceChanged',
		reviewedSubjectLabel: 'feature/review-comments',
	};
}

export function reviewSourceAccepted(
	identity: ReviewMetadataIdentity,
): BridgeProductReviewMetadataEvent {
	return { ...identity, eventKind: 'review.sourceAccepted' };
}

export function reviewSnapshot(
	identity: ReviewMetadataIdentity,
	itemId: string,
	startIndex: number,
	totalItemCount: number,
	finalWindow: boolean,
): ReviewSnapshotEvent {
	return {
		...reviewPayload(identity, itemId, startIndex, totalItemCount, finalWindow),
		baseEndpoint: reviewEndpoint('base', 'gitRef'),
		comparisonOrigin: reviewComparisonOrigin,
		eventKind: 'review.snapshot',
		operationCorrelationId: null,
		headEndpoint: reviewEndpoint('head', 'workingTree'),
		query: reviewQuery(),
		reviewedSubjectLabel: 'feature/review-comments',
	};
}

export function reviewWindow(
	identity: ReviewMetadataIdentity,
	itemId: string,
	startIndex: number,
	totalItemCount: number,
	finalWindow: boolean,
): ReviewWindowEvent {
	return {
		...reviewPayload(identity, itemId, startIndex, totalItemCount, finalWindow),
		eventKind: 'review.window',
		operationCorrelationId: null,
	};
}

export function reviewDelta(
	identity: ReviewMetadataIdentity,
	toRevision: number,
): ReviewDeltaEvent {
	return {
		...identity,
		addedLineCount: 0,
		affectedFileCount: 0,
		affectedStableFileIdentities: [],
		contentSources: [],
		deletedLineCount: 0,
		eventKind: 'review.delta',
		operationCorrelationId: null,
		fromRevision: identity.revision,
		operations: [],
		newlyImportedCommitCount: 0,
		preDeliveryPresentationClass: { kind: 'ordinary' },
		presentationRevision: toRevision,
		publicationId: reviewPublicationId(toRevision),
		revision: toRevision,
		reviewComparison: null,
		summary: reviewSummary(1),
		toRevision,
	};
}

export function reviewPublicationId(sequence: number): string {
	return `00000000-0000-7000-8000-${sequence.toString().padStart(12, '0')}`;
}

export function reviewInvalidated(identity: ReviewMetadataIdentity): ReviewInvalidatedEvent {
	return {
		...identity,
		eventKind: 'review.invalidated',
		operationCorrelationId: null,
		itemIds: [],
		pathHints: [],
		reason: 'watchEvent',
		scope: 'package',
	};
}

function reviewPayload(
	identity: ReviewMetadataIdentity,
	itemId: string,
	startIndex: number,
	totalItemCount: number,
	finalWindow: boolean,
): Omit<ReviewWindowEvent, 'eventKind'> {
	const path = `Sources/${itemId}.swift`;
	return {
		...identity,
		contentSources: [],
		extentFacts: [],
		itemMetadata: [
			{
				additions: 1,
				deletions: 1,
				basePath: path,
				changeKind: 'modified' as const,
				contentDescriptorIdsByRole: {},
				contentHashesByRole: {},
				contentRoles: [],
				extension: 'swift',
				fileClass: 'source' as const,
				headPath: path,
				isHiddenByDefault: false,
				itemId,
				language: 'swift',
				mimeTypes: ['text/plain'],
				provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
				reviewPriority: 'normal' as const,
				reviewState: 'unreviewed' as const,
			},
		],
		itemWindow: { finalWindow, itemCount: 1, startIndex, totalItemCount },
		...(finalWindow ? { presentationRevision: identity.revision, reviewComparison: null } : {}),
		revision: identity.revision,
		summary: reviewSummary(totalItemCount),
		treeRows: [{ depth: 0, isDirectory: false, itemId, path, rowId: `row-${itemId}` }],
		treeWindow: {
			finalWindow,
			rowCount: 1,
			startIndex,
			totalRowCount: totalItemCount,
		},
	};
}

function reviewSummary(totalItemCount: number): ReviewSnapshotEvent['summary'] {
	return {
		additions: totalItemCount,
		deletions: 0,
		filesChanged: totalItemCount,
		hiddenFileCount: 0,
		visibleFileCount: totalItemCount,
	};
}

function reviewEndpoint(
	endpointId: string,
	kind: 'gitRef' | 'workingTree',
): ReviewSnapshotEvent['baseEndpoint'] {
	return {
		createdAtUnixMilliseconds: 1,
		endpointId,
		kind,
		label: endpointId,
		providerIdentity: `${endpointId}-provider`,
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
	};
}

function reviewQuery(): ReviewSnapshotEvent['query'] {
	return {
		baseEndpointId: 'base',
		comparisonSemantics: 'threeDot',
		fileTarget: null,
		grouping: { kind: 'folder' },
		headEndpointId: 'head',
		pathScope: [],
		provenanceFilter: {
			agentSessionIds: [],
			operationIds: [],
			paneIds: [],
			promptIds: [],
			sourceKinds: [],
		},
		queryId: 'query-1',
		queryKind: 'compare',
		repoId: 'repo-1',
		viewFilter: {
			changeKinds: [],
			excludedExtensions: [],
			excludedFileClasses: [],
			excludedPathGlobs: [],
			includedExtensions: [],
			includedFileClasses: [],
			includedPathGlobs: [],
			reviewStates: [],
			showBinaryFiles: true,
			showHiddenFiles: false,
			showLargeFiles: true,
		},
		worktreeId: 'worktree-1',
	};
}

export function reviewMetadataTransport(
	reviewSubscription: ReviewMetadataSubscription | readonly ReviewMetadataSubscription[],
	onSubscriptionOpened: () => void = (): void => {},
	onPublicationApplied: () => void = (): void => {},
	onBatchFrameSinks: (sinks: BridgeProductBatchFrameSinks) => void = (): void => {},
	onResnapshot: () => void = (): void => {},
): BridgeProductTransportSession {
	let reviewWorkerDerivationEpoch = 0;
	let subscriptionIndex = 0;
	const reviewSubscriptions = Array.isArray(reviewSubscription)
		? reviewSubscription
		: [reviewSubscription];
	return {
		advanceWorkerDerivationEpoch: (surface): number => {
			if (surface === 'review') reviewWorkerDerivationEpoch += 1;
			return surface === 'review' ? reviewWorkerDerivationEpoch : 0;
		},
		call: async (...arguments_): Promise<never> => {
			const [method] = arguments_;
			if (method === 'review.activeViewerMode.update') {
				return null as never;
			}
			if (method === 'review.publication.applied') {
				onPublicationApplied();
				// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- This transaction fake accepts only the closed null-result receipt call.
				return null as never;
			}
			throw new Error('Unexpected product call in metadata transaction staging.');
		},
		openContent: (): never => {
			throw new Error('Review content is outside metadata transaction staging.');
		},
		setBatchFrameSinks: (sinks): void =>
			onBatchFrameSinks({
				...sinks,
				install: (installation): Promise<void> => {
					const install = Promise.resolve().then(() => sinks.install(installation));
					const settled = install.then(
						(): void => {},
						(): void => {},
					);
					pendingReviewTransactionInstalls.add(settled);
					void settled.finally((): void => {
						pendingReviewTransactionInstalls.delete(settled);
					});
					return install;
				},
			}),
		resnapshotView: async (request) => {
			onResnapshot();
			return {
				...request,
				kind: 'subscription.resnapshotAccepted' as const,
				paneSessionId: 'review-transaction-pane',
				requestId: uuidv7(),
				requestSequence: 1,
				wireVersion: 2 as const,
				workerInstanceId: 'review-transaction-worker',
			};
		},
		subscribe: (...arguments_): never => {
			const [{ kind: subscriptionKind }] = arguments_;
			if (subscriptionKind !== 'review.metadata') {
				throw new Error(`Unexpected product subscription ${subscriptionKind}.`);
			}
			const subscription = reviewSubscriptions[subscriptionIndex];
			if (subscription === undefined) {
				throw new Error('Unexpected additional Review metadata subscription.');
			}
			subscriptionIndex += 1;
			onSubscriptionOpened();
			// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- This closed fake returns only Review metadata subscriptions.
			return subscription as never;
		},
		workerDerivationEpoch: (surface): number =>
			surface === 'review' ? reviewWorkerDerivationEpoch : 0,
	};
}
import { uuidv7 } from 'uuidv7';

import reviewBatchCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-review-batch-record-corpus.json' with { type: 'json' };
import sessionCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-session-corpus.json' with { type: 'json' };
