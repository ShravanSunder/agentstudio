import { describe, expect, test } from 'vitest';

import { expectedEmptyReviewProjectionResetPatches } from './bridge-comm-worker-entry.test-support.js';
import {
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerMetadataInterestUpdateCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import {
	drainBridgeCommWorkerPreparationUntilIdle,
	drainUntilReviewAttemptCount,
	expectOriginalReviewContentAttemptsRemainActive,
	makePanePresentationFrame,
	makePendingReviewContentStream,
	makeProductTransport,
	requirePanePresentationSink,
	reviewEmptySnapshotEvent,
	reviewSnapshotEvent,
	reviewSnapshotWithContentEvent,
	startBridgeCommWorkerPreparationDrains,
	type PendingReviewContentAttempt,
} from './bridge-comm-worker-runtime-protocol.review-product.test-support.js';
import {
	activateBridgeCommWorkerReviewViewerMode,
	assertBridgeCommWorkerPreparationDrain,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	makeImmediateReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductPanePresentationFrame } from './bridge-product-transport.js';

describe('Bridge comm worker Review product runtime', () => {
	test('opens Review content when Review interaction epochs restart after File interaction', async () => {
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
		activateBridgeCommWorkerReviewViewerMode(dispatch, 'cross-surface-epoch');
		await flushBridgeWorkerRuntimeContinuations();
		events.push(reviewSnapshotWithContentEvent);
		await flushBridgeWorkerRuntimeContinuations();
		expect(scheduledDrains).toHaveLength(1);
		await assertBridgeCommWorkerPreparationDrain(scheduledDrains.shift())();
		await flushBridgeWorkerRuntimeContinuations();

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
		activateBridgeCommWorkerReviewViewerMode(dispatch, 'source-truth');

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

	test('publishes a ready empty Review source when the snapshot has no changed files', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-subscription-empty-source',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeProductTransport({ reviewSubscription, subscribedKinds: [] }),
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
		});
		activateBridgeCommWorkerReviewViewerMode(dispatch, 'empty-source');

		dispatch.message(
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				epoch: 1,
				request: {
					generation: 7,
					itemIds: [],
					lane: 'foreground',
					loaded_by: 'foreground',
					protocol: 'review',
					streamId: 'review-stream-empty-source',
				},
				requestId: 'request-review-interest-empty-source',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		events.push(reviewEmptySnapshotEvent);
		await flushBridgeWorkerRuntimeContinuations();

		const reviewDisplayEvents = postedMessages
			.map(({ message }) => message as unknown as Readonly<Record<string, unknown>>)
			.filter((message) => message['kind'] === 'reviewDisplayPatch');
		expect(scheduledDrains).toHaveLength(1);
		expect(reviewDisplayEvents).toHaveLength(1);
		expect(reviewDisplayEvents[0]).toMatchObject({
			kind: 'reviewDisplayPatch',
			patches: [
				{
					operation: 'upsert',
					payload: {
						status: 'ready',
						totalItemCount: 0,
						totalTreeRowCount: 0,
					},
					slice: 'reviewSource',
				},
				{
					operation: 'batch',
					payload: { items: [], operations: [], reset: true },
					slice: 'reviewItem',
				},
				{
					operation: 'batch',
					payload: { reset: true, windows: [{ rows: [] }] },
					slice: 'reviewTree',
				},
			],
			epoch: 1,
			surface: 'review',
		});
	});

	test('publishes a bounded Review display failure when the product subscription fails', async () => {
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
				...expectedEmptyReviewProjectionResetPatches(),
			],
			surface: 'review',
		});
		expect(JSON.stringify(reviewDisplayEvents)).not.toContain('private transport failure detail');
	});

	test('does not replay completed Review preparation or reset when native foreground returns to File', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const openedDescriptorIds: string[] = [];
		let panePresentationSink: ((frame: BridgeProductPanePresentationFrame) => void) | null = null;
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-subscription-completed-foreground-return',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			openReviewContent: (descriptor) => {
				openedDescriptorIds.push(descriptor.descriptorId);
				return makeImmediateReviewContentStream(descriptor, 'hello world\n');
			},
			productTransport: makeProductTransport({
				onPanePresentationSink: (sink): void => {
					panePresentationSink = sink;
				},
				reviewSubscription,
				subscribedKinds: [],
			}),
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
			sendProductControl: async (): Promise<void> => {},
		});
		await flushBridgeWorkerRuntimeContinuations();
		events.push(reviewSnapshotWithContentEvent);
		await flushBridgeWorkerRuntimeContinuations();
		await drainBridgeCommWorkerPreparationUntilIdle(scheduledDrains);
		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 1,
				requestId: 'request-review-mode-before-completed-preparation',
				update: {
					activeSource: null,
					mode: 'review',
					nativeSelectionRequestId: null,
					sequence: 1,
					sessionId: 'review-completed-foreground-return-session',
				},
			}),
		);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 2,
				requestId: 'request-review-completed-foreground-return-selection',
				selectedItemId: 'item-1',
				selectedSource: 'user',
				surface: 'review',
			}),
		);
		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				epoch: 3,
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
				requestId: 'request-review-completed-foreground-return-viewport',
				surface: 'review',
				visibleItemIds: ['item-1'],
			}),
		);
		await drainBridgeCommWorkerPreparationUntilIdle(scheduledDrains);
		const completedOpenCount = openedDescriptorIds.length;
		expect(completedOpenCount).toBeGreaterThan(0);

		// Act
		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 4,
				requestId: 'request-file-mode-before-review-foreground-return',
				update: {
					activeSource: null,
					mode: 'file',
					nativeSelectionRequestId: null,
					sequence: 2,
					sessionId: 'review-completed-foreground-return-session',
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		const messageCountBeforeNativeCycle = postedMessages.length;
		requirePanePresentationSink(panePresentationSink)(makePanePresentationFrame(2, 'loadedHidden'));
		requirePanePresentationSink(panePresentationSink)(makePanePresentationFrame(3, 'foreground'));
		await drainBridgeCommWorkerPreparationUntilIdle(scheduledDrains);

		// Assert
		expect(openedDescriptorIds).toHaveLength(completedOpenCount);
		expect(
			postedMessages
				.slice(messageCountBeforeNativeCycle)
				.map(({ message }) => message)
				.filter(
					(message) =>
						message.kind === 'reviewPierreRenderJob' ||
						(message.kind === 'reviewRenderPatch' &&
							message.patches.some((patch): boolean => patch.slice !== 'panelChrome')),
				),
		).toEqual([]);
	});

	test('pauses and resumes one selected-visible Review preparation without restarting transport', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const attempts: PendingReviewContentAttempt[] = [];
		let panePresentationSink: ((frame: BridgeProductPanePresentationFrame) => void) | null = null;
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-subscription-pane-suppression',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			openReviewContent: (descriptor, abortSignal) =>
				makePendingReviewContentStream({
					abortSignal,
					attempts,
					descriptorId: descriptor.descriptorId,
				}),
			productTransport: makeProductTransport({
				onPanePresentationSink: (sink): void => {
					panePresentationSink = sink;
				},
				reviewSubscription,
				subscribedKinds: [],
			}),
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
			sendProductControl: async (): Promise<void> => {},
		});
		activateBridgeCommWorkerReviewViewerMode(dispatch, 'pane-suppression');
		await flushBridgeWorkerRuntimeContinuations();
		events.push(reviewSnapshotWithContentEvent);
		await flushBridgeWorkerRuntimeContinuations();
		await startBridgeCommWorkerPreparationDrains(scheduledDrains);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 1,
				requestId: 'request-review-pane-suppression-selection',
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
				requestId: 'request-review-pane-suppression-viewport',
				surface: 'review',
				visibleItemIds: ['item-1'],
			}),
		);
		await drainUntilReviewAttemptCount({ attempts, expectedCount: 2, scheduledDrains });
		const messageCountBeforeSuppression = postedMessages.length;

		// Act
		requirePanePresentationSink(panePresentationSink)(makePanePresentationFrame(2, 'loadedHidden'));
		await flushBridgeWorkerRuntimeContinuations();
		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 3,
				requestId: 'request-hidden-review-active-viewer-mode',
				update: {
					activeSource: null,
					mode: 'review',
					nativeSelectionRequestId: null,
					sequence: 3,
					sessionId: 'hidden-review-session',
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expectOriginalReviewContentAttemptsRemainActive(attempts);
		expect(
			postedMessages
				.slice(messageCountBeforeSuppression)
				.map(({ message }) => message)
				.filter((message) => message.kind === 'reviewRenderPatch'),
		).toEqual([]);

		// Act
		requirePanePresentationSink(panePresentationSink)(makePanePresentationFrame(3, 'foreground'));
		await flushBridgeWorkerRuntimeContinuations();
		requirePanePresentationSink(panePresentationSink)(makePanePresentationFrame(3, 'foreground'));
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expectOriginalReviewContentAttemptsRemainActive(attempts);
	});

	test('pauses active Review content while File is accepted and resumes the same transport', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const attempts: PendingReviewContentAttempt[] = [];
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-subscription-active-surface-lifecycle',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			openReviewContent: (descriptor, abortSignal) =>
				makePendingReviewContentStream({
					abortSignal,
					attempts,
					descriptorId: descriptor.descriptorId,
				}),
			productTransport: makeProductTransport({ reviewSubscription, subscribedKinds: [] }),
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
			sendProductControl: async (): Promise<void> => {},
		});
		await flushBridgeWorkerRuntimeContinuations();
		events.push(reviewSnapshotWithContentEvent);
		await flushBridgeWorkerRuntimeContinuations();
		await startBridgeCommWorkerPreparationDrains(scheduledDrains);
		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 1,
				requestId: 'request-review-active-surface',
				update: {
					activeSource: null,
					mode: 'review',
					nativeSelectionRequestId: null,
					sequence: 1,
					sessionId: 'active-surface-lifecycle-session',
				},
			}),
		);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 2,
				requestId: 'request-review-active-surface-selection',
				selectedItemId: 'item-1',
				selectedSource: 'user',
				surface: 'review',
			}),
		);
		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				epoch: 3,
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
				requestId: 'request-review-active-surface-viewport',
				surface: 'review',
				visibleItemIds: ['item-1'],
			}),
		);
		await drainUntilReviewAttemptCount({ attempts, expectedCount: 2, scheduledDrains });
		expectOriginalReviewContentAttemptsRemainActive(attempts);

		// Act
		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 4,
				requestId: 'request-file-active-surface',
				update: {
					activeSource: null,
					mode: 'file',
					nativeSelectionRequestId: null,
					sequence: 2,
					sessionId: 'active-surface-lifecycle-session',
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expectOriginalReviewContentAttemptsRemainActive(attempts);

		// Act
		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				epoch: 5,
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
				requestId: 'request-inactive-review-viewport',
				surface: 'review',
				visibleItemIds: ['item-1'],
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expectOriginalReviewContentAttemptsRemainActive(attempts);

		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 6,
				requestId: 'request-review-active-surface-resume',
				update: {
					activeSource: null,
					mode: 'review',
					nativeSelectionRequestId: null,
					sequence: 3,
					sessionId: 'active-surface-lifecycle-session',
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expectOriginalReviewContentAttemptsRemainActive(attempts);

		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 5,
				requestId: 'request-stale-file-active-surface',
				update: {
					activeSource: null,
					mode: 'file',
					nativeSelectionRequestId: null,
					sequence: 4,
					sessionId: 'active-surface-lifecycle-session',
				},
			}),
		);
		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 7,
				requestId: 'request-repeated-review-active-surface',
				update: {
					activeSource: null,
					mode: 'review',
					nativeSelectionRequestId: null,
					sequence: 5,
					sessionId: 'active-surface-lifecycle-session',
				},
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expectOriginalReviewContentAttemptsRemainActive(attempts);
	});

	test('resumes the held Review stream when hidden and foreground frames arrive back-to-back', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const attempts: PendingReviewContentAttempt[] = [];
		let panePresentationSink: ((frame: BridgeProductPanePresentationFrame) => void) | null = null;
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-subscription-rapid-pane-resume',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			openReviewContent: (descriptor, abortSignal) =>
				makePendingReviewContentStream({
					abortSignal,
					attempts,
					descriptorId: descriptor.descriptorId,
				}),
			productTransport: makeProductTransport({
				onPanePresentationSink: (sink): void => {
					panePresentationSink = sink;
				},
				reviewSubscription,
				subscribedKinds: [],
			}),
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
			sendProductControl: async (): Promise<void> => {},
		});
		activateBridgeCommWorkerReviewViewerMode(dispatch, 'rapid-pane-resume');
		await flushBridgeWorkerRuntimeContinuations();
		events.push(reviewSnapshotWithContentEvent);
		await flushBridgeWorkerRuntimeContinuations();
		await startBridgeCommWorkerPreparationDrains(scheduledDrains);
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 1,
				requestId: 'request-review-rapid-pane-resume-selection',
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
				requestId: 'request-review-rapid-pane-resume-viewport',
				surface: 'review',
				visibleItemIds: ['item-1'],
			}),
		);
		await drainUntilReviewAttemptCount({ attempts, expectedCount: 2, scheduledDrains });
		const messageCountBeforeNativeCycle = postedMessages.length;

		// Act
		requirePanePresentationSink(panePresentationSink)(makePanePresentationFrame(2, 'loadedHidden'));
		requirePanePresentationSink(panePresentationSink)(makePanePresentationFrame(3, 'foreground'));
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expectOriginalReviewContentAttemptsRemainActive(attempts);
		expect(
			postedMessages
				.slice(messageCountBeforeNativeCycle)
				.map(({ message }) => message)
				.filter(
					(message) =>
						message.kind === 'reviewRenderPatch' &&
						message.patches.some(
							(patch) =>
								patch.slice === 'contentAvailability' &&
								patch.operation === 'upsert' &&
								patch.payload.reason === 'load_failed',
						),
				),
		).toEqual([]);
	});
});
