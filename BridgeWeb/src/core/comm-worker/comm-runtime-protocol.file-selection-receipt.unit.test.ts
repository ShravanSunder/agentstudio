import { describe, expect, test } from 'vitest';

import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import type { BridgeProductFileSelectionReceipt } from './bridge-product-call-contracts.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';

describe('Bridge comm worker File selection receipt', () => {
	test('forwards the displayed selection to native as a typed product control', async () => {
		// Arrange
		const sentCommands: BridgeProductControlCommand[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			sendProductControl: async (command): Promise<void> => {
				sentCommands.push(command);
			},
		});
		const receipt: BridgeProductFileSelectionReceipt = {
			displayPath: 'backend/src/plan.md',
			nativeNavigationCommandId: 'native-file-activation-1',
			outcome: 'displayed',
			source: { sourceId: 'collection-source', subscriptionGeneration: 3 },
		};

		// Act
		dispatch.message({
			command: 'fileSelectionReceipt',
			direction: 'mainToServerWorker',
			epoch: 5,
			issuedAtMilliseconds: 1_775_000_000_000,
			kind: 'command',
			receipt,
			requestId: 'file-selection-receipt-1',
			transferDescriptors: [],
			wireVersion: 1,
		});
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(sentCommands).toEqual([{ method: 'file.selection.receipt', params: receipt }]);
		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'file-selection-receipt-1',
				status: 'ready',
			}),
		);
	});
});
