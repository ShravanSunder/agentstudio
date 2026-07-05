import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerCommandHandler } from './bridge-comm-worker-command-handler.js';
import { encodeBridgeWorkerSelectCommand } from './bridge-comm-worker-protocol.js';

describe('Bridge comm worker command handler', () => {
	test('select command mutates worker-local store and publishes only typed slice patches', () => {
		const handler = createBridgeCommWorkerCommandHandler({
			rows: [
				{ id: 'item-1', parentId: null, index: 0 },
				{ id: 'item-2', parentId: null, index: 1 },
			],
			createSequence: (): number => 11,
		});

		const messages = handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 7,
				selectedItemId: 'item-2',
				selectedSource: 'user',
			}),
		);

		expect(messages).toHaveLength(2);
		expect(messages[0]).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'slicePatch',
			epoch: 7,
			sequence: 11,
			patches: [
				{
					slice: 'selection',
					operation: 'upsert',
					payload: { selectedItemId: 'item-2' },
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-2',
					payload: { state: 'loading' },
				},
			],
		});
		expect(messages[1]).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'health',
			requestId: 'request-select',
			status: 'ready',
		});
		expect(JSON.stringify(messages)).not.toMatch(/rowById|orderedIds|rootSnapshot|allRows/i);
	});
});
