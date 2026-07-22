import { describe, expect, test } from 'vitest';

import { bridgePierreContentDescriptorCacheKey } from './bridge-pierre-worker-content-descriptor.js';

describe('Bridge Pierre content identity', () => {
	test('derives the stable content-addressed cache key without resource authority', () => {
		expect(
			bridgePierreContentDescriptorCacheKey({
				contentHash: 'abc123',
				contentHashAlgorithm: 'sha256',
			}),
		).toBe('pierre-content:sha256:abc123');
	});
});
