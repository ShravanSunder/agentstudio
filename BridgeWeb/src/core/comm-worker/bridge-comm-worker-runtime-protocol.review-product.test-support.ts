import { expect } from 'vitest';

import type { BridgeCommWorkerPreparationDrain } from './bridge-comm-worker-runtime-protocol.js';
import {
	flushBridgeWorkerRuntimeContinuations,
	makeImmediateReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import type { BridgeProductReviewItemMetadata } from './bridge-product-review-metadata-contracts.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type {
	BridgeProductContentStream,
	BridgeProductSubscription,
} from './bridge-product-transport-contract.js';
import type {
	BridgeProductPanePresentationFrame,
	BridgeProductTransportSession,
} from './bridge-product-transport.js';

export interface PendingReviewContentAttempt {
	readonly abortSignal: AbortSignal;
	readonly descriptorId: string;
}

export function makeProductTransport(props: {
	readonly initialReviewEpoch?: number;
	readonly onPanePresentationSink?: (
		sink: (frame: BridgeProductPanePresentationFrame) => void,
	) => void;
	readonly openedContentKinds?: string[];
	readonly reviewSubscription: BridgeProductSubscription<'review.metadata'>;
	readonly subscribedKinds: string[];
}): BridgeProductTransportSession {
	let reviewEpoch = props.initialReviewEpoch ?? 0;
	return {
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'review') reviewEpoch += 1;
			return surface === 'review' ? reviewEpoch : 0;
		},
		call: async (): Promise<never> => ({ reason: 'notConfigured', status: 'unavailable' }) as never,
		openContent: (descriptor) => {
			if (descriptor.contentKind !== 'review.content') {
				throw new Error(`Unexpected product content kind ${descriptor.contentKind}.`);
			}
			props.openedContentKinds?.push(descriptor.contentKind);
			return makeImmediateReviewContentStream(descriptor, 'hello world\n') as never;
		},
		setPanePresentationFrameSink: (sink): void => {
			props.onPanePresentationSink?.(sink);
			sink(makePanePresentationFrame(1, 'foreground'));
		},
		subscribe: (...arguments_): never => {
			const [subscriptionKind] = arguments_;
			props.subscribedKinds.push(subscriptionKind);
			if (subscriptionKind !== 'review.metadata') {
				throw new Error(`Unexpected product subscription ${subscriptionKind}.`);
			}
			return props.reviewSubscription as never;
		},
		workerDerivationEpoch: (surface): number => (surface === 'review' ? reviewEpoch : 0),
	};
}

export function makePendingReviewContentStream(props: {
	readonly abortSignal: AbortSignal;
	readonly attempts: PendingReviewContentAttempt[];
	readonly descriptorId: string;
}): BridgeProductContentStream<'review.content'> {
	props.attempts.push({
		abortSignal: props.abortSignal,
		descriptorId: props.descriptorId,
	});
	return {
		contentKind: 'review.content',
		contentRequestId: `review-content-request-${props.attempts.length}`,
		frames: emptyReviewContentFrames(),
		terminal: new Promise((_, reject): void => {
			props.abortSignal.addEventListener('abort', (): void => reject(props.abortSignal.reason), {
				once: true,
			});
		}),
	};
}

export async function drainUntilReviewAttemptCount(props: {
	readonly attempts: readonly PendingReviewContentAttempt[];
	readonly expectedCount: number;
	readonly scheduledDrains: BridgeCommWorkerPreparationDrain[];
}): Promise<void> {
	const activeAttempts = props.attempts.filter(({ abortSignal }) => !abortSignal.aborted);
	if (activeAttempts.length >= props.expectedCount || props.scheduledDrains.length === 0) {
		expect(activeAttempts).toHaveLength(props.expectedCount);
		return;
	}
	const drain = props.scheduledDrains.shift();
	if (drain === undefined) throw new Error('Expected scheduled Review preparation drain.');
	void drain();
	await flushBridgeWorkerRuntimeContinuations();
	await drainUntilReviewAttemptCount(props);
}

export function expectOriginalReviewContentAttemptsRemainActive(
	attempts: readonly PendingReviewContentAttempt[],
): void {
	expect(attempts.map(({ descriptorId }) => descriptorId)).toEqual([
		'review-descriptor-item-1-base',
		'review-descriptor-item-1-head',
	]);
	expect(attempts.every(({ abortSignal }) => !abortSignal.aborted)).toBe(true);
}

export function requirePanePresentationSink(
	sink: ((frame: BridgeProductPanePresentationFrame) => void) | null,
): (frame: BridgeProductPanePresentationFrame) => void {
	if (sink === null) throw new Error('Expected Bridge pane presentation sink registration.');
	return sink;
}

export function makePanePresentationFrame(
	presentationRevision: number,
	nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
): BridgeProductPanePresentationFrame {
	return {
		presentationRevision,
		kind: 'pane.presentation',
		metadataStreamId: 'metadata-stream-review-pane-suppression',
		nativeActivity,
		paneSessionId: 'pane-session-review-pane-suppression',
		refreshingLanes: [],
		reviewComparison: null,
		streamSequence: presentationRevision,
		wireVersion: 2,
		workerInstanceId: 'worker-instance-review-pane-suppression',
	};
}

async function* emptyReviewContentFrames(): AsyncIterable<never> {}

export const reviewItemMetadata = {
	basePath: 'Sources/App.swift',
	changeKind: 'modified',
	contentDescriptorIdsByRole: {},
	contentHashesByRole: {},
	contentRoles: [],
	extension: 'swift',
	fileClass: 'source',
	headPath: 'Sources/App.swift',
	isHiddenByDefault: false,
	itemId: 'item-1',
	language: 'swift',
	mimeTypes: ['text/plain'],
	provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
	reviewPriority: 'normal',
	reviewState: 'unreviewed',
} satisfies BridgeProductReviewItemMetadata;

