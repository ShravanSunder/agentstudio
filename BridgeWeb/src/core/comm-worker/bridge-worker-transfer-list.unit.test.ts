import { describe, expect, test } from 'vitest';

import { buildBridgeWorkerTransferList } from './bridge-worker-transfer-list.js';

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
});
