import { describe, expect, test } from 'vitest';

import { makeBridgeReviewItem } from '../../foundation/review-package/bridge-review-package-test-support.js';
import { createBridgeCommWorkerCommandHandler } from './bridge-comm-worker-command-handler.js';
import {
	createSequenceFrom,
	ignoreScheduledSelectedFileViewPreparation,
	pushScheduledSelectedReviewPreparation,
	type ScheduledSelectedReviewPreparation,
} from './bridge-comm-worker-command-handler.test-support.js';
import { encodeBridgeWorkerSelectCommand } from './bridge-comm-worker-protocol.js';
import type { BridgeWorkerReviewContentMetadata } from './bridge-worker-contracts.js';

describe('Bridge comm worker selection clear', () => {
	test('retires worker-owned selected demand and publishes selection deletion', () => {
		// Arrange
		const scheduledPreparations: ScheduledSelectedReviewPreparation[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			createSequence: createSequenceFrom([30, 31]),
			scheduleSelectedReviewContentReadyPreparation:
				pushScheduledSelectedReviewPreparation(scheduledPreparations),
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				epoch: 7,
				requestId: 'request-select-before-clear',
				selectedItemId: 'item-1',
				selectedSource: 'user',
				surface: 'review',
			}),
		);

		// Act
		const messages = handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				epoch: 8,
				requestId: 'request-clear-selection',
				selectedItemId: null,
				selectedSource: null,
				surface: 'review',
			}),
		);

		// Assert
		expect(messages[0]).toMatchObject({
			kind: 'slicePatch',
			patches: [{ operation: 'delete', slice: 'selection' }],
		});
		const workerState = scheduledPreparations[0]?.store.getState();
		expect(workerState?.selectedId).toBeNull();
		expect(workerState?.selectedDemandEnabled).toBe(false);
		expect(workerState?.demandByKey.has('item-1')).toBe(false);
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
