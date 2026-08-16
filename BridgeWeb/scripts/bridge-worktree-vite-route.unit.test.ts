import { describe, expect, test } from 'vitest';

import {
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE,
	BRIDGE_PRODUCT_DEV_HEALTH_ROUTE,
} from '../src/core/comm-worker/bridge-product-dev-bootstrap.js';
import {
	BRIDGE_PRODUCT_HTTP_COMMAND_ENDPOINT,
	BRIDGE_PRODUCT_HTTP_CONTENT_ENDPOINT,
	BRIDGE_PRODUCT_HTTP_STREAM_ENDPOINT,
} from '../src/core/comm-worker/bridge-product-http-request-executor.js';
import {
	bridgeProductDevProxyConfiguration,
	bridgeProductDevBackendShouldBeSupervised,
	resolveBridgeProductDevBackendOrigin,
} from '../vite.config.js';
import { bridgeDevelopmentServerHealthResponseIsReady } from './dev-server/bridge-development-server-process.js';

describe('BridgeWeb Vite product proxy', () => {
	test('proxies exactly the five development product routes to one Swift backend origin', () => {
		const backendOrigin = 'http://127.0.0.1:43871';
		const proxy = bridgeProductDevProxyConfiguration(backendOrigin);

		expect(Object.keys(proxy)).toEqual([
			BRIDGE_PRODUCT_DEV_HEALTH_ROUTE,
			BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE,
			BRIDGE_PRODUCT_HTTP_COMMAND_ENDPOINT,
			BRIDGE_PRODUCT_HTTP_STREAM_ENDPOINT,
			BRIDGE_PRODUCT_HTTP_CONTENT_ENDPOINT,
		]);
		for (const route of Object.values(proxy)) {
			expect(route.target).toBe(backendOrigin);
		}
	});

	test('reserves an isolated loopback origin for each supervised Vite session', async () => {
		// Removing dynamic reservation would let Vite attach to an unrelated backend on a fixed port.
		expect(
			await resolveBridgeProductDevBackendOrigin({}, async (): Promise<number> => 43_987),
		).toBe('http://127.0.0.1:43987');
	});

	test('accepts only explicitly configured loopback HTTP origins', async () => {
		let reservePortCallCount = 0;
		expect(
			await resolveBridgeProductDevBackendOrigin(
				{
					BRIDGE_WEB_DEV_BACKEND_ORIGIN: 'http://localhost:43872',
				},
				async (): Promise<number> => {
					reservePortCallCount += 1;
					return 43_987;
				},
			),
		).toBe('http://localhost:43872');
		expect(reservePortCallCount).toBe(0);
		await expect(
			resolveBridgeProductDevBackendOrigin({
				BRIDGE_WEB_DEV_BACKEND_ORIGIN: 'https://127.0.0.1:43871',
			}),
		).rejects.toThrow(/loopback HTTP origin/u);
		await expect(
			resolveBridgeProductDevBackendOrigin({
				BRIDGE_WEB_DEV_BACKEND_ORIGIN: 'http://example.test:43871',
			}),
		).rejects.toThrow(/loopback HTTP origin/u);
	});

	test('accepts only a no-content development server health response as ready', () => {
		expect(bridgeDevelopmentServerHealthResponseIsReady(new Response(null, { status: 204 }))).toBe(
			true,
		);
		expect(bridgeDevelopmentServerHealthResponseIsReady(new Response(null, { status: 200 }))).toBe(
			false,
		);
		expect(bridgeDevelopmentServerHealthResponseIsReady(new Response(null, { status: 404 }))).toBe(
			false,
		);
	});

	test('supervises the default backend but leaves an explicitly configured backend alone', () => {
		// An E2E fixture supplies and owns its own backend process; double ownership would collide.
		expect(bridgeProductDevBackendShouldBeSupervised({})).toBe(true);
		expect(
			bridgeProductDevBackendShouldBeSupervised({
				BRIDGE_WEB_DEV_BACKEND_ORIGIN: 'http://127.0.0.1:43872',
			}),
		).toBe(false);
	});
});
