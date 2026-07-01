import { describe, expect, test } from 'vitest';

import { reviewTreeSelectionForEventTarget } from './bridge-trees-panel.js';

describe('BridgeReviewTreesPanel browser selection helpers', () => {
	test('maps Pierre button-shaped file row clicks to primary item ids', () => {
		const button = document.createElement('button');
		button.setAttribute('data-item-type', 'file');
		button.setAttribute('data-item-path', 'src/button-row.ts');

		expect(
			reviewTreeSelectionForEventTarget({
				primaryItemIdByTreePath: { 'src/button-row.ts': 'button-row-item' },
				target: button,
			}),
		).toEqual({
			itemId: 'button-row-item',
			path: 'src/button-row.ts',
		});
	});
});
