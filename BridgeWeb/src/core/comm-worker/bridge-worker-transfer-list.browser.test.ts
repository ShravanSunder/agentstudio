import { describe, expect, test } from 'vitest';

import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerFilePierreRenderJobEvent,
} from './bridge-worker-contracts.js';
import { buildBridgeWorkerPierreRenderJob } from './bridge-worker-pierre-render-job.js';
import { makeBridgeWorkerRenderReceiptIdentity } from './bridge-worker-render-fulfillment.test-support.js';
import {
	buildBridgeWorkerTransferList,
	prepareBridgeWorkerStructuredMessage,
} from './bridge-worker-transfer-list.js';

describe('Bridge worker transfer list browser transport', () => {
	test('transfers declared ArrayBuffers through browser message channels', async () => {
		const channel = new MessageChannel();
		const bytes = new ArrayBuffer(12);
		const payload = {
			kind: 'rawTransferProbe',
			bytes,
		};
		const transferPlan = buildBridgeWorkerTransferList({
			messageKind: 'rawTransferProbe',
			payload,
			declaredFields: [{ fieldPath: ['bytes'], mode: 'transfer' }],
		});

		const receivedMessage = new Promise<typeof payload>((resolve) => {
			channel.port1.addEventListener(
				'message',
				(event: MessageEvent<typeof payload>): void => {
					resolve(event.data);
				},
				{ once: true },
			);
		});
		channel.port1.start();
		channel.port2.postMessage(payload, [...transferPlan.transferList]);

		expect(bytes.byteLength).toBe(0);
		await expect(receivedMessage).resolves.toMatchObject({
			kind: 'rawTransferProbe',
		});
		const message = await receivedMessage;
		expect(message.bytes.byteLength).toBe(12);
	});

	test('clones worker-prepared CodeView payloads through browser message channels', async () => {
		const channel = new MessageChannel();
		const contents = 'export const answer = 42;\n';
		const cloneByteLength = new TextEncoder().encode(contents).byteLength;
		const preparedMessage = prepareBridgeWorkerStructuredMessage({
			message: {
				wireVersion: BRIDGE_WORKER_WIRE_VERSION,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'filePierreRenderJob',
				publicationSequence: 1,
				renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
					itemId: 'item-codeview-file',
					publicationSequence: 1,
					surface: 'file',
					workerDerivationEpoch: 1,
				}),
				surface: 'file',
				workerDerivationEpoch: 1,
				job: buildBridgeWorkerPierreRenderJob({
					itemId: 'item-codeview-file',
					renderKind: 'fileText',
					contentCacheKey: 'pierre-content:sha256:codeview-file',
					contentHash: 'sha256:codeview-file',
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
							id: 'item-codeview-file',
							type: 'file',
							file: {
								name: 'Sources/App.ts',
								contents,
								lang: 'typescript',
								cacheKey: 'pierre-content:sha256:codeview-file',
							},
							version: 2,
							bridgeMetadata: {
								itemId: 'item-codeview-file',
								displayPath: 'Sources/App.ts',
								contentState: 'hydrated',
								contentRoles: ['head'],
								cacheKey: 'pierre-content:sha256:codeview-file',
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
			} satisfies BridgeWorkerFilePierreRenderJobEvent,
			declaredFields: [
				{ fieldPath: ['job', 'payload'], mode: 'clone', byteLength: cloneByteLength },
			],
		});

		const receivedMessage = new Promise<BridgeWorkerFilePierreRenderJobEvent>((resolve) => {
			channel.port1.addEventListener(
				'message',
				(event: MessageEvent<BridgeWorkerFilePierreRenderJobEvent>): void => {
					resolve(event.data);
				},
				{ once: true },
			);
		});
		channel.port1.start();
		channel.port2.postMessage(preparedMessage.message, [...preparedMessage.transferList]);

		expect(preparedMessage.transferList).toEqual([]);
		await expect(receivedMessage).resolves.toMatchObject({
			kind: 'filePierreRenderJob',
			transferDescriptors: [
				{
					messageKind: 'filePierreRenderJob',
					fieldPath: ['job', 'payload'],
					byteLength: cloneByteLength,
					mode: 'clone',
				},
			],
			job: {
				payload: {
					kind: 'codeViewFileItem',
					item: {
						file: {
							contents,
						},
					},
				},
			},
		});
	});
});
