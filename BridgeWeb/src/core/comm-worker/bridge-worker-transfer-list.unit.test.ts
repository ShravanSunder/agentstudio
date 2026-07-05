import { describe, expect, test } from 'vitest';

import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerPierreRenderJobEvent,
} from './bridge-worker-contracts.js';
import { buildBridgeWorkerPierreRenderJob } from './bridge-worker-pierre-render-job.js';
import {
	buildBridgeWorkerTransferList,
	cloneBridgeWorkerStructuredMessage,
	prepareBridgeWorkerStructuredMessage,
} from './bridge-worker-transfer-list.js';

function assertTransferHelperRejectsSyntheticMessages(): void {
	const syntheticMessage = {
		kind: 'slicePatch',
		transferDescriptors: [],
		payload: {
			bytes: new ArrayBuffer(8),
		},
	};
	prepareBridgeWorkerStructuredMessage({
		// @ts-expect-error Send-side preparation only accepts schema-derived worker DTOs.
		message: syntheticMessage,
		declaredFields: [{ fieldPath: ['payload', 'bytes'], mode: 'transfer' }],
	});
}

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

	test('prepares contract DTOs with declared transfer descriptors', () => {
		const bytes = new ArrayBuffer(8);
		const message: BridgeWorkerPierreRenderJobEvent = {
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
		};

		const preparedMessage = prepareBridgeWorkerStructuredMessage({
			message,
			declaredFields: [{ fieldPath: ['job', 'payload', 'textBytes'], mode: 'transfer' }],
		});
		const clonedMessage = cloneBridgeWorkerStructuredMessage(preparedMessage.message);

		expect(preparedMessage.message.transferDescriptors).toEqual([
			{
				messageKind: 'pierreRenderJob',
				fieldPath: ['job', 'payload', 'textBytes'],
				byteLength: 8,
				mode: 'transfer',
			},
		]);
		expect(preparedMessage.transferList).toEqual([bytes]);
		expect(clonedMessage.job.payload.textBytes.byteLength).toBe(8);
		expect(bytes.byteLength).toBe(8);
	});

	test('does not typecheck synthetic messages outside BridgeWorkerContracts', () => {
		expect(typeof assertTransferHelperRejectsSyntheticMessages).toBe('function');
	});
});
