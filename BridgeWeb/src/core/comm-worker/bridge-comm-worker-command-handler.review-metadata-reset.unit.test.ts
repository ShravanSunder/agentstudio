import { describe, expect, test } from 'vitest';

import { makeBridgeReviewItem } from '../../foundation/review-package/bridge-review-package-test-support.js';
import { reviewMetadataApplication } from './bridge-comm-worker-command-handler-review.test-support.js';
import { createBridgeCommWorkerCommandHandler } from './bridge-comm-worker-command-handler.js';
import {
	ignoreScheduledSelectedFileViewPreparation,
	pushScheduledSelectedReviewPreparation,
	type ScheduledSelectedReviewPreparation,
} from './bridge-comm-worker-command-handler.test-support.js';
import {
	encodeBridgeWorkerReviewInvalidateCommand,
	encodeBridgeWorkerSelectCommand,
} from './bridge-comm-worker-protocol.js';
import { makeReviewPublication } from './bridge-main-render-fulfillment-coordinator.test-support.js';
import type { BridgeWorkerReviewContentMetadata } from './bridge-worker-contracts.js';

describe('Bridge comm worker Review metadata reset', () => {
	test('releases a selected render retry with the invalidated demand epoch', () => {
		// Arrange
		const itemId = 'item-invalidated-retry';
		const scheduledPreparations: ScheduledSelectedReviewPreparation[] = [];
		let nowMilliseconds = 0;
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata(itemId)],
			now: (): number => nowMilliseconds,
			renderReceiptLeaseDurationMilliseconds: 10,
			renderRetryBackoffMilliseconds: 5,
			rows: [{ id: itemId, parentId: null, index: 0 }],
			scheduleSelectedReviewContentReadyPreparation:
				pushScheduledSelectedReviewPreparation(scheduledPreparations),
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				epoch: 7,
				requestId: 'request-select-before-invalidated-retry',
				selectedItemId: itemId,
				selectedSource: 'user',
				surface: 'review',
			}),
		);
		const reviewStore = scheduledPreparations[0]?.store;
		if (reviewStore === undefined) throw new Error('expected selected Review store');
		reviewStore.renderFulfillmentRegistry.beginPublication({
			job: makeReviewPublication({ itemId, publicationSequence: 1 }).job,
			publicationSequence: 1,
			workerDerivationEpoch: 1,
		});
		nowMilliseconds = 10;
		handler.advanceReviewRenderFulfillmentLifecycle(nowMilliseconds);
		handler.handleMessage(
			encodeBridgeWorkerReviewInvalidateCommand({
				epoch: 8,
				itemIds: [itemId],
				pathHints: [],
				reason: 'watchEvent',
				requestId: 'request-invalidate-before-retry-release',
				scope: 'items',
			}),
		);
		expect(reviewStore.getState()).toMatchObject({ selectedEpoch: 7 });
		expect(reviewStore.getState().demandByKey.get(itemId)).toBe('selected:8');

		// Act
		nowMilliseconds = 15;
		handler.advanceReviewRenderFulfillmentLifecycle(nowMilliseconds);

		// Assert
		expect(scheduledPreparations).toHaveLength(3);
		expect(scheduledPreparations.at(-1)).toMatchObject({ epoch: 8, itemId });
	});

	test('requeues active render attempts only after transaction commit', () => {
		// Arrange
		const itemId = 'item-generation-refresh';
		const scheduledPreparations: ScheduledSelectedReviewPreparation[] = [];
		let reviewStore: ScheduledSelectedReviewPreparation['store'] | null = null;
		let resetScheduledAfterAttemptRequeue = false;
		const contentItems = [makeWorkerReviewContentMetadata(itemId)];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems,
			rows: [{ id: itemId, parentId: null, index: 0 }],
			scheduleReviewMetadataReset: (): void => {
				resetScheduledAfterAttemptRequeue =
					reviewStore?.renderFulfillmentRegistry.getItemState(itemId)?.stage === 'desired';
			},
			scheduleSelectedReviewContentReadyPreparation:
				pushScheduledSelectedReviewPreparation(scheduledPreparations),
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				epoch: 7,
				requestId: 'request-select-before-generation-refresh',
				selectedItemId: itemId,
				selectedSource: 'user',
				surface: 'review',
			}),
		);
		reviewStore = scheduledPreparations[0]?.store ?? null;
		if (reviewStore === null) throw new Error('expected selected Review store');
		const renderJob = makeReviewPublication({ itemId, publicationSequence: 1 }).job;
		const firstPublication = reviewStore.renderFulfillmentRegistry.beginPublication({
			job: renderJob,
			publicationSequence: 1,
			workerDerivationEpoch: 1,
		});
		const resetApplication = reviewMetadataApplication({
			contentItems,
			contentRequestDescriptors: [],
			renderSemantics: [],
			reset: true,
			rows: [{ id: itemId, parentId: null, index: 0 }],
			sourceEpoch: 8,
		});

		// Act: rollback retains the active attempt; commit requeues it before reset demand.
		const rolledBackTransaction = handler.prepareReviewMetadataApplication(resetApplication);
		rolledBackTransaction.rollback();
		const publicationAfterRollback = reviewStore.renderFulfillmentRegistry.beginPublication({
			job: renderJob,
			publicationSequence: 2,
			workerDerivationEpoch: 1,
		});
		const committedTransaction = handler.prepareReviewMetadataApplication(resetApplication);
		committedTransaction.commit();
		committedTransaction.runPostCommitEffects();
		const publicationAfterCommit = reviewStore.renderFulfillmentRegistry.beginPublication({
			job: renderJob,
			publicationSequence: 3,
			workerDerivationEpoch: 1,
		});

		// Assert
		expect(publicationAfterRollback).toMatchObject({
			receiptIdentity: firstPublication.receiptIdentity,
			shouldPublish: false,
			status: 'duplicate',
		});
		expect(resetScheduledAfterAttemptRequeue).toBe(true);
		expect(publicationAfterCommit).toMatchObject({ shouldPublish: true, status: 'published' });
		expect(publicationAfterCommit.receiptIdentity.publicationId).toBe(
			firstPublication.receiptIdentity.publicationId,
		);
		expect(publicationAfterCommit.receiptIdentity.attemptId).not.toBe(
			firstPublication.receiptIdentity.attemptId,
		);
	});
});

function makeWorkerReviewContentMetadata(itemId: string): BridgeWorkerReviewContentMetadata {
	const item = makeBridgeReviewItem({
		itemId,
		path: `Sources/App/${itemId}.swift`,
	});
	return {
		itemId: item.itemId,
		path: item.headPath ?? item.basePath ?? item.itemId,
		language: item.language ?? null,
		cacheKey: item.cacheKey,
		sizeBytes: item.sizeBytes,
		availableContentRoles: ['head'],
		contentLineCountsByRole: item.contentLineCountsByRole ?? {},
	};
}
