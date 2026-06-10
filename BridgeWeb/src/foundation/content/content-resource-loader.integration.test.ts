import { describe, expect, test } from 'vitest';

import { makeBridgeContentHandle } from '../review-package/bridge-review-package-test-support.js';
import { loadBridgeContentResource } from './content-resource-loader.js';

describe('content resource loader', () => {
	test('loads text from the scoped bridge content URL', async () => {
		const handle = makeBridgeContentHandle('item-source', 'head');
		const loaded = await loadBridgeContentResource(
			handle,
			async (url: string): Promise<Response> => {
				expect(url).toBe(handle.resourceUrl);
				return new Response('hello bridge');
			},
		);

		expect(loaded.text).toBe('hello bridge');
		expect(loaded.handle).toEqual(handle);
	});
});
