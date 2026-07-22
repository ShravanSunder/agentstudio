import { describe, expect, test } from 'vitest';

import {
	reviewTreeItemIdsForPierreVisibleFileRows,
	reviewTreeSelectionForEventTarget,
} from './bridge-trees-panel.js';

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

	test('maps visible Pierre file rows to deduped review item ids', () => {
		expect(
			reviewTreeItemIdsForPierreVisibleFileRows({
				primaryItemIdByTreePath: {
					'src/first.ts': 'item-first',
					'src/duplicate-a.ts': 'item-duplicate',
					'src/duplicate-b.ts': 'item-duplicate',
				},
				rowElements: [
					new RecordingReviewTreeRowElement('src/first.ts'),
					new RecordingReviewTreeRowElement('src/missing.ts'),
					new RecordingReviewTreeRowElement('src/duplicate-a.ts'),
					new RecordingReviewTreeRowElement('src/duplicate-b.ts'),
					new RecordingReviewTreeRowElement(null),
				],
			}),
		).toEqual(['item-first', 'item-duplicate']);
	});
});

class RecordingReviewTreeRowElement {
	constructor(private readonly path: string | null) {}

	getAttribute(name: string): string | null {
		return name === 'data-item-path' ? this.path : null;
	}
}
