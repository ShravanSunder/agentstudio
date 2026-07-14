import { describe, expect, test } from 'vitest';

import {
	BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
	BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
	BRIDGE_PRODUCT_WIRE_VERSION,
} from './bridge-product-contract-primitives.js';
import {
	decodeBridgeProductDevBootstrapDelivery,
	encodeBridgeProductDevBootstrapDelivery,
	type BridgeProductDevBootstrapDelivery,
} from './bridge-product-dev-bootstrap.js';
import { bridgeProductSessionBootstrapSchema } from './bridge-product-session-contracts.js';

describe('Bridge product dev bootstrap binary envelope', () => {
	test('round-trips one versioned delivery, consumes its source, and returns distinct capability storage', () => {
		// Arrange
		const delivery = productBootstrapDelivery();
		const expectedCapability = [...new Uint8Array(delivery.productCapability)];
		const envelope = encodeBridgeProductDevBootstrapDelivery(delivery);
		const envelopeBuffer = envelope.buffer;

		// Act
		const decoded = decodeBridgeProductDevBootstrapDelivery(envelope);

		// Assert
		expect(envelope[0]).toBe(0);
		expect([...envelope]).toEqual(Array.from({ length: envelope.byteLength }, () => 0));
		expect(decoded.bootstrap).toEqual(delivery.bootstrap);
		expect(decoded.productCapability.byteLength).toBe(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH);
		expect([...new Uint8Array(decoded.productCapability)]).toEqual(expectedCapability);
		expect(decoded.productCapability).not.toBe(envelopeBuffer);
	});

	test('rejects truncated, unsupported-version, oversized-metadata, and extra-byte envelopes', () => {
		// Arrange
		const validEnvelope = encodeBridgeProductDevBootstrapDelivery(productBootstrapDelivery());
		const truncated = validEnvelope.slice(0, BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH);
		const unsupportedVersion = validEnvelope.slice();
		unsupportedVersion[0] = 2;
		const oversizedMetadata = validEnvelope.slice();
		new DataView(oversizedMetadata.buffer).setUint32(1, 4 * 1024 + 1, false);
		const extraByte = new Uint8Array(validEnvelope.byteLength + 1);
		extraByte.set(validEnvelope);

		// Act / Assert
		expect(() => decodeBridgeProductDevBootstrapDelivery(truncated)).toThrow('truncated');
		expect(() => decodeBridgeProductDevBootstrapDelivery(unsupportedVersion)).toThrow(
			'version is unsupported',
		);
		expect(() => decodeBridgeProductDevBootstrapDelivery(oversizedMetadata)).toThrow(
			'metadata exceeds its byte limit',
		);
		expect(() => decodeBridgeProductDevBootstrapDelivery(extraByte)).toThrow('invalid byte length');
	});

	test('rejects encoding a delivery without one exact 32-byte capability', () => {
		// Arrange
		const delivery = productBootstrapDelivery();
		const invalidDelivery = {
			...delivery,
			productCapability: new ArrayBuffer(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH - 1),
		};

		// Act / Assert
		expect(() => encodeBridgeProductDevBootstrapDelivery(invalidDelivery)).toThrow(
			'invalid byte length',
		);
	});
});

function productBootstrapDelivery(): BridgeProductDevBootstrapDelivery {
	const productCapability = Uint8Array.from(
		{ length: BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH },
		(_, index): number => index,
	).buffer;
	return {
		bootstrap: bridgeProductSessionBootstrapSchema.parse({
			kind: 'productSession.bootstrap',
			paneSessionId: 'vite-dev-pane-session',
			policy: {
				maximumContentBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
				maximumMetadataFrameBytes: BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
				maximumQueuedStreamBytes: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
				maximumQueuedStreamFrames: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
				maximumRequestBodyBytes: BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
				terminalFrameReserve: BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
			},
			wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			workerInstanceId: 'vite-dev-worker-1',
		}),
		productCapability,
	};
}
