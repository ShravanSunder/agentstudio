import { describe, expect, test } from 'vitest';

import { createBridgeBodyRegistry } from './bridge-body-registry.js';

describe('bridge body registry', () => {
	test('stores bodies outside app state and evicts least recently used entries by bytes', () => {
		const registry = createBridgeBodyRegistry({ maxBytes: 10 });

		registry.put({
			cacheKey: 'a',
			freshnessKey: 'fresh-a',
			body: '12345',
			byteLength: 5,
		});
		registry.put({
			cacheKey: 'b',
			freshnessKey: 'fresh-b',
			body: '67890',
			byteLength: 5,
		});
		expect(registry.get({ cacheKey: 'a', freshnessKey: 'fresh-a' })).toBe('12345');
		registry.put({
			cacheKey: 'c',
			freshnessKey: 'fresh-c',
			body: 'xyz',
			byteLength: 3,
		});

		expect(registry.get({ cacheKey: 'a', freshnessKey: 'fresh-a' })).toBe('12345');
		expect(registry.get({ cacheKey: 'b', freshnessKey: 'fresh-b' })).toBeNull();
		expect(registry.get({ cacheKey: 'c', freshnessKey: 'fresh-c' })).toBe('xyz');
		expect(registry.snapshot()).toEqual({
			entryCount: 2,
			totalBytes: 8,
		});
	});

	test('evicts stale freshness entries explicitly on reset', () => {
		const registry = createBridgeBodyRegistry({ maxBytes: 100 });

		registry.put({
			cacheKey: 'descriptor-1',
			freshnessKey: 'revision-1',
			body: 'old',
			byteLength: 3,
		});
		registry.put({
			cacheKey: 'descriptor-1',
			freshnessKey: 'revision-2',
			body: 'new',
			byteLength: 3,
		});

		expect(registry.evictStale({ cacheKey: 'descriptor-1', keepFreshnessKey: 'revision-2' })).toBe(
			1,
		);
		expect(registry.get({ cacheKey: 'descriptor-1', freshnessKey: 'revision-1' })).toBeNull();
		expect(registry.get({ cacheKey: 'descriptor-1', freshnessKey: 'revision-2' })).toBe('new');
	});
});