export const reviewSnapshotEvent = {
	baseEndpoint: {
		createdAtUnixMilliseconds: 1,
		endpointId: 'base',
		kind: 'gitRef',
		label: 'base',
		providerIdentity: 'base-provider',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
	},
	contentSources: [],
	eventKind: 'review.snapshot',
	extentFacts: [],
	generation: 7,
	headEndpoint: {
		createdAtUnixMilliseconds: 1,
		endpointId: 'head',
		kind: 'workingTree',
		label: 'head',
		providerIdentity: 'head-provider',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
	},
	itemMetadata: [reviewItemMetadata],
	itemWindow: { finalWindow: true, itemCount: 1, startIndex: 0, totalItemCount: 1 },
	packageId: 'package-1',
	publicationId: '00000000-0000-7000-8000-000000000011',
	query: {
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
	},
	revision: 11,
	sourceIdentity: 'source-1',
	summary: {
		additions: 1,
		deletions: 1,
		filesChanged: 1,
		hiddenFileCount: 0,
		visibleFileCount: 1,
	},
	treeRows: [
		{
			depth: 0,
			isDirectory: false,
			itemId: 'item-1',
			path: 'Sources/App.swift',
			rowId: 'row-1',
		},
	],
	treeWindow: { finalWindow: true, rowCount: 1, startIndex: 0, totalRowCount: 1 },
} satisfies BridgeProductSubscriptionEvent<'review.metadata'>;

export const reviewEmptySnapshotEvent = {
	...reviewSnapshotEvent,
	contentSources: [],
	extentFacts: [],
	itemMetadata: [],
	itemWindow: { finalWindow: true, itemCount: 0, startIndex: 0, totalItemCount: 0 },
	summary: {
		additions: 0,
		deletions: 0,
		filesChanged: 0,
		hiddenFileCount: 0,
		visibleFileCount: 0,
	},
	treeRows: [],
	treeWindow: { finalWindow: true, rowCount: 0, startIndex: 0, totalRowCount: 0 },
} satisfies BridgeProductSubscriptionEvent<'review.metadata'>;

export const reviewContentSource = {
	contentDigest: {
		algorithm: 'sha256',
		authority: 'authoritative',
		value: 'a'.repeat(64),
	},
	contentKind: 'review.content',
	descriptorId: 'review-descriptor-item-1-head',
	encoding: 'utf-8',
	endpointId: 'head',
	handleId: 'review-handle-item-1-head',
	isBinary: false,
	itemId: 'item-1',
	language: 'swift',
	mimeType: 'text/plain',
	packageId: 'package-1',
	reviewGeneration: 7,
	role: 'head',
	sourceIdentity: 'source-1',
	wholeByteLength: 12,
} as const;

export const reviewBaseContentSource = {
	...reviewContentSource,
	contentDigest: {
		algorithm: 'sha256',
		authority: 'authoritative',
		value: 'b'.repeat(64),
	},
	descriptorId: 'review-descriptor-item-1-base',
	endpointId: 'base',
	handleId: 'review-handle-item-1-base',
	role: 'base',
} as const;

export const reviewSnapshotWithContentEvent = {
	...reviewSnapshotEvent,
	contentSources: [reviewBaseContentSource, reviewContentSource],
	extentFacts: [
		{ contentRole: 'base', itemId: 'item-1', lineCount: 1 },
		{ contentRole: 'head', itemId: 'item-1', lineCount: 1 },
	],
	itemMetadata: [
		{
			...reviewItemMetadata,
			contentDescriptorIdsByRole: {
				base: reviewBaseContentSource.descriptorId,
				head: reviewContentSource.descriptorId,
			},
			contentHashesByRole: {
				base: reviewBaseContentSource.contentDigest.value,
				head: reviewContentSource.contentDigest.value,
			},
			contentRoles: ['base', 'head'],
		},
	],
} satisfies BridgeProductSubscriptionEvent<'review.metadata'>;

export async function drainBridgeCommWorkerPreparationUntilIdle(
	scheduledDrains: BridgeCommWorkerPreparationDrain[],
): Promise<void> {
	const drainCompletions: Array<ReturnType<BridgeCommWorkerPreparationDrain>> = [];
	for (let drainRound = 0; drainRound < 16; drainRound += 1) {
		const drainsForRound = scheduledDrains.splice(0);
		if (drainsForRound.length > 0) {
			drainCompletions.push(...drainsForRound.map((drain) => drain()));
		}
		// oxlint-disable-next-line no-await-in-loop -- Each bounded round exposes the event-scheduled follow-up drains for the next round.
		await flushBridgeWorkerRuntimeContinuations();
		if (scheduledDrains.length === 0) break;
	}
	expect(scheduledDrains).toEqual([]);
	await Promise.all(drainCompletions);
	await flushBridgeWorkerRuntimeContinuations();
}

export async function startBridgeCommWorkerPreparationDrains(
	scheduledDrains: BridgeCommWorkerPreparationDrain[],
): Promise<void> {
	for (let drainRound = 0; drainRound < 16; drainRound += 1) {
		for (const drain of scheduledDrains.splice(0)) void drain();
		// oxlint-disable-next-line no-await-in-loop -- Each bounded round exposes event-scheduled follow-up drains.
		await flushBridgeWorkerRuntimeContinuations();
		if (scheduledDrains.length === 0) return;
	}
	expect(scheduledDrains).toEqual([]);
}
