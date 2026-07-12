import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerCommandHandler } from './bridge-comm-worker-command-handler.js';
import {
	encodeBridgeWorkerFileDisplayResyncCommand,
	encodeBridgeWorkerFileQueryUpdateCommand,
} from './bridge-comm-worker-protocol.js';
import type {
	BridgeWorkerFileDisplayResyncCommand,
	BridgeWorkerFileQueryUpdateCommand,
} from './bridge-worker-contracts.js';

describe('Bridge comm worker File query command handling', () => {
	test('routes the strict query command through the injected worker projection owner', () => {
		const receivedCommands: BridgeWorkerFileQueryUpdateCommand[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [],
			scheduleSelectedFileViewContentReadyPreparation: (): void => {},
			scheduleSelectedReviewContentReadyPreparation: (): void => {},
			updateFileDisplayQuery: (command) => {
				receivedCommands.push(command);
				return [];
			},
		});
		const command = encodeBridgeWorkerFileQueryUpdateCommand({
			epoch: 9,
			filterMode: 'unavailable',
			requestId: 'file-query-1',
			searchMode: 'regex',
			searchText: '\\.bin$',
		});

		expect(handler.handleMessage(command)).toEqual([]);
		expect(receivedCommands).toEqual([command]);
	});

	test('routes the strict display resync command through the injected worker authority', () => {
		const receivedCommands: BridgeWorkerFileDisplayResyncCommand[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [],
			requestFileDisplayResync: (command) => {
				receivedCommands.push(command);
				return [];
			},
			scheduleSelectedFileViewContentReadyPreparation: (): void => {},
			scheduleSelectedReviewContentReadyPreparation: (): void => {},
		});
		const command = encodeBridgeWorkerFileDisplayResyncCommand({
			epoch: 10,
			reason: 'acknowledgementTimeout',
			requestId: 'file-display-resync-1',
			transactionId: 'file-query-3',
		});

		expect(handler.handleMessage(command)).toEqual([]);
		expect(receivedCommands).toEqual([command]);
	});
});
