import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

import * as devRoutes from './bridge-product-dev-routes.js';
import * as productionRoutes from './bridge-product-routes.js';

describe('Bridge product route build separation', () => {
	test('keeps the production carrier fixed to three capability-bound custom-scheme POST routes', () => {
		expect(routeValues(productionRoutes)).toEqual({
			BRIDGE_PRODUCT_CAPABILITY_HEADER_NAME: 'X-AgentStudio-Bridge-Product-Capability',
			BRIDGE_PRODUCT_COMMAND_ROUTE: 'agentstudio://rpc/command',
			BRIDGE_PRODUCT_CONTENT_ROUTE: 'agentstudio://rpc/content',
			BRIDGE_PRODUCT_REQUEST_METHOD: 'POST',
			BRIDGE_PRODUCT_STREAM_ROUTE: 'agentstudio://rpc/stream',
		});
		const productionSource = readSource('./bridge-product-routes.ts');
		expect(productionSource).not.toMatch(/import\.meta\.env|process\.env|localhost|127\.0\.0\.1/u);
	});

	test('keeps relative HTTP routes in the Vite-only alias module', () => {
		expect(routeValues(devRoutes)).toEqual({
			BRIDGE_PRODUCT_CAPABILITY_HEADER_NAME: 'X-AgentStudio-Bridge-Product-Capability',
			BRIDGE_PRODUCT_COMMAND_ROUTE: '/__bridge-product/command',
			BRIDGE_PRODUCT_CONTENT_ROUTE: '/__bridge-product/content',
			BRIDGE_PRODUCT_REQUEST_METHOD: 'POST',
			BRIDGE_PRODUCT_STREAM_ROUTE: '/__bridge-product/stream',
		});
		const viteSource = readSource('../../../vite.config.ts');
		expect(viteSource).toContain("find: './bridge-product-routes.js'");
		expect(viteSource).toContain('bridge-product-dev-routes.ts');
	});
});

function readSource(relativePath: string): string {
	return readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), 'utf8');
}

function routeValues(routes: {
	readonly BRIDGE_PRODUCT_CAPABILITY_HEADER_NAME: string;
	readonly BRIDGE_PRODUCT_COMMAND_ROUTE: string;
	readonly BRIDGE_PRODUCT_CONTENT_ROUTE: string;
	readonly BRIDGE_PRODUCT_REQUEST_METHOD: string;
	readonly BRIDGE_PRODUCT_STREAM_ROUTE: string;
}): Record<string, string> {
	return {
		BRIDGE_PRODUCT_CAPABILITY_HEADER_NAME: routes.BRIDGE_PRODUCT_CAPABILITY_HEADER_NAME,
		BRIDGE_PRODUCT_COMMAND_ROUTE: routes.BRIDGE_PRODUCT_COMMAND_ROUTE,
		BRIDGE_PRODUCT_CONTENT_ROUTE: routes.BRIDGE_PRODUCT_CONTENT_ROUTE,
		BRIDGE_PRODUCT_REQUEST_METHOD: routes.BRIDGE_PRODUCT_REQUEST_METHOD,
		BRIDGE_PRODUCT_STREAM_ROUTE: routes.BRIDGE_PRODUCT_STREAM_ROUTE,
	};
}
