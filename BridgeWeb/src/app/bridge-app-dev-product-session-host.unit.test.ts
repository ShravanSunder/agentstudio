import { describe, expect, test } from 'vitest';

import { BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH } from '../core/comm-worker/bridge-product-contract-primitives.js';
import { bridgeProductSessionBootstrapSchema } from '../core/comm-worker/bridge-product-session-contracts.js';
import { installBridgeAppDevProductSessionHost } from './bridge-app-dev-product-session-host.js';

describe('Bridge app dev product session host', () => {
	test('issues a fresh schema-valid capability and worker bootstrap per request', () => {
		const target = new EventTarget();
		const responses: unknown[] = [];
		target.addEventListener('__bridge_product_session_bootstrap', (event): void => {
			responses.push('detail' in event ? event.detail : null);
		});
		const host = installBridgeAppDevProductSessionHost(target);

		target.dispatchEvent(
			new CustomEvent('__bridge_product_session_bootstrap_request', {
				detail: { reason: 'initial', requestId: 'request-1' },
			}),
		);
		target.dispatchEvent(
			new CustomEvent('__bridge_product_session_bootstrap_request', {
				detail: { reason: 'workerReplacement', requestId: 'request-2' },
			}),
		);

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

		host.dispose();
	});

	test('ignores malformed requests and stops after disposal', () => {
		const target = new EventTarget();
		let responseCount = 0;
		target.addEventListener('__bridge_product_session_bootstrap', (): void => {
			responseCount += 1;
		});
		const host = installBridgeAppDevProductSessionHost(target);

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

		expect(responseCount).toBe(0);
	});
});

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
