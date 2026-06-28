import { describe, expect, test } from 'vitest';

import { makeBridgeContentHandle } from '../review-package/bridge-review-package-test-support.js';
import { ReviewContentCache } from './review-content-cache.js';

describe('review content cache', () => {
	test('evicts least recently used content', () => {
		const cache = new ReviewContentCache(1);
		const firstHandle = makeBridgeContentHandle('item-one', 'head');
		const secondHandle = makeBridgeContentHandle('item-two', 'head');

		cache.set({ handle: firstHandle, readText: (): string => 'one' });
		cache.set({ handle: secondHandle, readText: (): string => 'two' });

		expect(cache.get(firstHandle.handleId)).toBeUndefined();
		expect(cache.get(secondHandle.handleId)?.readText()).toBe('two');
	});
});
