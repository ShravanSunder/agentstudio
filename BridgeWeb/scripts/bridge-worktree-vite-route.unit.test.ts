import { readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';

import { bridgeWorktreeDevProviderConfigCacheKey } from '../vite.config.js';

describe('BridgeWeb Vite product route cutover', () => {
	test('registers the typed product POST carrier and no legacy feature GET routes', () => {
		const viteSource = readFileSync(new URL('../vite.config.ts', import.meta.url), 'utf8');
		const bootstrapRouteIndex = viteSource.indexOf(
			'server.middlewares.use(BRIDGE_PRODUCT_DEV_BOOTSTRAP_ROUTE',
		);
		const commandRouteIndex = viteSource.indexOf(
			'server.middlewares.use(BRIDGE_PRODUCT_COMMAND_ROUTE',
		);
		const streamRouteIndex = viteSource.indexOf(
			'server.middlewares.use(BRIDGE_PRODUCT_STREAM_ROUTE',
		);
		const contentRouteIndex = viteSource.indexOf(
			'server.middlewares.use(BRIDGE_PRODUCT_CONTENT_ROUTE',
		);

		expect(bootstrapRouteIndex).toBeGreaterThanOrEqual(0);
		expect(viteSource).toContain(
			'void productCarrier.handleBootstrapRequest({ request, response })',
		);
		expect(viteSource).toContain('server.middlewares.use(BRIDGE_PRODUCT_COMMAND_ROUTE');
		expect(viteSource).toContain('server.middlewares.use(BRIDGE_PRODUCT_STREAM_ROUTE');
		expect(viteSource).toContain('server.middlewares.use(BRIDGE_PRODUCT_CONTENT_ROUTE');
		expect(bootstrapRouteIndex).toBeLessThan(commandRouteIndex);
		expect(commandRouteIndex).toBeLessThan(streamRouteIndex);
		expect(streamRouteIndex).toBeLessThan(contentRouteIndex);
		expect(viteSource).not.toContain('/__bridge-worktree/surface');
		expect(viteSource).not.toContain('/__bridge-worktree/file-descriptor');
		expect(viteSource).not.toContain('/__bridge-worktree/file-content');
		expect(viteSource).not.toContain('/__bridge-worktree/review-metadata');
		expect(viteSource).not.toContain('/__bridge-worktree/review-content');
	});

	test('keys provider caching by stable dev scenario rather than content identity', () => {
		const env = { BRIDGE_WEB_DEV_SCENARIO: undefined };

		expect(
			bridgeWorktreeDevProviderConfigCacheKey({
				env,
				requestUrl: '/__bridge-product/content?scenario=current-worktree&request=one',
			}),
		).toBe(
			bridgeWorktreeDevProviderConfigCacheKey({
				env,
				requestUrl: '/__bridge-product/content?scenario=current-worktree&request=two',
			}),
		);
	});

	test('does not cache non-loopback absolute provider config requests', () => {
		expect(
			bridgeWorktreeDevProviderConfigCacheKey({
				env: {},
				requestUrl: 'https://example.test/__bridge-product/content?scenario=current-worktree',
			}),
		).toBeNull();
	});
});
