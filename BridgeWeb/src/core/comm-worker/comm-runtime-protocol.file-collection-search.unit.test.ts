import { describe, expect, test } from 'vitest';

import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import type { BridgeProductFileSelectionReceipt } from './bridge-product-call-contracts.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';

describe('Bridge comm worker File collection search', () => {
	test('answers a search after later File intents without advancing or waiting on their epoch', async () => {
		// Arrange
		const forwardedControls: BridgeProductControlCommand[] = [];
		const selectionReceipt: BridgeProductFileSelectionReceipt = {
			displayPath: 'backend/src/plan.md',
			nativeNavigationCommandId: null,
			outcome: 'displayed',
			source: { sourceId: 'collection-source', subscriptionGeneration: 3 },
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			sendProductControl: async (command): Promise<void> => {
				forwardedControls.push(command);
			},
		});
		dispatch.message({
			command: 'fileSelectionReceipt',
			direction: 'mainToServerWorker',
			epoch: 7,
			kind: 'command',
			receipt: selectionReceipt,
			requestId: 'file-selection-receipt-7',
			transferDescriptors: [],
			wireVersion: 1,
		});

		// Act
		dispatch.message({
			command: 'fileCollectionSearch',
			criteria: { limit: 20, scope: { kind: 'all' }, searchMode: 'text', searchText: 'plan' },
			direction: 'mainToServerWorker',
			epoch: 0,
			kind: 'command',
			requestId: 'native-search-1',
			transferDescriptors: [],
			wireVersion: 1,
		});
		dispatch.message({
			command: 'fileSelectionReceipt',
			direction: 'mainToServerWorker',
			epoch: 8,
			kind: 'command',
			receipt: selectionReceipt,
			requestId: 'file-selection-receipt-8',
			transferDescriptors: [],
			wireVersion: 1,
		});
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		const messages = postedMessages.map(({ message }) => message);
		expect(messages).toContainEqual(
			expect.objectContaining({
				kind: 'fileCollectionSearch',
				outcome: { kind: 'noSource' },
				requestId: 'native-search-1',
			}),
		);
		expect(messages).not.toContainEqual(
			expect.objectContaining({ kind: 'health', status: 'degraded' }),
		);
		expect(forwardedControls).toHaveLength(2);
	});
});
