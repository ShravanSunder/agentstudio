import { describe, expect, test } from 'vitest';

import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerPierreRenderJobEvent,
} from './bridge-worker-contracts.js';
import { buildBridgeWorkerPierreRenderJob } from './bridge-worker-pierre-render-job.js';
import { prepareBridgeWorkerStructuredMessage } from './bridge-worker-transfer-list.js';

describe('Bridge worker transfer list browser transport', () => {
	test('transfers declared ArrayBuffers through browser message channels', async () => {
		const channel = new MessageChannel();
		const bytes = new ArrayBuffer(12);
		const preparedMessage = prepareBridgeWorkerStructuredMessage({
			message: {
				wireVersion: BRIDGE_WORKER_WIRE_VERSION,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'pierreRenderJob',
				job: buildBridgeWorkerPierreRenderJob({
					itemId: 'item-1',
					renderKind: 'reviewDiff',
					contentCacheKey: 'pierre-content:sha256:abc123',
					contentHash: 'abc123',
					language: 'typescript',
					bridgeDemandRank: { lane: 'selected', priority: 0 },
					window: {
						startLine: 1,
						endLine: 20,
						totalLineCount: 200,
					},
					payload: {
						kind: 'textWindow',
						textBytes: bytes,
					},
					budget: {
						className: 'interactive',
						maxBytes: 1024,
						maxWindowLines: 50,
					},
				}),
			} satisfies BridgeWorkerPierreRenderJobEvent,
			declaredFields: [{ fieldPath: ['job', 'payload', 'textBytes'], mode: 'transfer' }],
		});

		const receivedMessage = new Promise<BridgeWorkerPierreRenderJobEvent>((resolve) => {
			channel.port1.addEventListener(
				'message',
				(event: MessageEvent<BridgeWorkerPierreRenderJobEvent>): void => {
					resolve(event.data);
				},
				{ once: true },
			);
		});
		channel.port1.start();
		channel.port2.postMessage(preparedMessage.message, [...preparedMessage.transferList]);

		expect(bytes.byteLength).toBe(0);
		await expect(receivedMessage).resolves.toMatchObject({
			kind: 'pierreRenderJob',
			transferDescriptors: [
				{
					messageKind: 'pierreRenderJob',
					fieldPath: ['job', 'payload', 'textBytes'],
					byteLength: 12,
					mode: 'transfer',
				},
			],
		});
		const message = await receivedMessage;
		expect(message.job.payload.textBytes.byteLength).toBe(12);
	});
});
