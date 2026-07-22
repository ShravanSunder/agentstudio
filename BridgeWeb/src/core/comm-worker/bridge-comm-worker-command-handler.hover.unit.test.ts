import { describe, expect, test } from 'vitest';

import {
	createBridgeCommWorkerCommandHandler,
	type BridgeCommWorkerDemandExecutionScheduleRequest,
} from './bridge-comm-worker-command-handler.js';
import {
	ignoreScheduledSelectedFileViewPreparation,
	ignoreScheduledSelectedReviewPreparation,
} from './bridge-comm-worker-command-handler.test-support.js';
import { encodeBridgeWorkerHoverCommand } from './bridge-comm-worker-protocol.js';
import { makeWorkerReviewContentMetadata } from './bridge-comm-worker-runtime-protocol.test-support.js';

describe('Bridge comm worker Review hover command handling', () => {
	test('reconciles speculative membership and publishes only ready health responses', () => {
		// Arrange
		const scheduledDemandRequests: BridgeCommWorkerDemandExecutionScheduleRequest[] = [];
		const scheduledHoverFacts: Array<{
			readonly demandKey: string | undefined;
			readonly hoveredItemId: string | null;
		}> = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			scheduleDemandExecution: (request): void => {
				scheduledDemandRequests.push(request);
				scheduledHoverFacts.push({
					demandKey: request.store.getState().demandByKey.get('item-1'),
					hoveredItemId: request.store.getState().hoveredItemId,
				});
			},
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		// Act
		const hoverMessages = handler.handleMessage(
			encodeBridgeWorkerHoverCommand({
				epoch: 1,
				hoveredItemId: 'item-1',
				requestId: 'request-hover',
				surface: 'review',
			}),
		);
		const hoverExitMessages = handler.handleMessage(
			encodeBridgeWorkerHoverCommand({
				epoch: 2,
				hoveredItemId: null,
				requestId: 'request-hover-exit',
				surface: 'review',
			}),
		);

		// Assert
		expect(hoverMessages).toEqual([
			expect.objectContaining({ kind: 'health', requestId: 'request-hover', status: 'ready' }),
		]);
		expect(hoverExitMessages).toEqual([
			expect.objectContaining({ kind: 'health', requestId: 'request-hover-exit', status: 'ready' }),
		]);
		expect(scheduledDemandRequests).toHaveLength(2);
		expect(scheduledDemandRequests[0]?.cause).toBe('hover');
		expect(scheduledHoverFacts).toEqual([
			{ demandKey: 'speculative', hoveredItemId: 'item-1' },
			{ demandKey: undefined, hoveredItemId: null },
		]);
		expect(scheduledDemandRequests[1]?.store).toBe(scheduledDemandRequests[0]?.store);
	});
});
