import { describe, expect, test } from 'vitest';

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
	activateBridgeCommWorkerReviewViewerMode,
	assertBridgeCommWorkerPreparationDrain,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	makeImmediateReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
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

interface PendingReviewContentAttempt {
	readonly abortSignal: AbortSignal;
	readonly descriptorId: string;
}

function makeProductTransport(props: {
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

function makePendingReviewContentStream(props: {
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

async function drainUntilReviewAttemptCount(props: {
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

function expectOriginalReviewContentAttemptsRemainActive(
	attempts: readonly PendingReviewContentAttempt[],
): void {
	expect(attempts.map(({ descriptorId }) => descriptorId)).toEqual([
		'review-descriptor-item-1-base',
		'review-descriptor-item-1-head',
	]);
	expect(attempts.every(({ abortSignal }) => !abortSignal.aborted)).toBe(true);
}

function requirePanePresentationSink(
	sink: ((frame: BridgeProductPanePresentationFrame) => void) | null,
): (frame: BridgeProductPanePresentationFrame) => void {
	if (sink === null) throw new Error('Expected Bridge pane presentation sink registration.');
	return sink;
}

function makePanePresentationFrame(
	activityRevision: number,
	nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
): BridgeProductPanePresentationFrame {
	return {
		activityRevision,
		kind: 'pane.presentation',
		metadataStreamId: 'metadata-stream-review-pane-suppression',
		nativeActivity,
		paneSessionId: 'pane-session-review-pane-suppression',
		refreshingLanes: [],
		streamSequence: activityRevision,
		wireVersion: 2,
		workerInstanceId: 'worker-instance-review-pane-suppression',
	};
}

async function* emptyReviewContentFrames(): AsyncIterable<never> {}

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

async function startBridgeCommWorkerPreparationDrains(
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
