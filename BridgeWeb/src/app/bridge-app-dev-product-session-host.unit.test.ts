import { readFile } from 'node:fs/promises';

import { describe, expect, test, vi } from 'vitest';

import {
	BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
	BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
	BRIDGE_PRODUCT_WIRE_VERSION,
} from '../core/comm-worker/bridge-product-contract-primitives.js';
import {
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_REQUEST_MEDIA_TYPE,
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_RESPONSE_MEDIA_TYPE,
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE,
	encodeBridgeProductDevBootstrapDelivery,
	type BridgeProductDevBootstrapDelivery,
} from '../core/comm-worker/bridge-product-dev-bootstrap.js';
import { bridgeProductSessionBootstrapSchema } from '../core/comm-worker/bridge-product-session-contracts.js';
import { installBridgeAppDevProductSessionHost } from './bridge-app-dev-product-session-host.js';

describe('Bridge app dev product session host', () => {
	test('keeps product capability minting out of page JavaScript', async () => {
		// Arrange
		const source = await readFile(
			new URL('./bridge-app-dev-product-session-host.ts', import.meta.url),
			'utf8',
		);

		// Act
		const pageMintsProductCapability =
			source.includes('crypto.getRandomValues') ||
			source.includes('BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH');

		// Assert
		expect(pageMintsProductCapability).toBe(false);
		expect(source).toContain('props.fetchBootstrap(');
		expect(source).toContain('BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE');
	});

	test('obtains fresh registered bootstraps from the server-owned POST route', async () => {
		// Arrange
		const target = new EventTarget();
		const deliveries = [productBootstrapDelivery(1), productBootstrapDelivery(2)];
		let deliveryIndex = 0;
		const fetchBootstrap = vi.fn<typeof fetch>(async () => {
			const delivery = deliveries[deliveryIndex];
			if (delivery === undefined) throw new Error('Unexpected bootstrap request.');
			deliveryIndex += 1;
			const envelope = encodeBridgeProductDevBootstrapDelivery(delivery);
			return new Response(envelope.buffer as ArrayBuffer, {
				headers: { 'Content-Type': BRIDGE_PRODUCT_DEV_BOOTSTRAP_RESPONSE_MEDIA_TYPE },
				status: 200,
			});
		});
		const responses: unknown[] = [];
		const waitForResponse = (): Promise<void> =>
			new Promise<void>((resolve): void => {
				target.addEventListener(
					'__bridge_product_session_bootstrap',
					(event): void => {
						responses.push('detail' in event ? event.detail : null);
						resolve();
					},
					{ once: true },
				);
			});
		const host = installBridgeAppDevProductSessionHost({ fetchBootstrap, target });

		// Act
		const firstResponse = waitForResponse();
		target.dispatchEvent(
			new CustomEvent('__bridge_product_session_bootstrap_request', {
				detail: { reason: 'initial', requestId: 'request-1' },
			}),
		);
		await firstResponse;
		const secondResponse = waitForResponse();
		target.dispatchEvent(
			new CustomEvent('__bridge_product_session_bootstrap_request', {
				detail: { reason: 'workerReplacement', requestId: 'request-2' },
			}),
		);
		await secondResponse;

		// Assert
		expect(responses).toHaveLength(2);
		const first = parseResponse(responses[0]);
		const second = parseResponse(responses[1]);
		expect(first.requestId).toBe('request-1');
		expect(second.requestId).toBe('request-2');
		expect(first.bootstrap.workerInstanceId).not.toBe(second.bootstrap.workerInstanceId);
		expect(first.productCapability.byteLength).toBe(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH);
		expect(second.productCapability.byteLength).toBe(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH);
		expect([...new Uint8Array(first.productCapability)]).not.toEqual([
			...new Uint8Array(second.productCapability),
		]);
		expect(fetchBootstrap).toHaveBeenCalledTimes(2);
		const firstFetch = fetchBootstrap.mock.calls[0];
		const secondFetch = fetchBootstrap.mock.calls[1];
		expect(firstFetch?.[0]).toBe(BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE);
		expect(firstFetch?.[1]).toMatchObject({
			body: JSON.stringify({ reason: 'initial' }),
			cache: 'no-store',
			credentials: 'same-origin',
			headers: { 'Content-Type': BRIDGE_PRODUCT_DEV_BOOTSTRAP_REQUEST_MEDIA_TYPE },
			method: 'POST',
		});
		expect(secondFetch?.[1]).toMatchObject({
			body: JSON.stringify({
				paneSessionId: first.bootstrap.paneSessionId,
				reason: 'workerReplacement',
			}),
			method: 'POST',
		});

		host.dispose();
	});

	test('binds the default browser fetch receiver before requesting the initial bootstrap', async () => {
		// Arrange
		const target = new EventTarget();
		const delivery = productBootstrapDelivery(1);
		const envelope = encodeBridgeProductDevBootstrapDelivery(delivery);
		const originalFetch = globalThis.fetch;
		const observedFetchReceivers: unknown[] = [];
		globalThis.fetch = vi.fn(function (this: unknown): Promise<Response> {
			observedFetchReceivers.push(this);
			return Promise.resolve(
				new Response(envelope.buffer as ArrayBuffer, {
					headers: { 'Content-Type': BRIDGE_PRODUCT_DEV_BOOTSTRAP_RESPONSE_MEDIA_TYPE },
					status: 200,
				}),
			);
		});
		const response = new Promise<void>((resolve): void => {
			target.addEventListener('__bridge_product_session_bootstrap', (): void => resolve(), {
				once: true,
			});
		});
		const host = installBridgeAppDevProductSessionHost({ target });

		try {
			// Act
			target.dispatchEvent(
				new CustomEvent('__bridge_product_session_bootstrap_request', {
					detail: { reason: 'initial', requestId: 'request-default-fetch' },
				}),
			);
			await response;

			// Assert
			expect(observedFetchReceivers).toEqual([globalThis]);
		} finally {
			host.dispose();
			globalThis.fetch = originalFetch;
		}
	});

	test('ignores malformed requests and stops after disposal', () => {
		// Arrange
		const target = new EventTarget();
		const fetchBootstrap = vi.fn<typeof fetch>();
		let responseCount = 0;
		target.addEventListener('__bridge_product_session_bootstrap', (): void => {
			responseCount += 1;
		});
		const host = installBridgeAppDevProductSessionHost({ fetchBootstrap, target });

		// Act
		target.dispatchEvent(
			new CustomEvent('__bridge_product_session_bootstrap_request', {
				detail: { reason: 'unknown', requestId: 'request-1' },
			}),
		);
		host.dispose();
		target.dispatchEvent(
			new CustomEvent('__bridge_product_session_bootstrap_request', {
				detail: { reason: 'initial', requestId: 'request-2' },
			}),
		);

		// Assert
		expect(responseCount).toBe(0);
		expect(fetchBootstrap).not.toHaveBeenCalled();
	});
});

function productBootstrapDelivery(sequence: number): BridgeProductDevBootstrapDelivery {
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
			workerInstanceId: `vite-dev-worker-${sequence}`,
		}),
		productCapability: Uint8Array.from(
			{ length: BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH },
			(_, index): number => (index + sequence) % 256,
		).buffer,
	};
}

function parseResponse(value: unknown): {
	readonly bootstrap: ReturnType<typeof bridgeProductSessionBootstrapSchema.parse>;
	readonly productCapability: ArrayBuffer;
	readonly requestId: string;
} {
	if (
		typeof value !== 'object' ||
		value === null ||
		!('bootstrap' in value) ||
		!('productCapability' in value) ||
		!('requestId' in value) ||
		!(value.productCapability instanceof ArrayBuffer) ||
		typeof value.requestId !== 'string'
	) {
		throw new Error('Invalid dev product session response.');
	}
	return {
		bootstrap: bridgeProductSessionBootstrapSchema.parse(value.bootstrap),
		productCapability: value.productCapability,
		requestId: value.requestId,
	};
}
