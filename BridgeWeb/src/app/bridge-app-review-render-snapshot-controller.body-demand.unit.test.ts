import { describe, expect, test } from 'vitest';

import { reviewCodeViewBodyDemandItemIds } from './bridge-app-review-render-snapshot-controller.js';

describe('Bridge app Review body demand', () => {
	test('derives body demand only from unique CodeView-visible item ids', () => {
		expect(
			reviewCodeViewBodyDemandItemIds(['item-selected', 'item-code-visible', 'item-code-visible']),
		).toEqual(['item-selected', 'item-code-visible']);
	});
});
