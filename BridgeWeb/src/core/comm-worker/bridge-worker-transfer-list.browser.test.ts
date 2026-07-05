import { describe, expect, test } from 'vitest';

import {
	prepareBridgeWorkerStructuredMessage,
	type BridgeWorkerMessageWithTransferDescriptors,
} from './bridge-worker-transfer-list.js';

describe('Bridge worker transfer list browser transport', () => {
	test('transfers declared ArrayBuffers through browser message channels', async () => {
		interface TestWorkerMessage extends BridgeWorkerMessageWithTransferDescriptors {
			readonly kind: 'slicePatch';
			readonly payload: {
				readonly bytes: ArrayBuffer;
			};
		}

		const channel = new MessageChannel();
		const bytes = new ArrayBuffer(12);
		const preparedMessage = prepareBridgeWorkerStructuredMessage<TestWorkerMessage>({
			message: {
				kind: 'slicePatch',
				transferDescriptors: [],
				payload: {
					bytes,
				},
			},
			declaredFields: [{ fieldPath: ['payload', 'bytes'], mode: 'transfer' }],
		});

		const receivedMessage = new Promise<TestWorkerMessage>((resolve) => {
			channel.port1.addEventListener(
				'message',
				(event: MessageEvent<TestWorkerMessage>): void => {
					resolve(event.data);
				},
				{ once: true },
			);
		});
		channel.port1.start();
		channel.port2.postMessage(preparedMessage.message, [...preparedMessage.transferList]);

		expect(bytes.byteLength).toBe(0);
		await expect(receivedMessage).resolves.toMatchObject({
			kind: 'slicePatch',
			transferDescriptors: [
				{
					messageKind: 'slicePatch',
					fieldPath: ['payload', 'bytes'],
					byteLength: 12,
					mode: 'transfer',
				},
			],
		});
		const message = await receivedMessage;
		expect(message.payload.bytes.byteLength).toBe(12);
	});
});
