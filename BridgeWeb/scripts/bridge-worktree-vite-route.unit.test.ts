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

	test('accepts only loopback HTTP origins', () => {
		expect(resolveBridgeProductDevBackendOrigin({})).toBe('http://127.0.0.1:43871');
		expect(
			resolveBridgeProductDevBackendOrigin({
				BRIDGE_WEB_DEV_BACKEND_ORIGIN: 'http://localhost:43872',
			}),
		).toBe('http://localhost:43872');
		expect(() =>
			resolveBridgeProductDevBackendOrigin({
				BRIDGE_WEB_DEV_BACKEND_ORIGIN: 'https://127.0.0.1:43871',
			}),
		).toThrow(/loopback HTTP origin/u);
		expect(() =>
			resolveBridgeProductDevBackendOrigin({
				BRIDGE_WEB_DEV_BACKEND_ORIGIN: 'http://example.test:43871',
			}),
		).toThrow(/loopback HTTP origin/u);
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
});
