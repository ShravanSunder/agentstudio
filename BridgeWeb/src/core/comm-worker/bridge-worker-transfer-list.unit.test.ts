import { describe, expect, test } from 'vitest';

import {
	buildBridgeWorkerTransferList,
	cloneBridgeWorkerStructuredMessage,
	prepareBridgeWorkerStructuredMessage,
	type BridgeWorkerMessageWithTransferDescriptors,
} from './bridge-worker-transfer-list.js';

describe('Bridge worker transfer list', () => {
	test('builds declared transfer lists and rejects undeclared ArrayBuffers', () => {
		const bytes = new ArrayBuffer(16);
		const payload = {
			kind: 'slicePatch',
			bytes,
			metadata: { itemId: 'item-1' },
		};

		const transferPlan = buildBridgeWorkerTransferList({
			messageKind: 'slicePatch',
			payload,
			declaredFields: [
				{
					fieldPath: ['bytes'],
					mode: 'transfer',
				},
			],
		});

		expect(transferPlan.transferList).toEqual([bytes]);
		expect(transferPlan.descriptors).toEqual([
			{
				messageKind: 'slicePatch',
				fieldPath: ['bytes'],
				byteLength: 16,
				mode: 'transfer',
			},
		]);

		expect(() =>
			buildBridgeWorkerTransferList({
				messageKind: 'slicePatch',
				payload,
				declaredFields: [],
			}),
		).toThrow(/undeclared ArrayBuffer/i);
	});

	test('prepares typed structured-clone messages with declared transfer descriptors', () => {
		interface TestWorkerMessage extends BridgeWorkerMessageWithTransferDescriptors {
			readonly kind: 'slicePatch';
			readonly payload: {
				readonly bytes: ArrayBuffer;
				readonly label: string;
			};
		}

		const bytes = new ArrayBuffer(8);
		const message: TestWorkerMessage = {
			kind: 'slicePatch',
			transferDescriptors: [],
			payload: {
				bytes,
				label: 'README.md',
			},
		};

		const preparedMessage = prepareBridgeWorkerStructuredMessage({
			message,
			declaredFields: [{ fieldPath: ['payload', 'bytes'], mode: 'transfer' }],
		});
		const clonedMessage = cloneBridgeWorkerStructuredMessage(preparedMessage.message);

		expect(preparedMessage.message.transferDescriptors).toEqual([
			{
				messageKind: 'slicePatch',
				fieldPath: ['payload', 'bytes'],
				byteLength: 8,
				mode: 'transfer',
			},
		]);
		expect(preparedMessage.transferList).toEqual([bytes]);
		expect(clonedMessage.payload.bytes.byteLength).toBe(8);
		expect(bytes.byteLength).toBe(8);
	});
});
