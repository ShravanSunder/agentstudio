import { describe, expect, test } from 'vitest';

import { parseBridgeContentResourceUrl } from './bridge-resource-url.js';

describe('bridge resource URL', () => {
	test('parses content handle and generation', () => {
		const parsed = parseBridgeContentResourceUrl(
			'agentstudio://resource/content/handle-1?generation=7',
		);

		expect(parsed).toEqual({ handleId: 'handle-1', generation: 7 });
	});
});
