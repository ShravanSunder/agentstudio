import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerCommandHandler } from './bridge-comm-worker-command-handler.js';
import {
	ignoreScheduledSelectedFileViewPreparation,
	ignoreScheduledSelectedReviewPreparation,
} from './bridge-comm-worker-command-handler.test-support.js';
import {
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerMetadataInterestUpdateCommand,
} from './bridge-comm-worker-protocol.js';

describe('Bridge comm worker request retention', () => {
	test('bounds identities by domain while rejecting replays in the retained window', () => {
		// Arrange
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [],
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});
		const paneRequest = encodeBridgeWorkerActiveViewerModeUpdateCommand({
			requestId: 'pane-request-1',
			epoch: 1,
			update: {
				sessionId: 'active-viewer-session',
				sequence: 1,
				mode: 'review',
				activeSource: null,
				nativeSelectionRequestId: null,
			},
		});

		// Act
		handler.handleMessage(paneRequest);
		handler.handleMessage(makeReviewRequest('retired-review-request', 1));
		for (let epoch = 2; epoch <= 32; epoch += 1) {
			handler.handleMessage(makeReviewRequest(`review-request-${epoch}`, epoch));
		}
		const reusedAfterReviewEpochAdvance = handler.handleMessage(
			makeReviewRequest('retired-review-request', 32),
		);
		const activeReviewEpochReplay = handler.handleMessage(
			makeReviewRequest('retired-review-request', 32),
		);
		const paneReplayAfterReviewEpochAdvance = handler.handleMessage(paneRequest);
		handler.handleMessage(makeReviewRequest('oldest-bounded-review-request', 33));
		for (let requestIndex = 1; requestIndex <= 4096; requestIndex += 1) {
			handler.handleMessage(makeReviewRequest(`bounded-review-request-${requestIndex}`, 33));
		}
		const retiredByBoundedWindow = handler.handleMessage(
			makeReviewRequest('oldest-bounded-review-request', 33),
		);
		const recentBoundedWindowReplay = handler.handleMessage(
			makeReviewRequest('bounded-review-request-4096', 33),
		);

		// Assert
		expect(reusedAfterReviewEpochAdvance.at(-1)).toMatchObject({
			kind: 'health',
			requestId: 'retired-review-request',
			status: 'ready',
		});
		expect(activeReviewEpochReplay).toEqual([
			expect.objectContaining({
				message: 'Bridge comm worker rejected replayed request retired-review-request.',
				status: 'degraded',
			}),
		]);
		expect(paneReplayAfterReviewEpochAdvance).toEqual([
			expect.objectContaining({
				message: 'Bridge comm worker rejected replayed request pane-request-1.',
				status: 'degraded',
			}),
		]);
		expect(retiredByBoundedWindow.at(-1)).toMatchObject({
			requestId: 'oldest-bounded-review-request',
			status: 'ready',
		});
		expect(recentBoundedWindowReplay).toEqual([
			expect.objectContaining({
				message: 'Bridge comm worker rejected replayed request bounded-review-request-4096.',
				status: 'degraded',
			}),
		]);
	});
});

function makeReviewRequest(
	requestId: string,
	epoch: number,
): ReturnType<typeof encodeBridgeWorkerMetadataInterestUpdateCommand> {
	return encodeBridgeWorkerMetadataInterestUpdateCommand({
		requestId,
		epoch,
		request: {
			protocol: 'review',
			streamId: 'review-stream-1',
			generation: 1,
			itemIds: [],
			lane: 'foreground',
			loaded_by: 'foreground',
		},
	});
}
