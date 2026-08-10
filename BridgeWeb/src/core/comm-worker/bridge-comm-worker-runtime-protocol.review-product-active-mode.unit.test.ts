import { describe, test } from 'vitest';

import {
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import type { BridgeCommWorkerPreparationDrain } from './bridge-comm-worker-runtime-protocol.js';
import {
	drainUntilReviewAttemptCount,
	expectOriginalReviewContentAttemptsRemainActive,
	makePendingReviewContentStream,
	makeReviewProductTransport,
	reviewSnapshotWithContentEvent,
	startBridgeCommWorkerPreparationDrains,
	type PendingReviewContentAttempt,
} from './bridge-comm-worker-runtime-protocol.review-product.test-support.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';

describe('Bridge comm worker Review product active viewer mode lifecycle', () => {
	test('pauses active Review content while File is accepted and resumes the same transport', async () => {
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
			productTransport: makeReviewProductTransport({ reviewSubscription, subscribedKinds: [] }),
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
			sendProductControl: async (): Promise<void> => {},
		});
		await flushBridgeWorkerRuntimeContinuations();
		events.push(reviewSnapshotWithContentEvent);
		await flushBridgeWorkerRuntimeContinuations();
		await startBridgeCommWorkerPreparationDrains(
			scheduledDrains,
			flushBridgeWorkerRuntimeContinuations,
		);
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
		await drainUntilReviewAttemptCount({
			attempts,
			expectedCount: 2,
			scheduledDrains,
			flushContinuations: flushBridgeWorkerRuntimeContinuations,
		});
		expectOriginalReviewContentAttemptsRemainActive(attempts);

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
		expectOriginalReviewContentAttemptsRemainActive(attempts);

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
});
