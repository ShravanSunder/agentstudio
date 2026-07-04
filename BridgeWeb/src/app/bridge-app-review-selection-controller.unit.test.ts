import { describe, expect, test } from 'vitest';

import type { BridgeRPCClient, BridgeRPCCommand } from '../bridge/bridge-rpc-client.js';
import { scheduleReviewMarkFileViewedCommand } from './bridge-app-review-selection-controller.js';

describe('Bridge review selection controller command scheduling', () => {
	test('defers markFileViewed RPC dispatch outside the selection call stack', async () => {
		const sentCommands: BridgeRPCCommand[] = [];
		const rpcClient: BridgeRPCClient = {
			sendCommand: (command: BridgeRPCCommand): boolean => {
				sentCommands.push(command);
				return true;
			},
		};

		scheduleReviewMarkFileViewedCommand({
			itemId: 'async-target-item',
			rpcClient,
		});

		expect(sentCommands).toEqual([]);

		await Promise.resolve();

		expect(sentCommands).toEqual([
			{
				method: 'review.markFileViewed',
				params: { fileId: 'async-target-item' },
			},
		]);
	});
});
