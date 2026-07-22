import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerCommandHandler } from './bridge-comm-worker-command-handler.js';
import { encodeBridgeWorkerReviewIntakeReadyCommand } from './bridge-comm-worker-protocol.js';
import {
	bridgeWorkerReviewContentMetadataSchema,
	type BridgeWorkerReviewContentMetadata,
} from './bridge-worker-contracts.js';

describe('Bridge comm worker command handler review intake-ready protocol', () => {
	test('reviewIntakeReady commands are accepted as worker-owned ordinary RPC intents', () => {
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			scheduleSelectedReviewContentReadyPreparation: (): void => {},
			scheduleSelectedFileViewContentReadyPreparation: (): void => {},
		});

		const messages = handler.handleMessage(
			encodeBridgeWorkerReviewIntakeReadyCommand({
				requestId: 'request-review-intake-ready',
				epoch: 1,
				streamId: 'review:pane-1',
				reason: 'bridge-ready',
			}),
		);

		expect(messages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-review-intake-ready',
				status: 'ready',
			},
		]);
	});
});

function makeWorkerReviewContentMetadata(itemId: string): BridgeWorkerReviewContentMetadata {
	return bridgeWorkerReviewContentMetadataSchema.parse({
		itemId,
		path: `${itemId}.ts`,
		language: 'typescript',
		cacheKey: `cache:${itemId}`,
		sizeBytes: 42,
		availableContentRoles: ['head'],
		contentLineCountsByRole: { head: 1 },
	});
}
