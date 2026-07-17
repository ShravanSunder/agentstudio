import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerMetadataInterestUpdateCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	makeImmediateReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductReviewItemMetadata } from './bridge-product-review-metadata-contracts.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';

describe('Bridge comm worker Review product runtime', () => {
	test('opens Review content when Review interaction epochs restart after File interaction', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const openedContentKinds: string[] = [];
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-subscription-cross-surface-epoch',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeProductTransport({
				initialReviewEpoch: 40,
				openedContentKinds,
				reviewSubscription,
				subscribedKinds: [],
			}),
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
		});
		await flushBridgeWorkerRuntimeContinuations();
		events.push(reviewSnapshotWithContentEvent);
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toHaveLength(1);
		await requirePreparationDrain(scheduledDrains.shift())();
		await flushBridgeWorkerRuntimeContinuations();

		// Act
		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				epoch: 20,
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
				requestId: 'request-file-interaction-20',
				surface: 'fileView',
				visibleItemIds: [],
			}),
		);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 1,
				requestId: 'request-review-selection-1',
				selectedItemId: 'item-1',
				selectedSource: 'user',
				surface: 'review',
			}),
		);
		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				epoch: 2,
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
				requestId: 'request-review-viewport-2',
				surface: 'review',
				visibleItemIds: ['item-1'],
			}),
		);
		await drainBridgeCommWorkerPreparationUntilIdle(scheduledDrains);
		events.close(true);
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(openedContentKinds).toContain('review.content');
		const reviewContentPublications = postedMessages
			.map(({ message }) => message)
			.filter(
				(message) =>
					message.kind === 'reviewPierreRenderJob' || message.kind === 'reviewRenderPatch',
			);
		expect(reviewContentPublications).not.toEqual([]);
		expect(
			reviewContentPublications.map((publication) => publication.workerDerivationEpoch),
		).toEqual(reviewContentPublications.map(() => 41));
	});

	test('projects typed Review subscription snapshots into worker-owned source truth', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const subscribedKinds: string[] = [];
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-subscription-1',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeProductTransport({ reviewSubscription, subscribedKinds }),
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
		});

		// Act
		dispatch.message(
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				epoch: 1,
				request: {
					generation: 7,
					itemIds: ['item-1'],
					lane: 'foreground',
					loaded_by: 'foreground',
					protocol: 'review',
					streamId: 'review-stream-1',
				},
				requestId: 'request-review-interest-1',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		expect(subscribedKinds).toEqual(['review.metadata']);
		events.push(reviewSnapshotEvent);
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(scheduledDrains).toHaveLength(1);
		const reviewDisplayEvents = postedMessages
			.map(({ message }) => message as unknown as Readonly<Record<string, unknown>>)
			.filter((message) => message['kind'] === 'reviewDisplayPatch');
		expect(reviewDisplayEvents).toHaveLength(1);
		expect(reviewDisplayEvents[0]).toMatchObject({
			epoch: 1,
			kind: 'reviewDisplayPatch',
			patches: [
				{
					operation: 'upsert',
					payload: {
						metadataWindowIdentity: JSON.stringify([
							'bridge-review-metadata-window-v1',
							'source-1',
							7,
							'00000000-0000-7000-8000-000000000011',
							11,
						]),
						status: 'ready',
						totalItemCount: 1,
						totalTreeRowCount: 1,
					},
					slice: 'reviewSource',
				},
				expect.objectContaining({ operation: 'batch', slice: 'reviewItem' }),
				expect.objectContaining({ operation: 'batch', slice: 'reviewTree' }),
			],
			projectionRevision: 1,
			surface: 'review',
		});
		expect(JSON.stringify(reviewDisplayEvents)).not.toMatch(
			/"(?:capability|resourceUrl|contents|contentBody|sourceBytes)"/i,
		);
	});

	test('publishes a bounded Review display failure when the product subscription fails', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-subscription-failure',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeProductTransport({ reviewSubscription, subscribedKinds: [] }),
		});
		await flushBridgeWorkerRuntimeContinuations();

		// Act
		events.fail(new Error('private transport failure detail'), true);
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		const reviewDisplayEvents = postedMessages
			.map(({ message }) => message as unknown as Readonly<Record<string, unknown>>)
			.filter((message) => message['kind'] === 'reviewDisplayPatch');
		expect(reviewDisplayEvents.at(-1)).toMatchObject({
			kind: 'reviewDisplayPatch',
			patches: [
				{
					operation: 'failed',
					payload: { error: 'metadataUnavailable', status: 'failed' },
					slice: 'reviewSource',
				},
			],
			surface: 'review',
		});
		expect(JSON.stringify(reviewDisplayEvents)).not.toContain('private transport failure detail');
	});
});

function makeProductTransport(props: {
	readonly initialReviewEpoch?: number;
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

const reviewItemMetadata = {
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

const reviewSnapshotEvent = {
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

const reviewContentSource = {
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

const reviewBaseContentSource = {
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

const reviewSnapshotWithContentEvent = {
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

function requirePreparationDrain(
	drain: BridgeCommWorkerPreparationDrain | undefined,
): BridgeCommWorkerPreparationDrain {
	if (drain === undefined) throw new Error('Expected a Bridge comm-worker preparation drain.');
	return drain;
}

async function drainBridgeCommWorkerPreparationUntilIdle(
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
