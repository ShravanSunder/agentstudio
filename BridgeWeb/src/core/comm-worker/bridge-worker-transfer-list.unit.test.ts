import { describe, expect, test } from 'vitest';

import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerFilePierreRenderJobEvent,
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

	test('prepares contract DTOs with declared clone descriptors', () => {
		const contents = 'export const answer = 42;\n';
		const cloneByteLength = new TextEncoder().encode(contents).byteLength;
		const message: BridgeWorkerFilePierreRenderJobEvent = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'filePierreRenderJob',
			publicationSequence: 1,
			surface: 'file',
			workerDerivationEpoch: 1,
			job: buildBridgeWorkerPierreRenderJob({
				itemId: 'item-1',
				renderKind: 'fileText',
				contentCacheKey: 'pierre-content:sha256:abc123',
				contentHash: 'abc123',
				language: 'typescript',
				bridgeDemandRank: { lane: 'selected', priority: 0 },
				window: {
					startLine: 1,
					endLine: 2,
					totalLineCount: 2,
				},
				payload: {
					kind: 'codeViewFileItem',
					item: {
						id: 'item-1',
						type: 'file',
						file: {
							name: 'Sources/App.ts',
							contents,
							lang: 'typescript',
							cacheKey: 'pierre-content:sha256:abc123',
						},
						version: 2,
						bridgeMetadata: {
							itemId: 'item-1',
							displayPath: 'Sources/App.ts',
							contentState: 'hydrated',
							contentRoles: ['head'],
							cacheKey: 'pierre-content:sha256:abc123',
							lineCount: 1,
						},
					},
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
			declaredFields: [
				{ fieldPath: ['job', 'payload'], mode: 'clone', byteLength: cloneByteLength },
			],
		});
		const clonedMessage = cloneBridgeWorkerStructuredMessage(preparedMessage.message);

		expect(preparedMessage.message.transferDescriptors).toEqual([
			{
				messageKind: 'filePierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: cloneByteLength,
				mode: 'clone',
			},
		]);
		expect(preparedMessage.transferList).toEqual([]);
		expect(clonedMessage.job.payload.kind).toBe('codeViewFileItem');
		if (clonedMessage.job.payload.kind === 'codeViewFileItem') {
			expect(clonedMessage.job.payload.item.file.contents).toBe(contents);
		}
	});

	test('requires explicit byte lengths for cloned object fields', () => {
		expect(() =>
			buildBridgeWorkerTransferList({
				messageKind: 'filePierreRenderJob',
				payload: {
					job: {
						payload: {
							kind: 'codeViewFileItem',
							itemId: 'item-1',
						},
					},
				},
				declaredFields: [{ fieldPath: ['job', 'payload'], mode: 'clone' }],
			}),
		).toThrow(/clone field.*byte length/i);
	});

	test('rejects clone descriptors whose field path does not resolve', () => {
		expect(() =>
			buildBridgeWorkerTransferList({
				messageKind: 'filePierreRenderJob',
				payload: {
					job: {
						payload: {
							kind: 'codeViewFileItem',
							itemId: 'item-1',
						},
					},
				},
				declaredFields: [{ fieldPath: ['job', 'missingPayload'], mode: 'clone', byteLength: 12 }],
			}),
		).toThrow(/clone field.*does not resolve/i);
	});

	test('does not typecheck synthetic messages outside BridgeWorkerContracts', () => {
		expect(typeof assertTransferHelperRejectsSyntheticMessages).toBe('function');
	});
});
