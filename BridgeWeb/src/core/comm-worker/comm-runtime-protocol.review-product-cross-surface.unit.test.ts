import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import type { BridgeCommWorkerPreparationDrain } from './bridge-comm-worker-runtime-protocol.js';
import { reviewSnapshotWithContentEvent } from './bridge-comm-worker-runtime-protocol.review-product-fixtures.test-support.js';
import { drainBridgeCommWorkerPreparationUntilIdle } from './bridge-comm-worker-runtime-protocol.review-product-preparation.test-support.js';
import {
	makeReviewMetadataDataFrame,
	makeReviewProductTransport,
	type ReviewMetadataSubscription,
} from './bridge-comm-worker-runtime-protocol.review-product-transport.test-support.js';
import {
	assertBridgeCommWorkerPreparationDrain,
	activateBridgeCommWorkerReviewViewerMode,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';

type ReviewMetadataDataFrame = ReturnType<typeof makeReviewMetadataDataFrame>;

describe('Bridge comm worker Review product cross-surface lifecycle', () => {
	test('opens Review content when Review interaction epochs restart after File interaction', async () => {
		const events = new BridgeProductBoundedAsyncQueue<ReviewMetadataDataFrame>(64);
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const openedContentKinds: string[] = [];
		const reviewSubscription: ReviewMetadataSubscription = {
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
			productTransport: makeReviewProductTransport({
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
		events.push(makeReviewMetadataDataFrame(reviewSnapshotWithContentEvent));
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
		await drainBridgeCommWorkerPreparationUntilIdle(
			scheduledDrains,
			flushBridgeWorkerRuntimeContinuations,
		);
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
});
