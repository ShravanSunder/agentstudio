import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';

import invalidProductSessionCorpus from '../../test-fixtures/bridge-contract-fixtures/invalid/bridge-product-session-corpus.json' with { type: 'json' };
import validProductSessionCorpus from '../../test-fixtures/bridge-contract-fixtures/valid/bridge-product-session-corpus.json' with { type: 'json' };
import {
	BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH,
	bridgePaneCommWorkerInstallSchema,
	bridgeProductSessionBootstrapSchema,
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductResourceRequestIdentitySchema,
	bridgeProductStreamFrameSchema,
	encodeBridgeProductCapabilityHeader,
	encodeBridgeProductStreamFrame,
	postBridgePaneCommWorkerInstall,
} from './bridge-product-session-contracts.js';

describe('Bridge product session contracts', () => {
	test('keeps the Swift and TypeScript corpora byte-identical at frozen hashes', () => {
		const fixturePairs = [
			{
				expectedHash: 'b8b8ccf47dafc90b26b53aa12f39c32f86c689b56c9e4a25c6faba7ee4f765ec',
				kind: 'valid',
			},
			{
				expectedHash: 'e7fdc3a037af2fc363e7b20108eae7b331bd277cea0f6fc1712d07534df3f675',
				kind: 'invalid',
			},
		] as const;

		for (const fixturePair of fixturePairs) {
			const relativeFixturePath = `${fixturePair.kind}/bridge-product-session-corpus.json`;
			const typeScriptBytes = readFileSync(
				new URL(
					`../../test-fixtures/bridge-contract-fixtures/${relativeFixturePath}`,
					import.meta.url,
				),
			);
			const swiftBytes = readFileSync(
				new URL(`../../../../Tests/BridgeContractFixtures/${relativeFixturePath}`, import.meta.url),
			);

			expect(swiftBytes.equals(typeScriptBytes)).toBe(true);
			expect(createHash('sha256').update(typeScriptBytes).digest('hex')).toBe(
				fixturePair.expectedHash,
			);
		}
	});

	test('accepts the shared native bootstrap and canonical capability header', () => {
		expect(bridgeProductSessionBootstrapSchema.parse(validProductSessionCorpus.bootstrap)).toEqual(
			validProductSessionCorpus.bootstrap,
		);
		for (const capabilityCase of validProductSessionCorpus.capabilityHeaderCases) {
			expect(encodeBridgeProductCapabilityHeader(capabilityCase.bytes)).toBe(
				capabilityCase.encoded,
			);
			expect(
				encodeBridgeProductCapabilityHeader(Uint8Array.from(capabilityCase.bytes).buffer),
			).toBe(capabilityCase.encoded);
			expect(capabilityCase.encoded).not.toMatch(/[+/=]/u);
		}
	});

	test('rejects incomplete capabilities and route vocabulary drift', () => {
		expect(
			bridgeProductSessionBootstrapSchema.safeParse({
				...validProductSessionCorpus.bootstrap,
				productCapabilityBytes: validProductSessionCorpus.bootstrap.productCapabilityBytes.slice(
					0,
					-1,
				),
			}).success,
		).toBe(false);
		expect(
			bridgeProductSessionBootstrapSchema.safeParse({
				...validProductSessionCorpus.bootstrap,
				routes: {
					...validProductSessionCorpus.bootstrap.routes,
					stream: { method: 'POST', url: 'agentstudio://rpc/legacy-stream' },
				},
			}).success,
		).toBe(false);
	});

	test('accepts the shared versioned Swift and TypeScript corpus', () => {
		for (const request of validProductSessionCorpus.requests) {
			expect(bridgeProductControlRequestSchema.parse(request)).toEqual(request);
		}
		for (const response of validProductSessionCorpus.responses) {
			expect(bridgeProductControlResponseSchema.parse(response)).toEqual(response);
		}
		for (const streamFrame of validProductSessionCorpus.streamFrames) {
			expect(bridgeProductStreamFrameSchema.parse(streamFrame)).toEqual(streamFrame);
		}
		for (const resourceRequest of validProductSessionCorpus.resourceRequests) {
			expect(bridgeProductResourceRequestIdentitySchema.parse(resourceRequest)).toEqual(
				resourceRequest,
			);
		}
	});

	test('rejects every hostile shared-corpus case at its receiving boundary', () => {
		for (const hostileCase of invalidProductSessionCorpus.cases) {
			const schema = schemaForHostileContract(hostileCase.contract);
			expect(schema.safeParse(hostileCase.value).success, hostileCase.name).toBe(false);
		}
	});

	test('rejects non-JSON command payload values before transport serialization', () => {
		expect(
			bridgeProductControlRequestSchema.safeParse({
				kind: 'product.command',
				wireVersion: 1,
				paneSessionId: 'pane-session-1',
				workerInstanceId: 'worker-instance-1',
				requestId: 'request-command-1',
				requestSequence: 2,
				surface: 'review',
				sourceGeneration: 7,
				workerEpoch: 3,
				command: {
					name: 'review.refresh',
					payload: { callback: (): void => {} },
				},
			}).success,
		).toBe(false);
	});

	test('requires one exact 32-byte product capability in the install message', () => {
		const productChannel = new MessageChannel();
		const validCapability = new ArrayBuffer(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH);
		const shortCapability = new ArrayBuffer(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH - 1);

		expect(
			bridgePaneCommWorkerInstallSchema.safeParse({
				kind: 'bridgePaneCommWorker.install',
				wireVersion: 1,
				paneSessionId: 'pane-session-1',
				workerInstanceId: 'worker-instance-1',
				productCapability: validCapability,
				productPort: productChannel.port1,
			}).success,
		).toBe(true);
		expect(
			bridgePaneCommWorkerInstallSchema.safeParse({
				kind: 'bridgePaneCommWorker.install',
				wireVersion: 1,
				paneSessionId: 'pane-session-1',
				workerInstanceId: 'worker-instance-1',
				productCapability: shortCapability,
				productPort: productChannel.port1,
			}).success,
		).toBe(false);

		productChannel.port1.close();
		productChannel.port2.close();
	});

	test('transfers the install port and capability and proves sender detachment', async () => {
		const bootstrapChannel = new MessageChannel();
		const productChannel = new MessageChannel();
		const productCapability = new ArrayBuffer(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH);
		const receivedInstall = new Promise<unknown>((resolve) => {
			bootstrapChannel.port2.addEventListener(
				'message',
				(event): void => {
					resolve(event.data);
				},
				{ once: true },
			);
			bootstrapChannel.port2.start();
		});

		postBridgePaneCommWorkerInstall(bootstrapChannel.port1, {
			kind: 'bridgePaneCommWorker.install',
			wireVersion: 1,
			paneSessionId: 'pane-session-1',
			workerInstanceId: 'worker-instance-1',
			productCapability,
			productPort: productChannel.port1,
		});

		expect(productCapability.byteLength).toBe(0);
		const install = bridgePaneCommWorkerInstallSchema.parse(await receivedInstall);
		expect(install.productCapability.byteLength).toBe(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH);

		install.productPort.close();
		productChannel.port2.close();
		bootstrapChannel.port1.close();
		bootstrapChannel.port2.close();
	});

	test('encodes stream frames with an exact four-byte big-endian length prefix', () => {
		const frame = bridgeProductStreamFrameSchema.parse(validProductSessionCorpus.streamFrames[0]);
		const encoded = encodeBridgeProductStreamFrame(frame);
		const view = new DataView(encoded.buffer, encoded.byteOffset, encoded.byteLength);
		const declaredLength = view.getUint32(0, false);

		expect(declaredLength).toBe(encoded.byteLength - 4);
		expect(JSON.parse(new TextDecoder().decode(encoded.subarray(4)))).toEqual(frame);
	});
});

function schemaForHostileContract(
	contract: string,
):
	| typeof bridgeProductControlRequestSchema
	| typeof bridgeProductControlResponseSchema
	| typeof bridgeProductStreamFrameSchema
	| typeof bridgeProductResourceRequestIdentitySchema {
	switch (contract) {
		case 'request':
			return bridgeProductControlRequestSchema;
		case 'response':
			return bridgeProductControlResponseSchema;
		case 'streamFrame':
			return bridgeProductStreamFrameSchema;
		case 'resourceRequest':
			return bridgeProductResourceRequestIdentitySchema;
		default:
			throw new Error(`Unknown hostile contract: ${contract}`);
	}
}
