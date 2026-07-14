import { describe, expect, test, vi } from 'vitest';

import { encodeBridgeWorkerReviewIntakeReadyCommand } from './bridge-comm-worker-protocol.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';

describe('Bridge comm worker runtime review intake-ready protocol', () => {
	test('waits for the worker-owned product call before acknowledging review intake readiness', async () => {
		const sendSchemeRpcCommand = vi.fn(async (): Promise<void> => {});
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			sendSchemeRpcCommand,
		});

		dispatch.message(
			encodeBridgeWorkerReviewIntakeReadyCommand({
				requestId: 'request-review-intake-ready',
				epoch: 3,
				streamId: 'review:pane-1',
				reason: 'bridge-ready',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(sendSchemeRpcCommand).toHaveBeenCalledWith({
			method: 'bridge.intakeReady',
			params: {
				protocolId: 'review',
				reason: 'bridge-ready',
				streamId: 'review:pane-1',
			},
		});
		expect(postedMessages.map((postedMessage) => postedMessage.message)).toEqual([
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-review-intake-ready',
				status: 'ready',
			}),
		]);
	});
});
